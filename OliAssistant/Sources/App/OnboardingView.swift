import SwiftUI
import AppKit

// MARK: - Bienvenue dans Oli (onboarding de l'équipe)
// Au tout premier lancement (personne n'a encore rien branché), une fenêtre présente Oli en 6 étapes :
// qui il est, comment l'ouvrir, brancher l'essentiel en un clic (espace, agenda, mails, GitHub,
// Vercel), connecter Claude, choisir son style, c'est parti. Chaque étape se passe ; tout se refait
// plus tard depuis le menu d'Oli (« Bienvenue dans Oli… ») ou les Réglages.

@MainActor
final class OnboardingController {
    static let shared = OnboardingController()
    private var window: NSWindow?
    static let doneKey = "onboarding.v1.done"

    /// First launch only: someone who already connected something is not a newcomer.
    func showIfNeeded() {
        let ud = UserDefaults.standard
        guard !ud.bool(forKey: Self.doneKey) else { return }
        let alreadySetUp = ConnectionKind.allCases.contains { $0.isConnected } || HookServer.claudeHooksInstalled()
        if alreadySetUp { ud.set(true, forKey: Self.doneKey); return }
        show()
    }

    func show() {
        if let w = window, w.isVisible { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.backgroundColor = NSColor(red: 0.055, green: 0.059, blue: 0.067, alpha: 1)
        w.appearance = NSAppearance(named: .darkAqua)
        w.contentView = NSHostingView(rootView: OnboardingView { [weak self] in self?.finish() })
        w.isReleasedWhenClosed = false
        w.center()
        // Keep it clear of the open island (320 pt at the top of the notch screen).
        if let screen = IslandWindowController.notchScreen() ?? NSScreen.main {
            var f = w.frame
            f.origin.y = min(f.origin.y, screen.frame.maxY - 340 - f.height)
            f.origin.y = max(f.origin.y, screen.visibleFrame.minY + 12)
            w.setFrame(f, display: false)
        }
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func finish() {
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        window?.close()
        // Show the newcomer where Oli lives.
        NotificationCenter.default.post(name: .hookExpand, object: IslandView.overview)
    }
}

struct OnboardingView: View {
    let done: () -> Void

    @State private var step = 0
    @State private var refresh = 0
    @ObservedObject private var layout = HomeLayoutStore.shared
    @AppStorage(DesktopOliController.staysHomeKey) private var staysHome = false
    @State private var showMail = false
    @State private var showAgenda = false

    private let steps = ["Bienvenue", "L’encoche", "Tes services", "Claude", "Ton Oli", "C’est parti"]
    private var firstName: String { resolveUserFirstName() ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            // Progress
            HStack(spacing: 6) {
                ForEach(steps.indices, id: \.self) { i in
                    Capsule().fill(i <= step ? Color(hex: "#FF5B37") : Color.white.opacity(0.12)).frame(height: 4)
                }
            }
            .padding(.horizontal, 40).padding(.top, 34)

            HStack(alignment: .top, spacing: 28) {
                // Oli
                VStack {
                    BotCanvasView(state: AppState.shared)
                        .frame(width: 130, height: 130)
                        .starPower()
                    Text(steps[step].uppercased()).font(.system(size: 10, weight: .bold)).kerning(1)
                        .foregroundColor(Color(hex: "#6B7079"))
                }
                .frame(width: 150)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) { content }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .id(refresh)
            }
            .padding(.horizontal, 40).padding(.top, 28)
            .frame(maxHeight: .infinity, alignment: .top)

            // Navigation
            HStack {
                if step > 0 {
                    Button("Retour") { withAnimation { step -= 1 } }.buttonStyle(.plain)
                        .foregroundColor(Color(hex: "#8E939C")).font(.system(size: 13, weight: .semibold))
                }
                Spacer()
                if step < steps.count - 1 {
                    Button("Passer") { done() }.buttonStyle(.plain)
                        .foregroundColor(Color(hex: "#6B7079")).font(.system(size: 12))
                        .padding(.trailing, 10)
                }
                Button {
                    if step == steps.count - 1 { done() } else { withAnimation { step += 1 } }
                } label: {
                    Text(step == steps.count - 1 ? "Ouvrir Oli" : step == 0 ? "On y va" : "Continuer")
                        .font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                        .padding(.horizontal, 22).padding(.vertical, 9)
                        .background(Capsule().fill(Color(hex: "#FF5B37")))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 40).padding(.bottom, 28)
        }
        .foregroundColor(Color(hex: "#F5F6F8"))
        .frame(width: 760, height: 540)
        .background(Color(hex: "#0E0F11"))
        .onReceive(NotificationCenter.default.publisher(for: .oliConnectionsChanged)) { _ in refresh += 1 }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in if step == 2 || step == 3 { refresh += 1 } }
        .onAppear { StarPower.shared.fire("Bienvenue !", speak: false) }
    }

