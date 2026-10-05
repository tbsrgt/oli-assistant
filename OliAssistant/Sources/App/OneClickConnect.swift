import AppKit
import SwiftUI

// MARK: - Connexion en un clic
// Un seul bouton « Se connecter » par service :
// 1. une session déjà ouverte sur ce Mac (GitHub CLI, Vercel CLI) est reprise tout de suite ;
// 2. sinon la page du service s'ouvre dans le navigateur, sur ton compte, prête à créer l'accès.
//    Dès que tu cliques « Copier » sur la page, Oli reconnaît le jeton dans le presse-papiers,
//    le vérifie auprès du service, le range dans le Trousseau et efface le presse-papiers.
//    Rien à coller. Oli ne regarde le presse-papiers que pendant cette attente (5 min max) et
//    ne garde que ce qui a exactement la forme d'un jeton du service attendu.
// L'espace client garde son aller-retour oli://connect (EspaceConnect). Email, agenda, sites et
// téléphone ont besoin d'un mot de passe ou d'une liste : leur fiche s'ouvre dans Réglages.

@MainActor
final class OneClickConnect: ObservableObject {
    static let shared = OneClickConnect()
    private init() {}

    /// Service whose token Oli is waiting for, if any.
    @Published private(set) var waiting: ConnectionKind? = nil
    /// Sheet to open in Réglages → Connexions (services that need a form).
    @Published var pendingSheet: ConnectionKind? = nil

    private var timer: Timer?
    private var startCount = 0
    private var deadline = Date.distantPast

    // MARK: Start

    static func start(_ kind: ConnectionKind) { shared.start(kind) }

    func start(_ kind: ConnectionKind) {
        switch kind {
        case .espace:
            EspaceConnect.start()
        case .github:
            if let token = Self.githubCLIToken() { finish(kind, token: token, fromMac: true); return }
            openAndWatch(kind)
        case .vercel:
            if let token = Self.vercelCLIToken() { finish(kind, token: token, fromMac: true); return }
            openAndWatch(kind)
        case .instagram, .pagespeed:
            openAndWatch(kind)
        case .email, .agenda, .sites, .phone:
            pendingSheet = kind
            NotificationCenter.default.post(name: .openFullSettings, object: "integrations")
        }
    }

    func cancel() {
        timer?.invalidate(); timer = nil
        waiting = nil
    }

    /// Page where the user lands, signed in, ready to create Oli's access.
    static func loginPage(_ kind: ConnectionKind) -> URL? {
        switch kind {
        case .github:    return URL(string: "https://github.com/settings/tokens/new?description=Oli%20Assistant&scopes=repo,read:org,read:user")
        case .vercel:    return URL(string: "https://vercel.com/account/settings/tokens")
        case .instagram: return URL(string: "https://developers.facebook.com/apps/")
        case .pagespeed: return URL(string: "https://developers.google.com/speed/docs/insights/v5/get-started#APIKey")
        default:         return nil
        }
    }

    /// What to do on the page, one sentence.
    static func hint(_ kind: ConnectionKind) -> String {
        switch kind {
        case .github:    return "Sur GitHub : « Generate token », puis l’icône Copier."
        case .vercel:    return "Sur Vercel : « Create », puis « Copy »."
        case .instagram: return "Sur Meta : ton app → Instagram → « Générer un jeton », puis Copier."
        case .pagespeed: return "Sur Google : « Get a Key », puis Copier."
        default:         return ""
        }
    }

    /// Exact shape of each service's token: anything else on the clipboard is ignored.
    static func looksLikeToken(_ s: String, for kind: ConnectionKind) -> Bool {
        TokenShape.matches(s, service: kind.rawValue)
    }

    // MARK: Browser + clipboard

