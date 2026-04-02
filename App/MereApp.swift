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
                .onAppear {
                    if window.tabs.isEmpty {
                        window.openTab()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    window.openTab()
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("Close Tab") {
                    if let tab = window.activeTab { window.closeTab(tab) }
                }
                .keyboardShortcut("w", modifiers: .command)
            }

            CommandGroup(replacing: .sidebar) {
                Button("Toggle Sidebar") {
                    window.sidebarVisible.toggle()
                }
                .keyboardShortcut("s", modifiers: .command)
            }

            CommandGroup(after: .toolbar) {
                Button("Focus Address Bar") {
                    window.addressFocusTrigger += 1
                }
                .keyboardShortcut("l", modifiers: .command)

                Button("Reload Page") {
                    window.activeTab?.reload()
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Copy URL") {
                    if let url = window.activeTab?.url {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    }
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
        }
    }
}
