import SwiftUI
import WebKitEngine
import MereCore
import MereUI

@main
struct MereApp: App {

    @StateObject private var window = WindowViewModel(
        webkitContext: WebKitBrowserContext(),
        adBlockEngines: []
    )

    var body: some Scene {
        WindowGroup {
            BrowserWindowView(window: window)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    window.openTab()
                }
                .keyboardShortcut("t", modifiers: .command)
            }
        }
    }
}
