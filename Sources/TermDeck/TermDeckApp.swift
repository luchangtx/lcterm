import SwiftUI
import AppKit

@main
struct TermDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1080, minHeight: 660)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建本地终端") {
                    NotificationCenter.default.post(name: .tdNewLocalShell, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command])

                Button("新建主机连接…") {
                    NotificationCenter.default.post(name: .tdNewHost, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

extension Notification.Name {
    static let tdNewLocalShell = Notification.Name("td.newLocalShell")
    static let tdNewHost = Notification.Name("td.newHost")
}
