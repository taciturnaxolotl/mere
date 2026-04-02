import Foundation

public enum EngineType: String, Codable, Sendable {
    case webkit
    case chromium

    /// Heuristic: prefer Chromium for known compatibility-sensitive origins.
    /// Everything else defaults to WebKit.
    public static func preferred(for url: URL) -> EngineType {
        guard let host = url.host else { return .webkit }
        let chromiumHosts = [
            "figma.com", "notion.so", "linear.app",
            "docs.google.com", "sheets.google.com", "slides.google.com",
            "app.diagrams.net",
        ]
        return chromiumHosts.contains(where: { host.hasSuffix($0) }) ? .chromium : .webkit
    }
}
