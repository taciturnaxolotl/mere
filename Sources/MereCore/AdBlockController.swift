import Foundation
import MereKit
import Combine

/// Manages ad blocking state across both engine contexts.
/// Lives on WindowViewModel; drives both WebKitAdBlocker and ChromiumAdBlocker.
@MainActor
public final class AdBlockController: ObservableObject {

    @Published public private(set) var isEnabled: Bool = true
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var loadedLists: [String: Int] = [:]
    @Published public private(set) var error: String?

    private let engines: [any AdBlockEngine]

    public init(engines: [any AdBlockEngine]) {
        self.engines = engines
    }

    // MARK: - Control

    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        engines.forEach { $0.isEnabled = enabled }
    }

    // MARK: - List management

    /// Load the default lists (EasyList + EasyPrivacy).
    public func loadDefaults() async {
        await load(from: BlockListSource.easyList,    name: "EasyList")
        await load(from: BlockListSource.easyPrivacy, name: "EasyPrivacy")
    }

    /// Fetch a list from a URL and load it into all engines.
    public func load(from url: URL, name: String) async {
        isLoading = true
        error = nil
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let text = String(decoding: data, as: UTF8.self)
            let list = EasyListParser.parse(text, name: name)
            for engine in engines {
                try await engine.load(list)
            }
            loadedLists[name] = list.blockCount
        } catch {
            self.error = "\(name): \(error.localizedDescription)"
        }
        isLoading = false
    }

    public func remove(listNamed name: String) async {
        for engine in engines { await engine.remove(listNamed: name) }
        loadedLists.removeValue(forKey: name)
    }

    public var totalRuleCount: Int { loadedLists.values.reduce(0, +) }
    public var totalBlockedCount: Int { engines.map(\.totalBlockedRequestCount).reduce(0, +) }
}
