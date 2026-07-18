import AppKit
import SwiftUI

@main
struct LingyiTranslateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("墨匣", id: "main") {
            ContentView()
                .environment(model)
                .onAppear { appDelegate.appModel = model }
        }
        .defaultSize(width: 980, height: 620)

        Settings {
            SettingsView()
                .environment(model)
        }

        MenuBarExtra {
            MenuBarView()
                .environment(model)
        } label: {
            Image(systemName: model.apiServer.isRunning ? "character.bubble.fill" : "character.bubble")
        }
        .commands {
            CommandMenu("翻译") {
                Button("切换中英翻译方向") {
                    model.toggleDirection()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var appModel: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        appModel?.shutdown()
    }
}
