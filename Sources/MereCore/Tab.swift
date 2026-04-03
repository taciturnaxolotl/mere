import Foundation
import MereKit
import Combine
#if canImport(AppKit)
import AppKit
#endif

/// Observable model for a single browser tab.
/// Mirrors ADK2.WebContentViewModel / ADK2.WebContentController.
@MainActor
public final class Tab: ObservableObject, Identifiable {

    public let id: UUID
    public let engine: EngineType
    public let content: any WebContent

    @Published public private(set) var url: URL?
    @Published public private(set) var title: String?
    @Published public private(set) var isLoading = false
    @Published public private(set) var estimatedProgress: Double = 0
    @Published public private(set) var canGoBack = false
    @Published public private(set) var canGoForward = false
    @Published public private(set) var favicon: URL?
    @Published public private(set) var hasAudioPlaying = false
    @Published public private(set) var themeColor: PlatformColor?
    @Published public private(set) var navigationError: Error?

    private var observationTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var themeColorTask: Task<Void, Never>?

    /// Whether this tab is currently visible. Background tabs poll at a much
    /// lower rate and skip theme-colour reads to save CPU and memory.
    public private(set) var isActive = false

    public init(content: any WebContent) {
        self.id = content.id
        self.engine = content.engine
        self.content = content
        startObserving()
    }

    // MARK: - Navigation passthrough

    public func loadURL(_ url: URL) {
        print("🔍 Tab.loadURL: \(url.absoluteString)")
        content.loadURL(url)
    }
    public func goBack() { content.goBack() }
    public func goForward() { content.goForward() }
    public func reload() { content.reload() }
    public func stopLoading() { content.stopLoading() }

    // MARK: - State control

    public func resetToNewTab() {
        url = nil
        title = nil
        isLoading = false
        estimatedProgress = 0
        canGoBack = false
        canGoForward = false
        themeColor = nil
        navigationError = nil
        content.loadHTML("", baseURL: nil)
    }

    // MARK: - Active state

    public func activate() {
        guard !isActive else { return }
        isActive = true
        content.resume()
        // Immediately sync so the UI reflects current state.
        syncState()
        scheduleThemeColorRead()
        startPoll()
    }

    public func deactivate() {
        guard isActive else { return }
        isActive = false
        content.suspend()
        pollTask?.cancel()
        pollTask = nil
        themeColorTask?.cancel()
        themeColorTask = nil
    }

    // MARK: - Private

    private func startObserving() {
        observationTask = Task { [weak self] in
            guard let self else { return }
            for await event in content.navigationEvents {
                guard !Task.isCancelled else { break }
                await MainActor.run { self.apply(event) }
            }
        }
        // Start polling immediately; WindowViewModel will call activate/deactivate.
        startPoll()
    }

    private func startPoll() {
        pollTask?.cancel()
        // Active tabs poll at 250 ms; background tabs poll at 2 s (title/loading only).
        let interval: Duration = isActive ? .milliseconds(250) : .seconds(2)
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.syncState()
                try? await Task.sleep(for: interval)
            }
        }
    }

    private func apply(_ event: NavigationEvent) {
        switch event {
        case .started(let url):
            self.url = url
            self.isLoading = true
            self.estimatedProgress = 0.1
            self.navigationError = nil  // clear any previous error
            self.themeColor = nil  // clear for new navigation; readThemeColor will repopulate
        case .committed(let url):
            self.url = url
            self.estimatedProgress = 0.7
        case .finished(let url):
            self.url = url
            self.isLoading = false
            self.estimatedProgress = 1.0
            self.navigationError = nil
            scheduleThemeColorRead()
        case .failed(_, let error):
            self.isLoading = false
            self.estimatedProgress = 0
            self.navigationError = error
        case .titleChanged(let title):
            self.title = title
        case .faviconChanged(let url):
            self.favicon = url
        case .themeColorChanged(let css):
            self.themeColor = PlatformColor.fromCSS(css)
        case .redirected(_, let to):
            self.url = to
        }
    }

    private func scheduleThemeColorRead() {
        guard isActive, themeColorTask == nil else { return }
        themeColorTask = Task { [weak self] in
            await self?.readThemeColor()
            self?.themeColorTask = nil
        }
    }

    private func readThemeColor() async {
        let js = """
        (function() {
            function elBg(el) {
                var bg = window.getComputedStyle(el).backgroundColor;
                if (bg && bg !== 'rgba(0, 0, 0, 0)' && bg !== 'transparent') return bg;
                var attr = el.getAttribute ? el.getAttribute('bgcolor') : null;
                if (attr) return attr;
                return null;
            }
            var m = document.querySelector('meta[name="theme-color"]');
            if (m && m.content) return m.content;
            var el = document.elementFromPoint(
                window.innerWidth / 2, window.innerHeight / 2);
            while (el && el.nodeType === 1) {
                var bg = elBg(el);
                if (bg) return bg;
                el = el.parentElement;
            }
            return null;
        })()
        """
        let result = try? await content.evaluateJavaScript(js)
        // Only update when we get a valid colour; don't reset to nil on a
        // failed/null read — the colour was already cleared on .started.
        guard let css = result as? String, !css.isEmpty else { return }
        self.themeColor = PlatformColor.fromCSS(css)
    }

    private func syncState() {
        self.url = content.url
        self.title = content.title
        self.isLoading = content.isLoading
        self.estimatedProgress = content.estimatedProgress
        self.canGoBack = content.canGoBack
        self.canGoForward = content.canGoForward
        self.hasAudioPlaying = content.hasAudioPlaying
    }

    deinit {
        observationTask?.cancel()
        pollTask?.cancel()
        themeColorTask?.cancel()
    }
}
