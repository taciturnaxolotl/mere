import Foundation
#if canImport(AppKit)
import AppKit
public typealias PlatformView = NSView
public typealias PlatformImage = NSImage
public typealias PlatformColor = NSColor
#elseif canImport(UIKit)
import UIKit
public typealias PlatformView = UIView
public typealias PlatformImage = UIImage
public typealias PlatformColor = UIColor
#endif

extension PlatformColor {
    /// Serialize to an `rgb()` CSS string.
    public var cssString: String? {
        #if canImport(AppKit)
        guard let c = usingColorSpace(.deviceRGB) else { return nil }
        let r = Int(c.redComponent * 255), g = Int(c.greenComponent * 255), b = Int(c.blueComponent * 255)
        #else
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        let r = Int(r * 255), g = Int(g * 255), b = Int(b * 255)
        #endif
        return "rgb(\(r),\(g),\(b))"
    }

    /// Create from a CSS color string — hex (`#rgb`, `#rrggbb`) or `rgb()`/`rgba()`.
    public static func fromCSS(_ value: String) -> PlatformColor? {
        let s = value.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { return fromHex(s) }
        // rgb(r, g, b) or rgba(r, g, b, a)
        guard s.hasPrefix("rgb") else { return nil }
        let digits = s.drop(while: { $0 != "(" }).dropFirst().prefix(while: { $0 != ")" })
        let parts = digits.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 3,
              let ri = Double(parts[0]), let gi = Double(parts[1]), let bi = Double(parts[2]) else { return nil }
        let a = parts.count >= 4 ? (Double(parts[3]) ?? 1.0) : 1.0
        return PlatformColor(red: ri / 255, green: gi / 255, blue: bi / 255, alpha: a)
    }

    public static func fromHex(_ hex: String) -> PlatformColor? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        let len = s.count
        guard len == 3 || len == 6 || len == 8,
              let value = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: CGFloat
        switch len {
        case 3:
            r = CGFloat((value >> 8) & 0xF) / 15
            g = CGFloat((value >> 4) & 0xF) / 15
            b = CGFloat(value & 0xF) / 15
            a = 1
        case 6:
            r = CGFloat((value >> 16) & 0xFF) / 255
            g = CGFloat((value >> 8) & 0xFF) / 255
            b = CGFloat(value & 0xFF) / 255
            a = 1
        default: // 8
            r = CGFloat((value >> 24) & 0xFF) / 255
            g = CGFloat((value >> 16) & 0xFF) / 255
            b = CGFloat((value >> 8) & 0xFF) / 255
            a = CGFloat(value & 0xFF) / 255
        }
        return PlatformColor(red: r, green: g, blue: b, alpha: a)
    }
}

/// The core abstraction over a single browser tab, regardless of engine.
/// Mirrors what Dia calls ArcWebContents / ADK2.WebContentController.
@MainActor
public protocol WebContent: AnyObject {

    // MARK: - Identity

    var id: UUID { get }
    var engine: EngineType { get }

    // MARK: - State

    var url: URL? { get }
    var title: String? { get }
    var isLoading: Bool { get }
    var estimatedProgress: Double { get }
    var canGoBack: Bool { get }
    var canGoForward: Bool { get }
    var hasAudioPlaying: Bool { get }
    var isMuted: Bool { get set }

    // MARK: - Navigation

    func loadURL(_ url: URL)
    func loadHTML(_ html: String, baseURL: URL?)
    func goBack()
    func goForward()
    func reload()
    func stopLoading()

    // MARK: - JavaScript

    @discardableResult
    func evaluateJavaScript(_ script: String) async throws -> Any?

    // MARK: - Find in Page

    func findInPage(_ query: String, forward: Bool) async -> FindResult
    func clearFind()

    // MARK: - View

    /// Attach the engine's native view into the given container.
    /// Call this once after creation; the view fills the container.
    func attachHostView(_ container: PlatformView)
    func detachHostView()

    // MARK: - Zoom

    var zoomFactor: Double { get set }

    // MARK: - Snapshot

    func snapshot() async -> PlatformImage?

    // MARK: - Events

    /// Stream of navigation lifecycle events.
    var navigationEvents: AsyncStream<NavigationEvent> { get }

    // MARK: - Lifecycle

    /// Signal that the tab moved to the background. Implementations should
    /// fire the Page Visibility API and pause media so the page reduces activity.
    func suspend()

    /// Signal that the tab became active again.
    func resume()

    func close()
}
