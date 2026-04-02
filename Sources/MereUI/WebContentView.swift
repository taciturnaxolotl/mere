import SwiftUI
import AppKit
import MereKit

/// Hosts the engine's native NSView inside SwiftUI.
/// Works identically for WebKit and Chromium tabs.
public struct WebContentView: NSViewRepresentable {

    let content: any WebContent

    public init(content: any WebContent) {
        self.content = content
    }

    public func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        content.attachHostView(container)
        return container
    }

    public func updateNSView(_ nsView: NSView, context: Context) {}

    public static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        // WebContent.close() is called by the Tab when removed from WindowViewModel
    }
}
