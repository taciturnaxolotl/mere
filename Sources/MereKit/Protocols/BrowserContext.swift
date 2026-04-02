import Foundation

/// Represents a browsing profile: cookies, history, bookmarks, credentials.
/// Mirrors ArcBrowserContext / ADK2.BrowserContextController.
@MainActor
public protocol BrowserContext: AnyObject {

    var engine: EngineType { get }

    // MARK: - WebContent factory

    func makeWebContent() -> any WebContent

    // MARK: - Cookies

    /// Fetch all cookies for a given URL.
    func cookies(for url: URL) async -> [HTTPCookie]

    /// Set cookies into this context's store.
    func setCookies(_ cookies: [HTTPCookie], for url: URL) async

    /// Remove all cookies matching a URL.
    func clearCookies(for url: URL) async

    // MARK: - History (read-only; writes happen automatically on navigation)

    func history(limit: Int) async -> [HistoryItem]
    func clearHistory() async

    // MARK: - Downloads

    var activeDownloads: [DownloadItem] { get }

    // MARK: - Lifecycle

    func close()
}

// MARK: - Supporting types

public struct HistoryItem: Identifiable, Sendable {
    public let id: UUID
    public let url: URL
    public let title: String?
    public let visitedAt: Date

    public init(id: UUID = .init(), url: URL, title: String? = nil, visitedAt: Date = .now) {
        self.id = id
        self.url = url
        self.title = title
        self.visitedAt = visitedAt
    }
}

public struct DownloadItem: Identifiable, Sendable {
    public enum State: Sendable { case inProgress(Double), completed(URL), failed(Error) }
    public let id: UUID
    public let sourceURL: URL
    public let filename: String
    public let state: State

    public init(id: UUID = .init(), sourceURL: URL, filename: String, state: State) {
        self.id = id
        self.sourceURL = sourceURL
        self.filename = filename
        self.state = state
    }
}
