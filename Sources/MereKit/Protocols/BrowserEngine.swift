import Foundation

/// Entry point for each engine. One instance per process.
/// Responsible for spinning up the runtime and vending BrowserContexts.
public protocol BrowserEngine: AnyObject {

    var engineType: EngineType { get }

    /// Whether the engine runtime is currently loaded.
    var isLoaded: Bool { get }

    /// Load the engine runtime. No-op if already loaded.
    /// For WebKit this is essentially free; for CEF it initialises the subprocess infrastructure.
    func load() async throws

    /// Create a new isolated browsing context (profile / cookie jar).
    @MainActor
    func makeContext() -> any BrowserContext

    /// Tear down the engine. Call only on app exit.
    func shutdown()
}