    private func openAndWatch(_ kind: ConnectionKind) {
        guard let page = Self.loginPage(kind) else { return }
        cancel()
        waiting = kind
        startCount = NSPasteboard.general.changeCount
        deadline = Date().addingTimeInterval(5 * 60)
        NSWorkspace.shared.open(page)
        DesktopOliController.shared.say("J’ai ouvert \(kind.title). \(Self.hint(kind)) Je m’occupe du reste.", tone: .neutral)
        let t = Timer(timeInterval: 0.6, repeats: true) { _ in
            Task { @MainActor in OneClickConnect.shared.poll() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func poll() {
        guard let kind = waiting else { cancel(); return }
        if Date() > deadline {
            cancel()
            DesktopOliController.shared.say("Je n’ai rien vu venir pour \(kind.title). Reclique « Se connecter » quand tu veux.", tone: .neutral)
            return
        }
        let pb = NSPasteboard.general
        guard pb.changeCount != startCount else { return }
        startCount = pb.changeCount
        let text = (pb.string(forType: .string) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.looksLikeToken(text, for: kind) else { return }
        timer?.invalidate(); timer = nil
        finish(kind, token: text, fromMac: false, clearClipboardAt: pb.changeCount)
    }

    // MARK: Verify + save

    private func finish(_ kind: ConnectionKind, token: String, fromMac: Bool, clearClipboardAt: Int? = nil) {
        waiting = kind
        Task {
            let problem = await Self.verify(kind, token: token)
            // The token is in the Trousseau now (or refused): it has no business staying on the clipboard.
            if let n = clearClipboardAt, NSPasteboard.general.changeCount == n { NSPasteboard.general.clearContents() }
            waiting = nil
            if let problem {
                SoundEngine.shared.play("error")
                DesktopOliController.shared.say(problem, tone: .alert)
                if fromMac { openAndWatch(kind) }   // the Mac's session had expired: the page takes over
                return
            }
            Self.save(kind, token: token)
            SoundEngine.shared.play("approve")
            DesktopOliController.shared.say("C’est branché : \(kind.title) ✔︎", tone: .ok)
            NotificationCenter.default.post(name: .oliConnectionsChanged, object: nil)
            appendAppLog("oli.log", "\(kind.title) connecté en un clic\(fromMac ? " (session du Mac)" : "")")
        }
    }

    static func verify(_ kind: ConnectionKind, token: String) async -> String? {
        switch kind {
        case .github:
            return await check("https://api.github.com/user", token, refused: "GitHub a refusé ce jeton.")
        case .vercel:
            return await check("https://api.vercel.com/v2/user", token, refused: "Vercel a refusé ce jeton.")
        case .instagram:
            return await SocialFetcher.fetch(token: token, accountId: nil).error
        default:
            return nil
        }
    }

    private static func check(_ url: String, _ bearer: String, refused: String) async -> String? {
        guard let u = URL(string: url) else { return "Adresse invalide." }
        var req = URLRequest(url: u, timeoutInterval: 15)
        req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        guard let (_, resp) = try? await URLSession.shared.data(for: req) else { return "Service injoignable, réessaie dans un instant." }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 || code == 403 { return refused }
        return code == 200 ? nil : "Réponse \(code) du service."
    }

    static func save(_ kind: ConnectionKind, token: String) {
        let k = KeychainStore.shared
        switch kind {
        case .github:
            k.set("github-token", value: token); GithubPoller.shared.triggerPulseNow()
            AppState.shared.activatePill("integration_github")
        case .vercel:
            k.set("vercel-token", value: token)
            AppState.shared.activatePill("integration_vercel")
        case .instagram:
            k.set("instagram-token", value: token); SocialPoller.shared.refreshNow()
            AppState.shared.activatePill("integration_instagram")
        case .pagespeed:
            k.set("pagespeed-api-key", value: token)
        default:
            break
        }
    }

    // MARK: Sessions already open on this Mac

    static func githubCLIToken() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard let gh = [home + "/.local/bin/gh", "/opt/homebrew/bin/gh", "/usr/local/bin/gh"]
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return nil }
        let p = Process(); p.executableURL = URL(fileURLWithPath: gh); p.arguments = ["auth", "token"]
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        guard (try? p.run()) != nil else { return nil }
        let token = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        p.waitUntilExit()
        return token.isEmpty ? nil : token
    }

    static func vercelCLIToken() -> String? {
        let f = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.vercel.cli/auth.json")
        guard let d = try? Data(contentsOf: f),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let token = j["token"] as? String, !token.isEmpty else { return nil }
        return token
    }
}

// MARK: - Bouton réutilisable

/// « Se connecter » d'un service, avec l'état d'attente. Used in Réglages, the home settings and Oli's bubble.
struct OneClickConnectButton: View {
    let kind: ConnectionKind
    var compact: Bool = false
    @ObservedObject private var connect = OneClickConnect.shared

    var body: some View {
        if connect.waiting == kind {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                if !compact {
                    Text("Copie le jeton sur la page").font(.system(size: 11)).foregroundColor(.secondary)
                }
                Button("Annuler") { connect.cancel() }.buttonStyle(.borderless).font(.system(size: 11))
            }
            .help(OneClickConnect.hint(kind))
        } else {
            Button("Se connecter") { OneClickConnect.start(kind) }
                .buttonStyle(.borderedProminent)
                .controlSize(compact ? .small : .regular)
        }
    }
}
