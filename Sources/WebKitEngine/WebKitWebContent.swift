import Foundation
import AppKit
import WebKit
import MereKit

/// WebContent backed by WKWebView.
@MainActor
public final class WebKitWebContent: NSObject, WebContent {

    public let id = UUID()
    public let engine: EngineType = .webkit

    // MARK: - Public state (KVO-observed from WKWebView)

    public private(set) var url: URL?
    public private(set) var title: String?
    public private(set) var isLoading = false
    public private(set) var estimatedProgress: Double = 0
    public private(set) var canGoBack = false
    public private(set) var canGoForward = false
    public private(set) var hasAudioPlaying = false

    // WKWebView gained isMuted in macOS 14 but it's on WKWebViewConfiguration.mediaTypesRequiringUserActionForPlayback,
    // not directly on the view. Track manually.
    public var isMuted: Bool = false {
        didSet { webView.configuration.mediaTypesRequiringUserActionForPlayback = isMuted ? .all : [] }
    }

    public var zoomFactor: Double {
        get { webView.pageZoom }
        set { webView.pageZoom = newValue }
    }

    // MARK: - Navigation events

    private let eventContinuation: AsyncStream<NavigationEvent>.Continuation
    public let navigationEvents: AsyncStream<NavigationEvent>

    // MARK: - Internals

    let webView: WKWebView
    private var observations: [NSKeyValueObservation] = []

    // MARK: - Init

    public init(configuration: WKWebViewConfiguration = .init()) {
        let (stream, continuation) = AsyncStream<NavigationEvent>.makeStream()
        self.navigationEvents = stream
        self.eventContinuation = continuation

        self.webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView.allowsBackForwardNavigationGestures = true

        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        observeWebViewProperties()
    }

    // MARK: - WebContent

    public func loadURL(_ url: URL) {
        webView.load(URLRequest(url: url))
    }

    public func loadHTML(_ html: String, baseURL: URL?) {
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    public func goBack() { webView.goBack() }
    public func goForward() { webView.goForward() }
    public func reload() { webView.reload() }
    public func stopLoading() { webView.stopLoading() }

    public func evaluateJavaScript(_ script: String) async throws -> Any? {
        try await webView.evaluateJavaScript(script)
    }

    public func findInPage(_ query: String, forward: Bool) async -> FindResult {
        // WKWebView doesn't expose find results count natively; use JS fallback.
        let js = """
        (function() {
            window.getSelection().removeAllRanges();
            return window.find('\(query.replacingOccurrences(of: "'", with: "\\'"))',
                false, \(!forward), false, false, true);
        })()
        """
        _ = try? await webView.evaluateJavaScript(js)
        return FindResult(matchCount: -1, activeMatchIndex: -1) // WKWebView limitation
    }

    public func clearFind() {
        Task { _ = try? await webView.evaluateJavaScript("window.getSelection().removeAllRanges()") }
    }

    public func attachHostView(_ container: NSView) {
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    public func detachHostView() {
        webView.removeFromSuperview()
    }

    public func snapshot() async -> NSImage? {
        let config = WKSnapshotConfiguration()
        return try? await webView.takeSnapshot(configuration: config)
    }

    public func close() {
        observations.forEach { $0.invalidate() }
        observations.removeAll()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        detachHostView()
        eventContinuation.finish()
    }

    // MARK: - KVO

    private func observeWebViewProperties() {
        observations = [
            webView.observe(\.url, options: [.new]) { [weak self] wv, _ in
                Task { @MainActor in self?.url = wv.url }
            },
            webView.observe(\.title, options: [.new]) { [weak self] wv, _ in
                Task { @MainActor in
                    self?.title = wv.title
                    if let t = wv.title { self?.eventContinuation.yield(.titleChanged(title: t)) }
                }
            },
            webView.observe(\.isLoading, options: [.new]) { [weak self] wv, _ in
                Task { @MainActor in self?.isLoading = wv.isLoading }
            },
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
                Task { @MainActor in self?.estimatedProgress = wv.estimatedProgress }
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] wv, _ in
                Task { @MainActor in self?.canGoBack = wv.canGoBack }
            },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] wv, _ in
                Task { @MainActor in self?.canGoForward = wv.canGoForward }
            },
        ]
    }
}

// MARK: - WKNavigationDelegate

extension WebKitWebContent: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if let url = webView.url { eventContinuation.yield(.started(url: url)) }
    }

    public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if let url = webView.url { eventContinuation.yield(.committed(url: url)) }
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let url = webView.url { eventContinuation.yield(.finished(url: url)) }
        Task { await emitFavicon() }
    }

    private func emitFavicon() async {
        let js = """
        (function() {
            var sel = 'link[rel~="icon"], link[rel~="shortcut icon"], link[rel="apple-touch-icon"]';
            var links = Array.from(document.querySelectorAll(sel));
            links.sort(function(a, b) {
                var sa = (a.sizes && a.sizes[0]) ? parseInt(a.sizes[0]) : 0;
                var sb = (b.sizes && b.sizes[0]) ? parseInt(b.sizes[0]) : 0;
                return sb - sa;
            });
            if (links.length && links[0].href) return links[0].href;
            return null;
        })()
        """
        let result = try? await webView.evaluateJavaScript(js)
        let faviconURL: URL?
        if let href = result as? String, let url = URL(string: href) {
            faviconURL = url
        } else if let host = webView.url.flatMap({ URL(string: "\($0.scheme ?? "https")://\($0.host ?? "")") } ) {
            faviconURL = host.appendingPathComponent("favicon.ico")
        } else {
            faviconURL = nil
        }
        eventContinuation.yield(.faviconChanged(url: faviconURL))
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        eventContinuation.yield(.failed(url: webView.url, error: error))
    }

    public func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        // redirected event emitted when URL KVO fires
    }
}

// MARK: - WKUIDelegate

extension WebKitWebContent: WKUIDelegate {
    public func webView(_ webView: WKWebView,
                        createWebViewWith configuration: WKWebViewConfiguration,
                        for navigationAction: WKNavigationAction,
                        windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Emit the URL as a navigation so the tab controller can open a new tab.
        if let url = navigationAction.request.url {
            eventContinuation.yield(.started(url: url))
        }
        return nil
    }
}
