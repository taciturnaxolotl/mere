import SwiftUI
import AppKit
import MereCore
import MereKit

public struct BrowserWindowView: View {

    @StateObject var window: WindowViewModel

    public init(window: WindowViewModel) {
        _window = StateObject(wrappedValue: window)
    }

    private var isNewTab: Bool {
        window.activeTab == nil || (window.activeTab?.url == nil && window.activeTab?.isLoading == false)
    }

    /// Returns the color scheme that gives readable contrast against `color`.
    private func scheme(for color: NSColor) -> ColorScheme {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return .light }
        let r = rgb.redComponent, g = rgb.greenComponent, b = rgb.blueComponent
        let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return luma > 0.5 ? .light : .dark
    }

    private var tintColor: Color {
        if isNewTab {
            return window.newTabBackgroundColor.map { Color(nsColor: $0) }
                ?? Color(nsColor: .windowBackgroundColor)
        }
        if let tc = window.activeTab?.themeColor { return Color(nsColor: tc) }
        return Color(nsColor: .windowBackgroundColor)
    }

    private var preferredScheme: ColorScheme? {
        if let tc = window.activeTab?.themeColor { return scheme(for: tc) }
        if isNewTab, let bg = window.newTabBackgroundColor { return scheme(for: bg) }
        return nil
    }

    private var isLocalhost: Bool {
        guard let url = window.activeTab?.url else { return false }
        let host = url.host?.lowercased() ?? ""
        return host == "localhost" ||
               host == "127.0.0.1" ||
               host == "::1" ||
               host.hasPrefix("127.") ||
               host == "[::1]"
    }

    public var body: some View {
        ZStack {
            // Full-window color gradient using the raw page background colour.
            LinearGradient(
                stops: [
                    .init(color: tintColor.opacity(0.95), location: 0),
                    .init(color: tintColor.opacity(0.70), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.35), value: isNewTab)

            HStack(spacing: 0) {
                if window.sidebarVisible {
                    SidebarView(window: window)
                        .frame(width: 220)
                        .background(.ultraThinMaterial)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                VStack(spacing: 0) {
                    // Toolbar: transparent background — window gradient shows through.
                    BrowserToolbarView(
                        window: window,
                        sidebarVisible: $window.sidebarVisible,
                        focusTrigger: window.addressFocusTrigger
                    )
                    .padding(.top, 8)
                    .padding(.leading, window.sidebarVisible ? 10 : 86)
                    .padding(.trailing, 10)
                    .padding(.bottom, 8)

                    // Content: material matching sidebar, fills all remaining space.
                    contentArea
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(UnevenRoundedRectangle(
                            topLeadingRadius: 0,
                            bottomLeadingRadius: 10,
                            bottomTrailingRadius: 10,
                            topTrailingRadius: 0
                        ))
                        .overlay(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 0,
                                bottomLeadingRadius: 10,
                                bottomTrailingRadius: 10,
                                topTrailingRadius: 0
                            )
                            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.5)
                        )
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                }
                .padding(4)
                .overlay(
                    Group {
                        if isLocalhost {
                            UnevenRoundedRectangle(
                                topLeadingRadius: 0,
                                bottomLeadingRadius: 14,
                                bottomTrailingRadius: 14,
                                topTrailingRadius: 0
                            )
                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                            .foregroundStyle(.yellow)
                        }
                    }
                )
                .ignoresSafeArea(edges: .top)
            }
        }
        .animation(.spring(duration: 0.22), value: window.sidebarVisible)
        .background(TrafficLightNudge(xOffset: 8, yOffset: 8))
        .preferredColorScheme(preferredScheme)
        .onChange(of: window.activeTab?.id) { _, _ in
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }

    @ViewBuilder
    private var contentArea: some View {
        if let tab = window.activeTab, tab.url != nil || tab.isLoading {
            ZStack {
                WebContentView(content: tab.content)
                    .id(tab.id)

                if let error = tab.navigationError {
                    NavigationErrorView(error: error)
                        .padding()
                }
            }
        } else {
            NewTabView(hasBackground: window.newTabBackgroundColor != nil)
        }
    }
}

// MARK: - New Tab Page

struct NewTabView: View {
    let hasBackground: Bool