    // MARK: Steps

    @ViewBuilder private var content: some View {
        switch step {
        case 0:
            title("Salut\(firstName.isEmpty ? "" : " \(firstName)") ! Moi c’est Oli 👋")
            text("Je vis dans l’encoche de ton Mac et je garde un œil sur le studio pour toi :")
            bullet("calendar", "#FFB547", "ton agenda, les appels à prendre et les nouveaux rendez-vous")
            bullet("envelope.fill", "#FF8A52", "tes mails, triés avec Claude (rien n’est jamais supprimé)")
            bullet("globe", "#22C55E", "les sites des clients, les projets de l’espace client")
            bullet("bolt.fill", "#3B9EFF", "des automatisations « Quand… alors… » et le rangement du bureau")
            text("Deux minutes pour tout brancher, et c’est parti.").padding(.top, 4)
        case 1:
            title("Où me trouver")
            bullet("rectangle.topthird.inset.filled", "#FF5B37", "Passe la souris sur l’encoche en haut de l’écran : je m’ouvre.")
            bullet("house.fill", "#C5C8CD", "En haut, les onglets : accueil, mails, agenda, terminal, chat.")
            bullet("plus", "#C5C8CD", "De l’autre côté de l’encoche : déposer un fichier, ⚡ automatisations, ✨ ranger.")
            bullet("gearshape.fill", "#8E939C", "La roue dentée ouvre les Réglages (ou ⌘, quand je suis ouvert).")
            bullet("hand.draw.fill", "#A78BFA", "Tu peux me glisser sur le bureau : je te suis, je me promène, et un clic sur moi ouvre mon panneau.")
        case 2:
            title("Branche tes services")
            text("Un clic chacun. Tout reste dans le Trousseau de ton Mac.")
            serviceRow(.espace)
            agendaRow
            mailRow
            serviceRow(.github)
            serviceRow(.vercel)
        case 3:
            title("Connecte Claude")
            text("Je parle avec ton propre Claude : je te fais un point le matin, je réponds à tes questions et je trie tes mails. Il me faut Claude Code installé sur ce Mac.")
            let ok = ClaudeService.claudeCodePath != nil && HookServer.claudeHooksInstalled()
            HStack(spacing: 10) {
                Image(systemName: ok ? "checkmark.circle.fill" : "sparkles").foregroundColor(Color(hex: ok ? "#4ADE80" : "#E07950"))
                Text(ok ? "Claude est connecté." : (ClaudeService.claudeCodePath == nil ? "Claude Code n’est pas encore installé sur ce Mac." : "Claude Code est là, il reste à me relier à lui."))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if !ok {
                    if ClaudeService.claudeCodePath == nil {
                        pillButton("Installer Claude Code") { NSWorkspace.shared.open(URL(string: "https://claude.com/claude-code")!) }
                    }
                    pillButton("Me relier à Claude") { NotificationCenter.default.post(name: .openFullSettings, object: "agents") }
                }
            }
            .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
            text("Je te montre toujours ce que je change dans la configuration de Claude avant de le faire.")
                .foregroundColor(Color(hex: "#8E939C"))
        case 4:
            title("Ton Oli, à ta façon")
            HStack(spacing: 12) {
                choice("Accueil bento", "square.grid.3x2.fill", layout.style == .bento) { layout.style = .bento }
                choice("Accueil en liste", "list.bullet", layout.style == .list) { layout.style = .list }
            }
            HStack(spacing: 12) {
                choice("Je reste dans l’encoche", "house.fill", staysHome) { DesktopOliController.staysHome = true; staysHome = true }
                choice("Je peux sortir sur le bureau", "figure.walk", !staysHome) { DesktopOliController.staysHome = false; staysHome = false }
            }
            text("Tout se change plus tard dans Réglages → Accueil : les tuiles, leur ordre, leur taille.")
                .foregroundColor(Color(hex: "#8E939C"))
        default:
            title("C’est parti 🎉")
            let n = ConnectionKind.allCases.filter(\.isConnected).count
            text(n == 0 ? "Rien de branché pour l’instant ? Pas grave : tout se fait depuis l’encoche, quand tu veux."
                        : "\(n) service\(n > 1 ? "s" : "") branché\(n > 1 ? "s" : ""). Je m’occupe du reste.")
            bullet("sparkles", "#A78BFA", "Quand un nouveau rendez-vous ou un mail d’Oculot arrive, je deviens arc-en-ciel.")
            bullet("bolt.fill", "#3B9EFF", "Essaie l’onglet ⚡ : « Quand mon bureau a plus de 20 fichiers, alors ranger mon bureau ».")
            bullet("questionmark.circle.fill", "#8E939C", "Cette visite se refait depuis mon menu : « Bienvenue dans Oli… ».")
        }
    }

