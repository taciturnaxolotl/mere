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
    private var pendingReloadURL: URL?
    private var reloadAttempt = 0

    // MARK: - Init

    public override convenience init() {
        self.init(configuration: WKWebViewConfiguration())
    }

    public init(configuration: WKWebViewConfiguration) {
        let (stream, continuation) = AsyncStream<NavigationEvent>.makeStream()
        self.navigationEvents = stream
        self.eventContinuation = continuation

        // Audio: forwards play/pause state via message handler.
        configuration.userContentController.addUserScript(WKUserScript(
            source: """
            (function() {
                function notify() {
                    var playing = Array.from(document.querySelectorAll('video,audio'))
                        .some(function(m){ return !m.paused && !m.muted && m.volume > 0; });
                    window.webkit.messageHandlers.mereAudio.postMessage(playing);
                }
                document.addEventListener('play', notify, true);
                document.addEventListener('pause', notify, true);
                document.addEventListener('volumechange', notify, true);
            })();
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        ))

        // Console logging for debugging
        configuration.userContentController.addUserScript(WKUserScript(
            source: """
            (function() {
                const originalLog = console.log;
                const originalError = console.error;
                const originalWarn = console.warn;

                console.log = function() {
                    originalLog.apply(console, arguments);
                    const args = Array.from(arguments).map(String);
                    window.webkit.messageHandlers.mereConsole.postMessage('LOG: ' + args.join(' '));
                };

                console.error = function() {
                    originalError.apply(console, arguments);
                    const args = Array.from(arguments).map(String);
                    window.webkit.messageHandlers.mereConsole.postMessage('ERROR: ' + args.join(' '));
                };

                console.warn = function() {
                    originalWarn.apply(console, arguments);
                    const args = Array.from(arguments).map(String);
                    window.webkit.messageHandlers.mereConsole.postMessage('WARN: ' + args.join(' '));
                };
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))

        // Theme colour detection. Priority order:
        //   1. meta[name="theme-color"] — explicit, always wins
        //   2. elementFromPoint walk — finds the actual rendered background
        //      regardless of which element holds it (wrapper divs, app roots, etc.)
        // Triggers: documentEnd, window load, html/body attr mutations,
        // and <head> childList (for SPAs that inject meta[name="theme-color"]).
        configuration.userContentController.addUserScript(WKUserScript(
            source: """
            (function() {
                var _lastColor = null;
                function elBg(el) {
                    var bg = window.getComputedStyle(el).backgroundColor;
                    if (bg && bg !== 'rgba(0, 0, 0, 0)' && bg !== 'transparent') return bg;
                    // Also check legacy bgcolor attribute (used by HN and old-school HTML)
                    var attr = el.getAttribute ? el.getAttribute('bgcolor') : null;
                    if (attr) return attr;
                    return null;
                }
                function readColor() {
                    var m = document.querySelector('meta[name="theme-color"]');
                    if (m && m.content) return m.content;
                    // Walk up from the center of the page to find the background.
                    var el = document.elementFromPoint(
                        window.innerWidth / 2, window.innerHeight / 2);
                    while (el && el.nodeType === 1) {
                        var bg = elBg(el);
                        if (bg) return bg;
                        el = el.parentElement;
                    }
                    return null;
                }
                function report() {
                    var c = readColor();
                    if (c && c !== _lastColor) {
                        _lastColor = c;
                        window.webkit.messageHandlers.mereTheme.postMessage(c);
                    }
                }
                report();
                window.addEventListener('load', report);
                var attrObs = new MutationObserver(report);
                var attrOpts = { attributes: true, attributeFilter: ['style', 'class'] };
                attrObs.observe(document.documentElement, attrOpts);
                if (document.body) attrObs.observe(document.body, attrOpts);
                if (document.head) {
                    var headObs = new MutationObserver(function(ms) {
                        for (var i = 0; i < ms.length; i++) {
                            for (var j = 0; j < ms[i].addedNodes.length; j++) {
                                if (ms[i].addedNodes[j].nodeName === 'META') { report(); return; }
                            }
                        }
                    });
                    headObs.observe(document.head, { childList: true });
                }
            })();
            console.log('📄 Page loaded, document.styleSheets.length:', document.styleSheets.length);
            console.log('📄 StyleSheets:', Array.from(document.styleSheets).map(s => s.href));
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))

        self.webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView.allowsBackForwardNavigationGestures = true

        #if DEBUG
        // Enable Web Inspector for Safari
        self.webView.isInspectable = true
        #endif

        super.init()

        // Use a weak wrapper to avoid retain cycles through userContentController.
        let weak = WeakScriptMessageHandler(self)
        configuration.userContentController.add(weak, name: "mereAudio")
        configuration.userContentController.add(weak, name: "mereTheme")
        configuration.userContentController.add(weak, name: "mereConsole")

        webView.navigationDelegate = self
        webView.uiDelegate = self
        observeWebViewProperties()
    }

    // MARK: - WebContent

    public func loadURL(_ url: URL) {
        print("🌐 WebKitWebContent.loadURL: \(url.absoluteString)")
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

    public func suspend() {
        // Tell the page it is hidden — well-behaved pages pause rAF, timers, etc.
        Task {
            _ = try? await webView.evaluateJavaScript("""
            (function() {
                Object.defineProperty(document,'hidden',{value:true,configurable:true});
                Object.defineProperty(document,'visibilityState',{value:'hidden',configurable:true});
                document.dispatchEvent(new Event('visibilitychange'));
            })()
            """)
        }
    }

    public func resume() {
        Task {
            _ = try? await webView.evaluateJavaScript("""
            (function() {
                Object.defineProperty(document,'hidden',{value:false,configurable:true});
                Object.defineProperty(document,'visibilityState',{value:'visible',configurable:true});
                document.dispatchEvent(new Event('visibilitychange'));
            })()
            """)
        }
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
        reloadAttempt = 0
        pendingReloadURL = nil
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

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        let retryableCodes = [-1001, -1002, -1004, -1005]

        print("❌ Provisional load failed: domain=\(nsError.domain) code=\(nsError.code) url=\(webView.url?.absoluteString ?? "nil")")

        // Retry once for transient network errors
        if retryableCodes.contains(nsError.code), reloadAttempt == 0, let url = webView.url {
            reloadAttempt = 1
            pendingReloadURL = url
            print("🔄 Attempting retry for url: \(url.absoluteString)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.webView.reload()
            }
        } else {
            reloadAttempt = 0
            pendingReloadURL = nil
            eventContinuation.yield(.failed(url: webView.url, error: error))
        }
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

// MARK: - Audio state message handler

extension WebKitWebContent: WKScriptMessageHandler {
    public func userContentController(_ userContentController: WKUserContentController,
                                      didReceive message: WKScriptMessage) {
        switch message.name {
        case "mereAudio":
            if let playing = message.body as? Bool {
                Task { @MainActor in self.hasAudioPlaying = playing }
            }
        case "mereTheme":
            if let css = message.body as? String {
                eventContinuation.yield(.themeColorChanged(cssColor: css))
            }
        case "mereConsole":
            if let log = message.body as? String {
                print("🖥️ JS Console: \(log)")
            }
        default: break
        }
    }
}

/// Breaks the WKUserContentController → handler retain cycle.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }

    func userContentController(_ userContentController: WKUserContentController,
                                didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
