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

    private var observationTask: Task<Void, Never>?

    public init(content: any WebContent) {
        self.id = content.id
        self.engine = content.engine
        self.content = content
        startObserving()
    }

    // MARK: - Navigation passthrough

    public func loadURL(_ url: URL) { content.loadURL(url) }
    public func goBack() { content.goBack() }
    public func goForward() { content.goForward() }
    public func reload() { content.reload() }
    public func stopLoading() { content.stopLoading() }

    // MARK: - Private

    private func startObserving() {
        observationTask = Task { [weak self] in
            guard let self else { return }
            for await event in content.navigationEvents {
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    self.apply(event)
                }
            }
        }

        // Poll lightweight state from the WebContent on each event.
        // A real implementation would use Combine or direct KVO bindings.
        Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.syncState()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func apply(_ event: NavigationEvent) {
        switch event {
        case .started(let url):
            self.url = url
            self.isLoading = true
            self.estimatedProgress = 0.1
        case .committed(let url):
            self.url = url
            self.estimatedProgress = 0.7
        case .finished(let url):
            self.url = url
            self.isLoading = false
            self.estimatedProgress = 1.0
            Task { await self.readThemeColor() }
        case .failed:
            self.isLoading = false
            self.estimatedProgress = 0
        case .titleChanged(let title):
            self.title = title
        case .faviconChanged(let url):
            self.favicon = url
        case .redirected(_, let to):
            self.url = to
        }
    }

    private func readThemeColor() async {
        let js = """
        (function() {
            var m = document.querySelector('meta[name="theme-color"]');
            if (m && m.content) return m.content;
            var els = [document.documentElement, document.body];
            for (var el of els) {
                if (!el) continue;
                var bg = window.getComputedStyle(el).backgroundColor;
                if (bg && bg !== 'rgba(0, 0, 0, 0)' && bg !== 'transparent') return bg;
            }
            return null;
        })()
        """
        let result = try? await content.evaluateJavaScript(js)
        guard let css = result as? String, !css.isEmpty else {
            self.themeColor = nil
            return
        }
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
        // Re-check background colour on each poll cycle so JS-driven
        // colour changes (dark mode toggles, SPA navigations) are picked up.
        if !self.isLoading, self.url != nil {
            Task { await self.readThemeColor() }
        }
    }

    deinit {
        observationTask?.cancel()
    }
}