    var body: some View {
        Text("mere")
            .font(.system(size: 52, weight: .ultraLight, design: .rounded))
            .foregroundStyle(.primary)
            .tracking(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Navigation Error

struct NavigationErrorView: View {
    let error: Error

    private var errorMessage: String {
        let nsError = error as NSError
        switch (nsError.domain, nsError.code) {
        case ("NSURLErrorDomain", -1004):
            return "Can't connect to server"
        case ("NSURLErrorDomain", -1001):
            return "Connection timed out"
        case ("NSURLErrorDomain", -1003):
            return "Server not found"
        default:
            return nsError.localizedDescription
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Unable to load page")
                .font(.system(size: 20, weight: .semibold))

            Text(errorMessage)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 300)
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 20)
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @ObservedObject var window: WindowViewModel

    var body: some View {
        GlassEffectContainer {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 1) {
                    ForEach(window.tabs) { tab in
                        SidebarTabRow(
                            tab: tab as MereCore.Tab,
                            isActive: window.activeTab?.id == tab.id,
                            onActivate: { window.activateTab(tab) },
                            onClose: { window.closeTab(tab) }
                        )
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 6)
                .padding(.horizontal, 8)
            }
        }
    }
}

struct SidebarTabRow: View {
    @ObservedObject var tab: MereCore.Tab
    let isActive: Bool
    let onActivate: () -> Void
    let onClose: () -> Void
    @State private var isHovered = false

    var body: some View {
        rowContent
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .labelColor).opacity(isActive ? 0.08 : isHovered ? 0.04 : 0))
            )
    }

    private var rowContent: some View {
        HStack(spacing: 9) {
            FaviconView(url: tab.favicon, engine: tab.engine)
                .frame(width: 14, height: 14)

            Text(tab.title ?? tab.url?.host ?? "New Tab")
                .lineLimit(1)
                .font(.system(size: 13))
                .foregroundStyle(isActive ? .primary : .secondary)

            Spacer(minLength: 0)

            if tab.hasAudioPlaying {
                Button {
                    tab.content.isMuted.toggle()
                } label: {
                    Image(systemName: tab.content.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 9, weight: .medium))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(HoverButtonStyle())
                .transition(.opacity.animation(.easeInOut(duration: 0.15)))
            }

            // Always reserve space; only visible on hover or when active.
            Button { onClose() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(HoverButtonStyle())
            .opacity(isHovered || isActive ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture { onActivate() }
        .onHover { isHovered = $0 }
    }
}

// MARK: - Favicon

private final class FaviconCache {
    static let shared = FaviconCache()
    private let cache: NSCache<NSURL, NSImage> = {
        let c = NSCache<NSURL, NSImage>()
        c.countLimit = 200
        return c
    }()

    func image(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    func store(_ image: NSImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
}

struct FaviconView: View {
    let url: URL?
    let engine: EngineType
    @State private var image: NSImage? = nil

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                Circle()
                    .fill(engine == .webkit ? Color.blue.opacity(0.7) : Color.orange.opacity(0.7))
                    .frame(width: 8, height: 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            if let cached = FaviconCache.shared.image(for: url) {
                image = cached
                return
            }
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let loaded = NSImage(data: data) else { return }
            FaviconCache.shared.store(loaded, for: url)
            image = loaded
        }
    }
}

// MARK: - Toolbar

struct HoverButtonStyle: ButtonStyle {
    var disabled: Bool = false
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(disabled ? .tertiary : isHovered ? .primary : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .labelColor)
                        .opacity(configuration.isPressed ? 0.12 : isHovered ? 0.07 : 0))
            )
            .animation(.easeInOut(duration: 0.12), value: isHovered)
            .animation(.easeInOut(duration: 0.08), value: configuration.isPressed)
            .onHover { isHovered = $0 }
    }
}

struct BrowserToolbarView: View {
    @ObservedObject var window: WindowViewModel
    @Binding var sidebarVisible: Bool
    let focusTrigger: Int
    @State private var addressText = ""

    private var securityState: SecurityState {
        guard let url = window.activeTab?.url else { return .none }
        if isLocalhost(url) { return .localhost }
        return url.scheme == "https" ? .secure : .insecure
    }

