import Foundation

public enum NavigationEvent: Sendable {
    case started(url: URL)
    case redirected(from: URL, to: URL)
    case committed(url: URL)
    case finished(url: URL)
    case failed(url: URL?, error: Error)
    case titleChanged(title: String)
    case faviconChanged(url: URL?)
    /// Native theme-color from `<meta name="theme-color">` — carries the raw CSS string.
    case themeColorChanged(cssColor: String)
}

public struct NavigationPolicy: Sendable {
    public enum Action: Sendable {
        case allow
        case cancel
        case redirectTo(URL)
    }

    public let action: Action

    public static let allow = NavigationPolicy(action: .allow)
    public static let cancel = NavigationPolicy(action: .cancel)
}

public struct FindResult: Sendable {
    public let matchCount: Int
    public let activeMatchIndex: Int

    public init(matchCount: Int, activeMatchIndex: Int) {
        self.matchCount = matchCount
        self.activeMatchIndex = activeMatchIndex
    }
}
