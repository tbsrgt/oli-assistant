import SwiftUI
import AppKit
import ServiceManagement

// MARK: - Réglages

enum SettingsTab: String, CaseIterable, Identifiable {
    case connections, claude, general
    var id: String { rawValue }
    var title: String {
        switch self { case .connections: return "Connexions"; case .claude: return "Claude Code"; case .general: return "Général" }
    }
    var icon: String {
        switch self { case .connections: return "link"; case .claude: return "sparkles"; case .general: return "gearshape" }
    }
}

@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()
    private var window: NSWindow?
    private let state = SettingsState()

    func show(tab: SettingsTab = .connections) {
        state.tab = tab
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.title = "Réglages d’Oli"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView().environmentObject(state).environmentObject(OliModel.shared))
            w.center()
            w.delegate = self
            window = w
        }
        state.reload()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        NotchController.shared.fold()
    }
}

@MainActor
final class SettingsState: ObservableObject {
    @Published var tab: SettingsTab = .connections
    @Published var espaceToken = ""
    @Published var espaceURL = ""
    @Published var agendaURL = ""
    @Published var pagespeed = ""
    @Published var instagramToken = ""
    @Published var instagramAccount = ""
    @Published var anthropic = ""
    @Published var chatModel = ""
    @Published var sites = ""
    @Published var saved = false

    func reload() {
        let s = Secrets.shared
        espaceToken = s[.espaceToken] ?? ""; espaceURL = s[.espaceURL] ?? ""
        agendaURL = s[.agendaURL] ?? ""; pagespeed = s[.pagespeed] ?? ""
        instagramToken = s[.instagramToken] ?? ""; instagramAccount = s[.instagramAccount] ?? ""
        anthropic = s[.anthropic] ?? ""
        chatModel = UserDefaults.standard.string(forKey: "chatModel") ?? ""
        sites = OliModel.shared.sitesManual
        saved = false
    }

    func save() {
        let s = Secrets.shared
        s.set(.espaceToken, espaceToken); s.set(.espaceURL, espaceURL)
        s.set(.agendaURL, agendaURL); s.set(.pagespeed, pagespeed)
        s.set(.instagramToken, instagramToken); s.set(.instagramAccount, instagramAccount)
        s.set(.anthropic, anthropic)
        UserDefaults.standard.set(chatModel.trimmingCharacters(in: .whitespaces), forKey: "chatModel")
        if OliModel.shared.sitesManual != sites {
            OliModel.shared.sitesManual = sites
            SitesWatcher.shared.refresh()
        }
        saved = true
        Chimes.shared.play(.tick)
    }
}

struct SettingsView: View {
    @EnvironmentObject var state: SettingsState

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    OliMascot(mood: .calm, size: 34)
                    Text("Oli").font(Typo.display(20, .heavy)).foregroundStyle(Palette.tomate)
                }
                .padding(.bottom, 12)
                ForEach(SettingsTab.allCases) { t in
                    Button { state.tab = t } label: {
                        Label(t.title, systemImage: t.icon)
                            .font(Typo.text(13, .semibold))
                            .foregroundStyle(state.tab == t ? Palette.cream : Palette.sand)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 9).fill(state.tab == t ? Palette.raised : .clear))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text("Oli Assistant 2.0 · Oculot Studio").font(Typo.text(10.5)).foregroundStyle(Palette.dust)
            }
            .padding(.top, 34).padding(.horizontal, 14).padding(.bottom, 14)
            .frame(width: 180)
            .background(Palette.night)

            ScrollView {
                Group {
                    switch state.tab {
                    case .connections: ConnectionsPane()
                    case .claude: ClaudePane()
                    case .general: GeneralPane()
                    }
                }
                .padding(.horizontal, 22).padding(.top, 34).padding(.bottom, 22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Palette.card)
        }
        .frame(width: 620, height: 560)
        .preferredColorScheme(.dark)
    }
}

private struct Field: View {
    let label: String
    let hint: String
    @Binding var text: String
    var secret = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Typo.text(12, .semibold)).foregroundStyle(Palette.cream)
            Group {
                if secret { SecureField("", text: $text) } else { TextField("", text: $text) }
            }
            .textFieldStyle(.roundedBorder)
            Text(hint).font(Typo.text(11)).foregroundStyle(Palette.dust).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct PaneTitle: View {
    let text: String
    let color: Color
    var body: some View { Text(text).font(Typo.display(15, .bold)).foregroundStyle(color).padding(.top, 6) }
}

private struct ConnectionsPane: View {
    @EnvironmentObject var state: SettingsState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaneTitle(text: "Espace client", color: Palette.tomate)
            Field(label: "Jeton d’équipe", hint: "ESPACE_TEAM_TOKEN de espace.oculot.studio.", text: $state.espaceToken, secret: true)
            Field(label: "Adresse (facultatif)", hint: "Par défaut https://espace.oculot.studio", text: $state.espaceURL)