    var body: some View {
        HStack(spacing: 4) {
            navIcon("sidebar.left") {
                sidebarVisible.toggle()
            }

            navIcon("chevron.left", disabled: window.activeTab?.canGoBack != true) {
                window.activeTab?.goBack()
            }
            navIcon("chevron.right", disabled: window.activeTab?.canGoForward != true) {
                window.activeTab?.goForward()
            }

            HStack(spacing: 6) {
                securityIcon

                HStack(spacing: 6) {
                    AddressBar(text: $addressText, focusTrigger: focusTrigger, onSubmit: navigate)
                        .frame(maxWidth: .infinity, minHeight: 22)

                    if let url = window.activeTab?.url {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(url.absoluteString, forType: .string)
                        } label: {
                            Image(systemName: "link")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .buttonStyle(HoverButtonStyle())
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .onChange(of: window.activeTab?.url) { _, url in
                    addressText = url?.absoluteString ?? ""
                }
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(.regularMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 0.5)
                        )
                )
            }

            navIcon("arrow.clockwise") { window.activeTab?.reload() }

            if let tab = window.activeTab {
                Text(tab.engine == .webkit ? "WK" : "CR")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color(nsColor: .separatorColor).opacity(0.3),
                                in: RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    private func navIcon(_ name: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(HoverButtonStyle(disabled: disabled))
        .disabled(disabled)
    }

    @ViewBuilder
    private var securityIcon: some View {
        Button {
            showSecurityInfo()
        } label: {
            let iconName: String = {
                switch securityState {
                case .secure, .localhost:
                    return "lock.fill"
                case .insecure:
                    return "lock.open.fill"
                case .none:
                    return "lock.fill"
                }
            }()

            Image(systemName: iconName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 20, height: 26)
        }
        .buttonStyle(HoverButtonStyle())
    }

    private func showSecurityInfo() {
        guard let url = window.activeTab?.url else { return }
        let message: String
        switch securityState {
        case .secure:
            message = "Connection is secure (HTTPS)\n\n\(url.absoluteString)"
        case .insecure:
            message = "Connection is not secure (HTTP)\n\n\(url.absoluteString)"
        case .localhost:
            message = "Localhost connection\n\n\(url.absoluteString)"
        case .none:
            message = "No connection"
        }
        let alert = NSAlert()
        alert.messageText = "Security Information"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func navigate() {
        let raw = addressText.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }

        let url: URL

        func isURL(_ input: String) -> Bool {
            // Already has a scheme
            if input.hasPrefix("http://") || input.hasPrefix("https://") {
                return true
            }

            // localhost (with optional port)
            if input.lowercased().hasPrefix("localhost") {
                return true
            }

            // IPv4 address pattern
            let ipv4Pattern = #"^(\d{1,3}\.){3}\d{1,3}(:\d+)?$"#
            if let regex = try? NSRegularExpression(pattern: ipv4Pattern),
               regex.firstMatch(in: input, options: [], range: NSRange(input.startIndex..., in: input)) != nil {
                return true
            }

            // Domain-like (contains dot, no spaces)
            if input.contains(".") && !input.contains(" ") {
                return true
            }

            return false
        }

        if isURL(raw) {
            let urlString = raw.hasPrefix("http") ? raw : "http://\(raw)"
            if let u = URL(string: urlString) {
                url = u
            } else {
                // Fallback to search if URL construction fails
                url = URL(string: "https://s.dunkirk.sh?q=\(raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!
            }
        } else {
            url = URL(string: "https://s.dunkirk.sh?q=\(raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!
        }

        if let tab = window.activeTab {
            tab.loadURL(url)
        } else {
            window.openTab(url: url)
        }
    }
}

// MARK: - Address bar (NSViewRepresentable)
// SwiftUI TextField + @FocusState is unreliable on macOS for makeFirstResponder.
// NSTextField gives us direct control over focus and avoids the focus-ring highlight.

struct AddressBar: NSViewRepresentable {
    @Binding var text: String
    var focusTrigger: Int
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let f = NSTextField()
        f.placeholderString = "Search or enter URL"
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.font = .systemFont(ofSize: 13)
        f.cell?.isScrollable = true
        f.cell?.wraps = false
        f.alignment = .left
        f.delegate = context.coordinator
        return f
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        if !context.coordinator.isEditing, context.coordinator.lastDisplayedURL != text {
            context.coordinator.lastDisplayedURL = text
            if let attr = prettyAttributed(text) {
                nsView.attributedStringValue = attr
            } else {
                nsView.stringValue = text
            }
        }
        if context.coordinator.lastTrigger != focusTrigger {
            context.coordinator.lastTrigger = focusTrigger
            context.coordinator.focusGeneration += 1
            let gen = context.coordinator.focusGeneration
            Task { @MainActor [weak coordinator = context.coordinator] in
                guard coordinator?.focusGeneration == gen else { return }
                nsView.window?.makeFirstResponder(nsView)
                nsView.currentEditor()?.selectAll(nil)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// Returns an attributed string showing `host` in label color and `/path` in secondary label color.
    func prettyAttributed(_ urlString: String) -> NSAttributedString? {
        guard !urlString.isEmpty,
              let url = URL(string: urlString),
              let host = url.host else { return nil }
        let font = NSFont.systemFont(ofSize: 13)
        let para = NSMutableParagraphStyle()
        para.alignment = .left
        let hostAttr: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: para,
        ]
        let pathAttr: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: para,
        ]
        let displayHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let result = NSMutableAttributedString(string: displayHost, attributes: hostAttr)
        let path = url.path
        let query = url.query.map { "?\($0)" } ?? ""
        let suffix = (path == "/" || path.isEmpty ? "" : path) + query
        if !suffix.isEmpty {
            result.append(NSAttributedString(string: suffix, attributes: pathAttr))
        }
        return result
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AddressBar
        var lastTrigger: Int
        var focusGeneration = 0
        var lastDisplayedURL: String = ""
        var isEditing = false

        init(_ parent: AddressBar) {
            self.parent = parent
            self.lastTrigger = parent.focusTrigger
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) {
                focusGeneration += 1  // cancel any pending focus-and-select
                parent.onSubmit()
                Task { @MainActor in control.window?.makeFirstResponder(nil) }
                return true
            }
            return false
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            isEditing = true
            if let tv = (obj.object as? NSTextField)?.currentEditor() as? NSTextView {
                tv.insertionPointColor = .labelColor
            }
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            isEditing = false
            if let field = obj.object as? NSTextField {
                lastDisplayedURL = "" // force re-render of pretty URL
                if let attr = parent.prettyAttributed(parent.text) {
                    field.attributedStringValue = attr
                } else {
                    field.stringValue = parent.text
                }
            }
        }
    }
}

// MARK: - Security

enum SecurityState {
    case none
    case secure
    case insecure
    case localhost
}

private func isLocalhost(_ url: URL) -> Bool {
    guard let host = url.host?.lowercased() else { return false }
    return host == "localhost" ||
           host == "127.0.0.1" ||
           host == "::1" ||
           host.hasPrefix("127.") ||
           host == "[::1]"
}

// MARK: - Traffic light repositioning

/// Zero-size view that moves the window's traffic-light buttons down by `yOffset` points
/// so they vertically align with the toolbar icon row.
private struct TrafficLightNudge: NSViewRepresentable {
    let xOffset: CGFloat
    let yOffset: CGFloat

    func makeNSView(context: Context) -> _View { _View() }

    func updateNSView(_ nsView: _View, context: Context) {
        let x = xOffset, y = yOffset
        // Defer until after AppKit's own layout pass resets button frames.
        Task { @MainActor in nsView.apply(xOffset: x, yOffset: y) }
    }

    final class _View: NSView {
        private var baseOrigins: [NSWindow.ButtonType: NSPoint] = [:]
        private static let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

        required init?(coder: NSCoder) { fatalError() }
        init() { super.init(frame: .zero) }

        func apply(xOffset: CGFloat, yOffset: CGFloat) {
            guard let window else { return }
            // Lazily capture default origins the first time we have a window.
            if baseOrigins.isEmpty {
                for type in Self.types {
                    if let btn = window.standardWindowButton(type) {
                        baseOrigins[type] = btn.frame.origin
                    }
                }
            }
            for type in Self.types {
                guard let btn = window.standardWindowButton(type),
                      let base = baseOrigins[type] else { continue }
                btn.setFrameOrigin(NSPoint(x: base.x + xOffset, y: base.y - yOffset))
            }
        }
    }
}
