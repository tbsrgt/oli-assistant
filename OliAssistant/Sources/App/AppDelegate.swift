import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    private(set) var islandController: IslandWindowController?

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyCenter.shared.unregisterAll()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppIconManager.applyStored()
        // Ignore SIGPIPE — prevents crash when oli-hook closes socket before we write response
        signal(SIGPIPE, SIG_IGN)
        // Warm up Keychain cache on main thread BEFORE any poller or view touches it
        _ = KeychainStore.shared
        NSApp.setActivationPolicy(.accessory)
        setupMenuBarItem()
        setupIsland()
    }

    // MARK: - URL scheme oli://

    /// `oli://` (clic sur le widget, ou `open oli://`) : déplie l'encoche.
    /// `oli://reglages` ouvre les réglages. `oli://connect?…` connecte un service en un clic (EspaceConnect).
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: { $0.scheme?.lowercased() == "oli" }) else { return }
        if url.host?.lowercased() == "reglages" { openSettings(); return }
        if url.host?.lowercased() == "connect" { EspaceConnect.handle(url); return }
        islandController?.openFromURL()
    }

    // MARK: - Menu bar

    private func setupMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Oli")
        button.image?.size = NSSize(width: 24, height: 18)
        button.image?.accessibilityDescription = "Oli"
        button.image?.isTemplate = true

        let menu = NSMenu()
        menu.addItem(withTitle: "Open Oli", action: #selector(openIsland), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        statusItem?.menu = menu
    }

    // MARK: - Actions

    @objc private func openIsland() {
        islandController?.expand(to: .overview)
    }

    private var settingsWindow: NSWindow?

    @objc private func openSettingsFromNotification(_ notification: Notification) {
        if let section = notification.object as? String {
            UserDefaults.standard.set(section, forKey: "settingsSection")
        }
        openSettings()
    }

    @objc private func openSettings() {
        // The island floats above every window; fold it away so it can't cover Settings.
        if AppState.shared.mode == .expanded { islandController?.collapse() }

        if let w = settingsWindow, w.isVisible {
            placeBelowIsland(w)
            w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return
        }
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        win.title = "Settings — Oli"
        let host = NSHostingView(rootView: SettingsView())
        host.sizingOptions = [.minSize]
        win.contentView = host
        win.contentMinSize = NSSize(width: 640, height: 420)
        win.isReleasedWhenClosed = false
        placeBelowIsland(win)
        settingsWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Centres the window horizontally and keeps its title bar clear of the island panel
    /// (320 pt tall at the top of the notch screen), shrinking it to fit if needed.
    private func placeBelowIsland(_ win: NSWindow) {
        let screen = IslandWindowController.notchScreen() ?? NSScreen.main ?? win.screen
        guard let screen else { win.center(); return }
        let visible = screen.visibleFrame
        let islandBottom = screen.frame.maxY - 320 - 12   // island panel height + margin
        let top = min(visible.maxY, islandBottom)
        var frame = win.frame
        frame.size.height = min(frame.height, max(top - visible.minY - 12, win.minSize.height))
        frame.origin.x = visible.midX - frame.width / 2
        frame.origin.y = max(visible.minY + 12, top - frame.height)
        win.setFrame(frame, display: true)
    }

    // MARK: - Island setup

    private func setupIsland() {
        islandController = IslandWindowController()
        islandController?.showWindow(nil)
        islandController?.fsm.launch()
        HookServer.shared.start()
        VercelPoller.shared.start()
        EspacePoller.shared.start()
        SocialPoller.shared.start()
        AgendaPoller.shared.start()
        #if DEBUG
        BriefingCenter.shared.installDebugTrigger()
        // Dev only: scripts/chat-demo.sh "question" sends a message to the chat, like typing it.
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("studio.oculot.oli.chatDemo"),
                                                            object: nil, queue: .main) { note in
            let q = note.object as? String ?? "Bonjour"
            Task { @MainActor in
                let st = AppState.shared
                st.chatHistory.append(ChatMessage(role: .user, content: q))
                NotificationCenter.default.post(name: .hookExpand, object: IslandView.prompt)
                await ClaudeService.shared.chat(query: q, context: nil, state: st)
            }
        }
        #endif
        SitesPoller.shared.start()
        if PhoneBridge.enabled { PhoneBridge.shared.start() }
        GithubPoller.shared.start()
        WidgetSnapshotWriter.shared.start()
        StarPower.shared.start()        // mode étoile : nouveau rendez-vous / mail d'Oculot
        OculotAgenda.shared.start()     // agenda Oculot en direct (appels à prendre, nouveautés) si débloqué
        MailCenter.shared.start()       // mails : relevés toutes les 5 min (lecture seule)
        OliAutomations.shared.start()   // routines : point du matin, alertes en bulle, rendez-vous, récap du soir
        #if DEBUG
        // Dev only: `scripts/oli-desktop.sh` drives desktop Oli for screenshots (no mouse/keyboard needed):
        // hub | close | say | follow | wander | still | settings | home
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("studio.oculot.oli.desktop"),
                                                            object: nil, queue: .main) { note in
            let cmd = note.object as? String ?? ""
            Task { @MainActor in
                let d = DesktopOliController.shared
                switch cmd {
                case "hub":
                    if d.isOnDesktop { d.openHub() } else {
                        d.flyOutOrHome()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { DesktopOliController.shared.openHub() }
                    }
                case "close":    OliBubbleCenter.shared.closeAll()
                case "say":      d.say("Démo : un site vient de tomber, je te montre ?", tone: .alert, button: ("Voir", {}))
                case "follow":   DesktopOliMotion.current = .follow
                case "wander":   DesktopOliMotion.current = .wander
                case "still":    DesktopOliMotion.current = .still
                case "google":   Task { _ = await MailAccounts.connectGoogle(); NotificationCenter.default.post(name: .hookExpand, object: IslandView.inbox) }
                case "star":     StarPower.shared.fire("Démo : nouveau mail d’Oculot ✨")
                case "home":     if d.isOnDesktop { d.flyHome() }
                case "settings": NotificationCenter.default.post(name: .openFullSettings, object: "home")
                default: break
                }
            }
        }
        #endif
        NotificationCenter.default.addObserver(self, selector: #selector(openSettingsFromNotification(_:)),
                                               name: .openFullSettings, object: nil)
        // After the greeting ends, fly Oli back to the desktop if it was there at last quit
        NotificationCenter.default.addObserver(forName: .greetComplete, object: nil, queue: .main) { _ in
            DesktopOliController.shared.launchFlyIfNeeded()
        }
        #if !APPSTORE
        _ = MusicController.shared
        #endif
    }
}
