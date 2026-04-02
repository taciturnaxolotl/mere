import Foundation

/// Applies content blocking rules to a browser context.
/// Each engine implements this differently:
///   - WebKit  → WKContentRuleList (compiled bytecode, runs in WebKit process)
///   - Chromium → CefRequestHandler (Swift callback per request)
@MainActor
public protocol AdBlockEngine: AnyObject {

    /// Whether blocking is currently active.
    var isEnabled: Bool { get set }

    /// Currently loaded lists and their rule counts.
    var loadedLists: [String: Int] { get }

    /// Load and compile a block list. Replaces any existing list with the same name.
    /// Compilation is async because WebKit's rule list compilation can take ~100-500ms
    /// for large lists (EasyList has ~50k rules).
    func load(_ list: BlockList) async throws

    /// Remove a list by name.
    func remove(listNamed name: String) async

    /// Fetch a list from a URL, parse it, and load it.
    func fetchAndLoad(from url: URL, name: String) async throws

    /// Block count across all loaded lists.
    var totalBlockedRequestCount: Int { get }
}

// MARK: - Default implementation

public extension AdBlockEngine {
    func fetchAndLoad(from url: URL, name: String) async throws {
        let (data, _) = try await URLSession.shared.data(from: url)
        let text = String(decoding: data, as: UTF8.self)
        let list = EasyListParser.parse(text, name: name)
        try await load(list)
    }
}

// MARK: - Well-known list URLs

public enum BlockListSource {
    public static let easyList        = URL(string: "https://easylist.to/easylist/easylist.txt")!
    public static let easyPrivacy     = URL(string: "https://easylist.to/easylist/easyprivacy.txt")!
    public static let uBlockFilters   = URL(string: "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters.txt")!
    public static let peterlowePII    = URL(string: "https://raw.githubusercontent.com/peterkliewe/easyprivacy/master/easyprivacy.txt")!
}
