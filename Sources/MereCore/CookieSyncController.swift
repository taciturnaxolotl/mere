import Foundation
import MereKit

/// Bridges the cookie stores between the two engines when switching a tab.
///
/// The core problem: WKWebView and CEF maintain completely separate HTTP cookie
/// stores. A user logged into GitHub in a WebKit tab will not be logged in when
/// the same URL is opened in a Chromium tab.
///
/// This controller extracts cookies for a given URL from the source engine's
/// store and injects them into the destination engine's store before navigation.
///
/// Limitations:
/// - HttpOnly cookies set by servers are readable from WKHTTPCookieStore but
///   may not be extractable from CEF's cookie manager depending on CEF version.
/// - Secure cookies are transferred in-process (no network exposure), which is safe.
/// - Session cookies are transferred but may expire immediately if the destination
///   engine's session handling differs.
@MainActor
public final class CookieSyncController {

    private let webkit: any BrowserContext
    private let chromium: (any BrowserContext)?

    public init(webkit: any BrowserContext, chromium: (any BrowserContext)?) {
        self.webkit = webkit
        self.chromium = chromium
    }

    /// Copy cookies for `url` from `sourceEngine` into the other engine's store.
    public func sync(from sourceEngine: EngineType, url: URL) async {
        switch sourceEngine {
        case .webkit:
            guard let chromium else { return }
            let cookies = await webkit.cookies(for: url)
            await chromium.setCookies(cookies, for: url)

        case .chromium:
            guard let chromium else { return }
            let cookies = await chromium.cookies(for: url)
            await webkit.setCookies(cookies, for: url)
        }
    }

    /// Full bidirectional sync for all cookies on a domain.
    /// Call this periodically if keeping both engines logged in simultaneously.
    public func fullSync(url: URL) async {
        guard let chromium else { return }
        let webkitCookies = await webkit.cookies(for: url)
        let chromiumCookies = await chromium.cookies(for: url)

        // Merge: newest cookie wins on conflict
        let merged = merge(webkitCookies, chromiumCookies)
        await webkit.setCookies(merged, for: url)
        await chromium.setCookies(merged, for: url)
    }

    private func merge(_ a: [HTTPCookie], _ b: [HTTPCookie]) -> [HTTPCookie] {
        var result: [String: HTTPCookie] = [:]
        for cookie in a + b {
            let key = "\(cookie.domain)|\(cookie.path)|\(cookie.name)"
            if let existing = result[key] {
                // Keep the one with a later expiry, or b if equal
                if let expA = existing.expiresDate, let expB = cookie.expiresDate, expB > expA {
                    result[key] = cookie
                } else if existing.expiresDate == nil {
                    result[key] = cookie
                }
            } else {
                result[key] = cookie
            }
        }
        return Array(result.values)
    }
}
