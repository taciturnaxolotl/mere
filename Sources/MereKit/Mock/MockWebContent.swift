import Foundation

/// In-process stub used for SwiftUI previews and unit tests.
/// Mirrors ADK2.MockWebContent.
@MainActor
public final class MockWebContent: WebContent {

    public let id = UUID()
    public let engine: EngineType = .webkit

    public var url: URL? = URL(string: "https://example.com")
    public var title: String? = "Example Domain"
    public var isLoading = false
    public var estimatedProgress: Double = 1.0
    public var canGoBack = false
    public var canGoForward = false
    public var hasAudioPlaying = false
    public var isMuted = false
    public var zoomFactor: Double = 1.0

    private let (stream, continuation) = AsyncStream<NavigationEvent>.makeStream()
    public var navigationEvents: AsyncStream<NavigationEvent> { stream }

    public init() {}

    public func loadURL(_ url: URL) { self.url = url }
    public func loadHTML(_ html: String, baseURL: URL?) {}
    public func goBack() {}
    public func goForward() {}
    public func reload() {}
    public func stopLoading() {}
    public func evaluateJavaScript(_ script: String) async throws -> Any? { nil }
    public func findInPage(_ query: String, forward: Bool) async -> FindResult { .init(matchCount: 0, activeMatchIndex: 0) }
    public func clearFind() {}
    public func attachHostView(_ container: PlatformView) {}
    public func detachHostView() {}
    public func snapshot() async -> PlatformImage? { nil }
    public func suspend() {}
    public func resume() {}
    public func close() { continuation.finish() }
}