            PaneTitle(text: "Sites", color: Palette.menthe)
            VStack(alignment: .leading, spacing: 4) {
                Text("Autres sites à surveiller").font(Typo.text(12, .semibold)).foregroundStyle(Palette.cream)
                TextEditor(text: $state.sites).font(Typo.mono(11.5)).frame(height: 64)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.hair))
                Text("Une adresse par ligne. Les sites livrés de l’espace client sont surveillés d’office.")
                    .font(Typo.text(11)).foregroundStyle(Palette.dust)
            }
            Field(label: "Clé PageSpeed Insights", hint: "Gratuite sur Google Cloud ; sans elle Google limite les mesures.", text: $state.pagespeed, secret: true)

            PaneTitle(text: "Agenda", color: Palette.ciel)
            Field(label: "Lien du calendrier", hint: "Sur agenda.oculot.studio : « S’abonner au calendrier » → Copier le lien. Un lien iCal Google marche aussi.", text: $state.agendaURL, secret: true)

            PaneTitle(text: "Instagram", color: Palette.rose)
            Field(label: "Jeton d’accès", hint: "IGAA… (Instagram Login) ou EAA… (Facebook Login). Lecture seule.", text: $state.instagramToken, secret: true)
            Field(label: "Identifiant du compte (facultatif)", hint: "Trouvé tout seul la plupart du temps.", text: $state.instagramAccount)

            PaneTitle(text: "Demander à Oli", color: Palette.beurre)
            Field(label: "Clé API Anthropic", hint: "Pour le chat et ses outils.", text: $state.anthropic, secret: true)
            Field(label: "Modèle (facultatif)", hint: "Par défaut \(ChatEngine.modelId).", text: $state.chatModel)

            HStack {
                ActionButton(title: "Enregistrer", icon: "checkmark", tint: Palette.tomate, filled: true) { state.save() }
                if state.saved { Text("Enregistré dans le Trousseau.").font(Typo.text(11.5)).foregroundStyle(Palette.menthe) }
            }
            .padding(.top, 6)
        }
    }
}

private struct ClaudePane: View {
    @EnvironmentObject var model: OliModel
    @State private var preview: String? = nil
    @State private var installing = true
    @State private var message: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PaneTitle(text: "Claude Code", color: Palette.lilas)
            Text("Oli suit tes sessions Claude Code (Terminal, iTerm, VS Code, son propre terminal) et te laisse accepter ou refuser les autorisations depuis l’encoche. Pour ça, il ajoute un petit relais à tes réglages Claude Code.")
                .font(Typo.text(12)).foregroundStyle(Palette.sand).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Tag(text: model.hooksInstalled ? "installé" : "pas installé", tint: model.hooksInstalled ? Palette.menthe : Palette.beurre)
                Spacer()
                if model.hooksInstalled {
                    ActionButton(title: "Retirer", icon: "minus", tint: Palette.alerte) { installing = false; preview = HookInstaller.preview(install: false) }
                } else {
                    ActionButton(title: "Installer", icon: "plus", tint: Palette.lilas, filled: true) { installing = true; preview = HookInstaller.preview(install: true) }
                }
            }
            if let p = preview {
                Text("Changements dans ~/.claude/settings.json (une copie datée est gardée) :")
                    .font(Typo.text(11.5, .semibold)).foregroundStyle(Palette.cream)
                ScrollView { Text(p).font(Typo.mono(10.5)).foregroundStyle(Palette.sand).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                    .frame(height: 200).padding(8).background(RoundedRectangle(cornerRadius: 8).fill(Palette.night))
                HStack {
                    ActionButton(title: "Confirmer", icon: "checkmark", tint: Palette.lilas, filled: true) {
                        do {
                            let backup = try HookInstaller.apply(install: installing)
                            model.hooksInstalled = HookInstaller.isInstalled()
                            message = "C’est fait. Copie de l’ancien fichier : " + backup
                        } catch { message = "Échec : \(error.localizedDescription)" }
                        preview = nil
                    }
                    ActionButton(title: "Annuler", tint: Palette.sand) { preview = nil }
                }
            }
            if let m = message { Text(m).font(Typo.text(11)).foregroundStyle(Palette.sand).textSelection(.enabled) }
        }
    }
}

private struct GeneralPane: View {
    @EnvironmentObject var model: OliModel
    @State private var atLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaneTitle(text: "Général", color: Palette.beurre)
            Toggle("Sons", isOn: $model.soundOn).toggleStyle(.switch)
            Toggle("Lancer Oli à l’ouverture de session", isOn: $atLogin).toggleStyle(.switch)
                .onChange(of: atLogin) { _, on in
                    do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                    catch { atLogin = SMAppService.mainApp.status == .enabled }
                }
            PaneTitle(text: "Raccourcis", color: Palette.beurre)
            VStack(alignment: .leading, spacing: 6) {
                shortcut("⌥⌘O", "Ouvrir / replier Oli")
                shortcut("⌥⌘T", "Terminal")
                shortcut("⌥⌘J", "Demander à Oli")
                shortcut("Échap", "Replier (hors terminal)")
            }
            ActionButton(title: "Montrer le briefing", icon: "sun.horizon.fill", tint: Palette.beurre) {
                BriefingDesk.show(.morning); NotchController.shared.unfold(on: .home)
            }
        }
        .font(Typo.text(12.5))
        .foregroundStyle(Palette.cream)
    }

    private func shortcut(_ keys: String, _ what: String) -> some View {
        HStack {
            Text(keys).font(Typo.mono(12, .bold)).foregroundStyle(Palette.cream).frame(width: 70, alignment: .leading)
            Text(what).foregroundStyle(Palette.sand)
        }
    }
}
