import Foundation
import WebKit
import MereKit

/// Ad blocker for WebKit using WKContentRuleListStore.
///
/// How it works:
/// - Converts BlockList rules → Apple's content blocker JSON format
/// - Compiles them into a WKContentRuleList (bytecode, runs inside WebKit — no Swift
///   callbacks per request, zero performance overhead)
/// - Applies the compiled list to the shared WKWebViewConfiguration so all
///   WebKitWebContent instances in this context are blocked automatically
@MainActor
public final class WebKitAdBlocker: AdBlockEngine {

    public var isEnabled: Bool = true {
        didSet { Task { await applyToConfiguration() } }
    }

    public private(set) var loadedLists: [String: Int] = [:]
    public private(set) var totalBlockedRequestCount = 0

    private let store: WKContentRuleListStore
    private let configuration: WKWebViewConfiguration
    private var compiledLists: [String: WKContentRuleList] = [:]

    /// `store` is keyed to a directory so compiled bytecode survives app restarts.
    public init(configuration: WKWebViewConfiguration, storageURL: URL? = nil) {
        self.configuration = configuration
        self.store = storageURL.map { WKContentRuleListStore(url: $0) }
            ?? .default()
    }

    // MARK: - AdBlockEngine

    public func load(_ list: BlockList) async throws {
        let json = try appleContentBlockerJSON(from: list)
        let compiled: WKContentRuleList = try await withCheckedThrowingContinuation { continuation in
            store.compileContentRuleList(forIdentifier: list.name, encodedContentRuleList: json) { result, error in
                if let error { continuation.resume(throwing: error) }
                else if let result { continuation.resume(returning: result) }
                else { continuation.resume(throwing: ContentBlockerError.compilationFailed) }
            }
        }
        compiledLists[list.name] = compiled
        loadedLists[list.name] = list.blockCount
        await applyToConfiguration()
    }

    public func remove(listNamed name: String) async {
        compiledLists.removeValue(forKey: name)
        loadedLists.removeValue(forKey: name)
        store.removeContentRuleList(forIdentifier: name) { _ in }
        await applyToConfiguration()
    }

    /// Apply the current enabled rule lists to a freshly created content controller.
    /// Called by WebKitBrowserContext when making a new tab.
    public func applyCurrentRules(to controller: WKUserContentController) {
        guard isEnabled else { return }
        for list in compiledLists.values { controller.add(list) }
    }

    // MARK: - Private

    private func applyToConfiguration() async {
        let controller = configuration.userContentController
        controller.removeAllContentRuleLists()
        guard isEnabled else { return }
        for list in compiledLists.values {
            controller.add(list)
        }
    }

    // MARK: - JSON conversion

    /// Converts our engine-agnostic rules to Apple's content blocker JSON format.
    /// Spec: https://webkit.org/blog/3476/content-blockers-first-look/
    private func appleContentBlockerJSON(from list: BlockList) throws -> String {
        var entries: [[String: Any]] = []

        for rule in list.rules {
            var trigger: [String: Any] = ["url-filter": rule.urlPattern]

            if !rule.resourceTypes.isEmpty {
                trigger["resource-type"] = rule.resourceTypes.map { $0.rawValue }
            }
            if !rule.ifDomain.isEmpty {
                trigger["if-domain"] = rule.ifDomain.map { "*\($0)" }
            }
            if !rule.unlessDomain.isEmpty {
                trigger["unless-domain"] = rule.unlessDomain.map { "*\($0)" }
            }

            let action: [String: Any] = switch rule.action {
            case .block:      ["type": "block"]
            case .allowList:  ["type": "ignore-previous-rules"]
            }

            entries.append(["trigger": trigger, "action": action])

            // WKContentRuleList has a hard cap of 150k rules per list
            if entries.count >= 149_000 { break }
        }

        let data = try JSONSerialization.data(withJSONObject: entries)
        return String(decoding: data, as: UTF8.self)
    }
}

enum ContentBlockerError: Error {
    case compilationFailed
}