    // MARK: Service rows

    private func serviceRow(_ k: ConnectionKind) -> some View {
        HStack(spacing: 12) {
            Image(systemName: k.icon).font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                .frame(width: 30, height: 30).background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: k.color)))
            VStack(alignment: .leading, spacing: 1) {
                Text(k.title).font(.system(size: 13, weight: .semibold))
                Text(k.why).font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C")).lineLimit(1)
            }
            Spacer()
            if k.isConnected { connected } else { OneClickConnectButton(kind: k, compact: true) }
        }
        .padding(10).background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
    }

    private var agendaRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "calendar").font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                    .frame(width: 30, height: 30).background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "#FFB547")))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Agenda Oculot").font(.system(size: 13, weight: .semibold))
                    Text("Rendez-vous, appels à prendre, nouveautés").font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C"))
                }
                Spacer()
                if OculotAgenda.shared.isUnlocked { connected }
                else { pillButton(showAgenda ? "Fermer" : "Se connecter") { showAgenda.toggle() } }
            }
            if showAgenda && !OculotAgenda.shared.isUnlocked {
                UnlockAgendaForm(oc: OculotAgenda.shared) {
                    showAgenda = false
                    // The iCal link too, so the agenda tab and the reminders work.
                    if let pw = KeychainStore.shared.get("agenda-password"), let m = KeychainStore.shared.get("agenda-member") {
                        Task {
                            if let link = try? await AgendaLogin.calendarLink(password: pw, member: m) {
                                KeychainStore.shared.set("agenda-ics-url", value: link)
                                AgendaPoller.shared.pollNow()
                            }
                            refresh += 1
                        }
                    }
                }
            }
        }
        .padding(10).background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
    }

    private var mailRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "envelope.fill").font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                    .frame(width: 30, height: 30).background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "#FF8A52")))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Boîte mail").font(.system(size: 13, weight: .semibold))
                    Text(MailAccounts.all.first?.address ?? "Tes mails triés avec Claude").font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C"))
                }
                Spacer()
                if !MailAccounts.all.isEmpty { connected }
                else { pillButton(showMail ? "Fermer" : "Se connecter") { showMail.toggle() } }
            }
            if showMail && MailAccounts.all.isEmpty {
                AddMailboxForm(first: true) { showMail = false; refresh += 1 }
            }
        }
        .padding(10).background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
    }

    // MARK: Bits

    private var connected: some View {
        Label("Branché", systemImage: "checkmark.circle.fill").font(.system(size: 12, weight: .bold)).foregroundColor(Color(hex: "#4ADE80"))
    }

    private func title(_ t: String) -> some View {
        Text(t).font(.system(size: 26, weight: .heavy, design: .rounded)).fixedSize(horizontal: false, vertical: true)
    }

    private func text(_ t: String) -> some View {
        Text(t).font(.system(size: 13.5)).foregroundColor(Color(hex: "#C5C8CD")).fixedSize(horizontal: false, vertical: true)
    }

    private func bullet(_ icon: String, _ color: String, _ t: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundColor(Color(hex: color))
                .frame(width: 30, height: 30).background(Circle().fill(Color(hex: color).opacity(0.14)))
            Text(t).font(.system(size: 13.5)).foregroundColor(Color(hex: "#E4E6EA")).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
    }

    private func pillButton(_ t: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                .padding(.horizontal, 12).padding(.vertical, 6).background(Capsule().fill(Color(hex: "#FF5B37")))
        }
        .buttonStyle(.plain)
    }

    private func choice(_ t: String, _ icon: String, _ on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 22, weight: .semibold))
                Text(t).font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundColor(on ? .white : Color(hex: "#9398A1"))
            .frame(maxWidth: .infinity, minHeight: 86)
            .background(RoundedRectangle(cornerRadius: 14).fill(on ? Color(hex: "#FF5B37").opacity(0.85) : Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(on ? Color(hex: "#FF5B37") : Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}
