import SwiftUI
import AppKit

// MARK: - Oli Assistant

@main
struct OliApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            Button("Ouvrir Oli") { NotchController.shared.toggle(.home) }.keyboardShortcut("o", modifiers: [.option, .command])
            Button("Terminal") { NotchController.shared.unfold(on: .terminal) }.keyboardShortcut("t", modifiers: [.option, .command])
            Button("Demander à Oli") { NotchController.shared.unfold(on: .chat) }
            Divider()
            Button("Réglages…") { SettingsWindow.shared.show() }.keyboardShortcut(",")
            Divider()
            Button("Quitter Oli") { NSApp.terminate(nil) }.keyboardShortcut("q")
        } label: {
            Image("MenuBarIcon")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Typo.registerFonts()
        _ = Chimes.shared
        OliModel.shared.hooksInstalled = HookInstaller.isInstalled()
        ClaudeBridge.shared.start()
        NotchController.shared.start()
        Watchers.shared.start()
        HotKeys.shared.register()
        #if DEBUG
        DevTriggers.install()
        #endif
        // Hello: a short happy wave on launch
        OliModel.shared.celebrate()
        OliModel.shared.say("Oli est là", tint: Palette.tomate, seconds: 3)
    }
}
