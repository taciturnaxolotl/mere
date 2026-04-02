import Foundation
import WebKit
import MereKit

/// BrowserContext backed by a WKWebsiteDataStore.
@MainActor
public final class WebKitBrowserContext: BrowserContext {

    public let engine: EngineType = .webkit

    private let dataStore: WKWebsiteDataStore
    private let sharedConfiguration: WKWebViewConfiguration
    private var _activeDownloads: [DownloadItem] = []
    public let adBlocker: WebKitAdBlocker

    public init(persistent: Bool = true) {
        self.dataStore = persistent ? .default() : .nonPersistent()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore
        config.preferences.isElementFullscreenEnabled = true
        self.sharedConfiguration = config
        self.adBlocker = WebKitAdBlocker(configuration: config)
    }

    // MARK: - BrowserContext

    public func makeWebContent() -> any WebContent {
        // Each tab needs its own WKWebViewConfiguration so that script message
        // handler names (mereAudio, mereTheme) don't collide. We share only the
        // websiteDataStore so cookies and storage are common across tabs.
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore
        config.preferences.isElementFullscreenEnabled = true
        adBlocker.applyCurrentRules(to: config.userContentController)
        return WebKitWebContent(configuration: config)
    }

    public func cookies(for url: URL) async -> [HTTPCookie] {
        await dataStore.httpCookieStore.allCookies().filter { cookie in
            url.host?.hasSuffix(cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain) ?? false
        }
    }

    public func setCookies(_ cookies: [HTTPCookie], for url: URL) async {
        for cookie in cookies {
            await dataStore.httpCookieStore.setCookie(cookie)
        }
    }

    public func clearCookies(for url: URL) async {
        let existing = await cookies(for: url)
        for cookie in existing {
            await dataStore.httpCookieStore.deleteCookie(cookie)
        }
    }

    public func history(limit: Int) async -> [HistoryItem] {
        // WKWebView doesn't expose browsing history via public API.
        // Must be tracked manually — see SessionController.
        return []
    }

    public func clearHistory() async {
        await dataStore.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        )
    }

    public var activeDownloads: [DownloadItem] { _activeDownloads }

    public func close() {
        _activeDownloads.removeAll()
    }
}
