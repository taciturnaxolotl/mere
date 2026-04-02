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

    /// Sidebar visibility — owned here so keyboard shortcuts in commands can toggle it.
    @Published public var sidebarVisible = true
    /// Incrementing this triggers the address bar to take focus and select-all.
    @Published public var addressFocusTrigger = 0

    private let webkitContext: any BrowserContext
    private let chromiumContext: (any BrowserContext)?
    private let cookieSync: CookieSyncController
    public let adBlock: AdBlockController
    private var activeTabObservation: AnyCancellable?

    private let tabsFileURL: URL

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

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("Mere", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.tabsFileURL = appDir.appendingPathComponent("saved_tabs.json")
    }

    // MARK: - Tab management

    @discardableResult
    public func openTab(url: URL? = nil, engine: EngineType? = nil) -> Tab {
        // Carry the previous tab's theme color into the new tab page background.
        if url == nil, let current = activeTab, current.url != nil {
            newTabBackgroundColor = current.themeColor
        }
        activeTab?.deactivate()
        let resolvedEngine = engine ?? url.map(EngineType.preferred) ?? .webkit
        let context = context(for: resolvedEngine)
        let content = context.makeWebContent()
        let tab = Tab(content: content)
        tabs.append(tab)
        activeTab = tab
        tab.activate()
        subscribeToActiveTab()
        if let url { tab.loadURL(url) }
        return tab
    }

    public func closeTab(_ tab: Tab) {
        guard tabs.count > 1 else {
            tab.resetToNewTab()
            return
        }
        tab.deactivate()
        tab.content.close()
        tabs.removeAll { $0.id == tab.id }
        if activeTab?.id == tab.id {
            activeTab = tabs.last
            activeTab?.activate()
            subscribeToActiveTab()
        }
    }

    public func activateTab(_ tab: Tab) {
        activeTab?.deactivate()
        activeTab = tab
        tab.activate()
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
        newTab.activate()
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
