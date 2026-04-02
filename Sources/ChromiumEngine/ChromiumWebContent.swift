import Foundation
import AppKit
import MereKit

/// WebContent backed by CEF (Chromium Embedded Framework).
///
/// ## Integration note
/// This is a stub. To wire it up:
///
/// 1. Add CEF as a dependency (https://bitbucket.org/chromiumembedded/cef).
///    The easiest Swift path is via CEF.swift (https://github.com/lvsti/CEF.swift)
///    or by bridging the CEF ObjC layer yourself using the same pattern
///    Dia uses for ArcCore (Arc* ObjC classes → ADK Swift wrappers).
///
/// 2. Replace `hostView` with a real `CefBrowserView` or an `NSView` returned
///    by `CefBrowserHost::CreateBrowserSync`.
///
/// 3. Forward CEF's `CefLoadHandler`, `CefDisplayHandler`, `CefLifeSpanHandler`
///    callbacks into `eventContinuation.yield(...)`.
///
/// Everything above this class (MereCore, UI) is already engine-agnostic
/// and needs no changes.
@MainActor
public final class ChromiumWebContent: WebContent {

    public let id = UUID()
    public let engine: EngineType = .chromium

    public private(set) var url: URL?
    public private(set) var title: String?
    public private(set) var isLoading = false
    public private(set) var estimatedProgress: Double = 0
    public private(set) var canGoBack = false
    public private(set) var canGoForward = false
    public private(set) var hasAudioPlaying = false
    public var isMuted = false
    public var zoomFactor: Double = 1.0

    private let (stream, continuation) = AsyncStream<NavigationEvent>.makeStream()
    public var navigationEvents: AsyncStream<NavigationEvent> { stream }

    // Placeholder — replace with real CefBrowserView
    private let hostView = NSView()

    public init() {}

    public func loadURL(_ url: URL) {
        self.url = url
        // cefBrowser.mainFrame.loadURL(url.absoluteString)
        assertionFailure("ChromiumWebContent: CEF not wired up yet. See class doc.")
    }

    public func loadHTML(_ html: String, baseURL: URL?) {
        // cefBrowser.mainFrame.loadString(html, url: baseURL?.absoluteString ?? "about:blank")
    }

    public func goBack() { /* cefBrowser.goBack() */ }
    public func goForward() { /* cefBrowser.goForward() */ }
    public func reload() { /* cefBrowser.reload() */ }
    public func stopLoading() { /* cefBrowser.stopLoad() */ }

    public func evaluateJavaScript(_ script: String) async throws -> Any? {
        // CEF JS evaluation is callback-based; bridge to async/await with a CheckedContinuation.
        // cefBrowser.mainFrame.evaluateJavaScript(...)
        return nil
    }

    public func findInPage(_ query: String, forward: Bool) async -> FindResult {
        // cefBrowser.host.find(query, forward: forward, matchCase: false, findNext: true)
        return FindResult(matchCount: 0, activeMatchIndex: 0)
    }

    public func clearFind() {
        // cefBrowser.host.stopFinding(clearSelection: true)
    }

    public func attachHostView(_ container: NSView) {
        hostView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hostView)
        NSLayoutConstraint.activate([
            hostView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hostView.topAnchor.constraint(equalTo: container.topAnchor),
            hostView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    public func detachHostView() { hostView.removeFromSuperview() }

    public func snapshot() async -> NSImage? { nil }

    public func suspend() {}
    public func resume() {}
    public func close() { continuation.finish() }
}
