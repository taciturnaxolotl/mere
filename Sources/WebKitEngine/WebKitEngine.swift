import Foundation
import MereKit

/// Lightweight WebKit engine — runtime is always available, load() is a no-op.
public final class WebKitEngine: BrowserEngine {

    public static let shared = WebKitEngine()

    public let engineType: EngineType = .webkit
    public private(set) var isLoaded = true

    private init() {}

    public func load() async throws {
        // WebKit is always available — nothing to initialise.
    }

    @MainActor
    public func makeContext() -> any BrowserContext {
        WebKitBrowserContext()
    }

    public func shutdown() {}
}
