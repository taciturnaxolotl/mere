import Foundation
import MereKit
import Combine

/// Drives a single browser window: tab list, active tab, engine routing.
/// Mirrors ADK2.BrowserApplicationController / ADK2.BrowserController.
@MainActor
public final class WindowViewModel: ObservableObject {

    @Published public private(set) var tabs: [Tab] = []
    @Published public var activeTab: Tab?
    @Published public private(set) var newTabBackgroundColor: PlatformColor?

    private let webkitContext: any BrowserContext
    private let chromiumContext: (any BrowserContext)?
    private let cookieSync: CookieSyncController
    public let adBlock: AdBlockController
    private var activeTabObservation: AnyCancellable?

    public init(
        webkitContext: any BrowserContext,
        chromiumContext: (any BrowserContext)? = nil,
        adBlockEngines: [any AdBlockEngine] = []
    ) {
        self.webkitContext = webkitContext
        self.chromiumContext = chromiumContext
        self.cookieSync = CookieSyncController(
            webkit: webkitContext,
            chromium: chromiumContext
        )
        self.adBlock = AdBlockController(engines: adBlockEngines)
    }

    // MARK: - Tab management

    @discardableResult
    public func openTab(url: URL? = nil, engine: EngineType? = nil) -> Tab {
        // Carry the previous tab's theme color into the new tab page background.
        if url == nil, let current = activeTab, current.url != nil {
            newTabBackgroundColor = current.themeColor
        }
        let resolvedEngine = engine ?? url.map(EngineType.preferred) ?? .webkit
        let context = context(for: resolvedEngine)
        let content = context.makeWebContent()
        let tab = Tab(content: content)
        tabs.append(tab)
        activeTab = tab
        subscribeToActiveTab()
        if let url { tab.loadURL(url) }
        return tab
    }

    public func closeTab(_ tab: Tab) {
        tab.content.close()
        tabs.removeAll { $0.id == tab.id }
        if activeTab?.id == tab.id {
            activeTab = tabs.last
            subscribeToActiveTab()
        }
    }

    public func activateTab(_ tab: Tab) {
        activeTab = tab
        subscribeToActiveTab()
    }

    /// Reopen a tab in the other engine, syncing cookies first.
    public func switchEngine(for tab: Tab) async {
        guard let url = tab.url else { return }
        let newEngine: EngineType = tab.engine == .webkit ? .chromium : .webkit
        guard newEngine == .webkit || chromiumContext != nil else { return }

        await cookieSync.sync(from: tab.engine, url: url)

        let idx = tabs.firstIndex(where: { $0.id == tab.id })
        closeTab(tab)

        let newTab = openTab(url: url, engine: newEngine)
        if let idx {
            tabs.move(fromOffsets: IndexSet(integer: tabs.count - 1), toOffset: idx)
        }
        activeTab = newTab
        subscribeToActiveTab()
    }

    // MARK: - Helpers

    private func subscribeToActiveTab() {
        activeTabObservation = activeTab?.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }

    private func context(for engine: EngineType) -> any BrowserContext {
        switch engine {
        case .webkit: return webkitContext
        case .chromium: return chromiumContext ?? webkitContext
        }
    }
}
