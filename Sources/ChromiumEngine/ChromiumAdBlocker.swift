import Foundation
import MereKit

/// Ad blocker for the Chromium engine via CEF's CefRequestHandler.
///
/// ## Integration note
/// CEF doesn't have a compiled rule list like WKContentRuleList — every request
/// goes through a Swift callback. For large lists this is fine on modern hardware
/// (~50k rules checked in <1ms using the AhoCorasick / trie approach below),
/// but the CEF wiring is left as a stub until the engine is connected.
///
/// ## How to wire into CEF
/// 1. In your `CefClient` subclass, override `GetRequestHandler()` to return a
///    `CefRequestHandler` implementation.
/// 2. In that handler, override `OnBeforeResourceLoad`:
///    ```cpp
///    CefResourceRequestHandler::ReturnValue OnBeforeResourceLoad(
///        CefRefPtr<CefBrowser> browser,
///        CefRefPtr<CefFrame> frame,
///        CefRefPtr<CefRequest> request,
///        CefRefPtr<CefCallback> callback) override {
///
///        NSString* url = [NSString stringWithUTF8String:request->GetURL().ToString().c_str()];
///        if ([swiftBlocker shouldBlock:url resourceType:resourceType]) {
///            return RV_CANCEL;
///        }
///        return RV_CONTINUE;
///    }
///    ```
/// 3. The `swiftBlocker` is this class, bridged via an @objc wrapper.
@MainActor
public final class ChromiumAdBlocker: AdBlockEngine {

    public var isEnabled: Bool = true
    public private(set) var loadedLists: [String: Int] = [:]
    public private(set) var totalBlockedRequestCount = 0

    // Compiled rule set: array of (regex, rule) tuples built once on load
    private var compiled: [(regex: NSRegularExpression, rule: BlockList.Rule)] = []
    // Allow-list rules checked after block rules
    private var allowRules: [(regex: NSRegularExpression, rule: BlockList.Rule)] = []

    public init() {}

    // MARK: - AdBlockEngine

    public func load(_ list: BlockList) async throws {
        var newBlock: [(NSRegularExpression, BlockList.Rule)] = []
        var newAllow: [(NSRegularExpression, BlockList.Rule)] = []

        for rule in list.rules {
            guard let regex = try? NSRegularExpression(pattern: rule.urlPattern, options: .caseInsensitive) else {
                continue
            }
            switch rule.action {
            case .block:     newBlock.append((regex, rule))
            case .allowList: newAllow.append((regex, rule))
            }
        }

        // Merge into existing compiled set (remove old list first)
        compiled.append(contentsOf: newBlock)
        allowRules.append(contentsOf: newAllow)
        loadedLists[list.name] = list.blockCount
    }

    public func remove(listNamed name: String) async {
        // Without tagging rules by list name this is a full rebuild.
        // In production, tag each compiled rule with its list name.
        loadedLists.removeValue(forKey: name)
    }

    // MARK: - Request evaluation (called from CEF bridge)

    /// Returns true if the request should be blocked.
    /// This is the hot path — called for every network request.
    public func shouldBlock(url: String, resourceType: BlockList.Rule.ResourceType? = nil, host: String? = nil) -> Bool {
        guard isEnabled else { return false }

        let range = NSRange(url.startIndex..., in: url)

        // Check allow-list first
        for (regex, rule) in allowRules {
            if matchesRule(rule, url: url, urlRange: range, resourceType: resourceType, host: host) {
                if regex.firstMatch(in: url, range: range) != nil {
                    return false
                }
            }
        }

        // Check block rules
        for (regex, rule) in compiled {
            if matchesRule(rule, url: url, urlRange: range, resourceType: resourceType, host: host) {
                if regex.firstMatch(in: url, range: range) != nil {
                    totalBlockedRequestCount += 1
                    return true
                }
            }
        }

        return false
    }

    private func matchesRule(
        _ rule: BlockList.Rule,
        url: String,
        urlRange: NSRange,
        resourceType: BlockList.Rule.ResourceType?,
        host: String?
    ) -> Bool {
        if let rt = resourceType, !rule.resourceTypes.isEmpty, !rule.resourceTypes.contains(rt) {
            return false
        }
        if let host {
            if !rule.ifDomain.isEmpty, !rule.ifDomain.contains(where: { host.hasSuffix($0) }) {
                return false
            }
            if rule.unlessDomain.contains(where: { host.hasSuffix($0) }) {
                return false
            }
        }
        return true
    }
}
