import SwiftUI

// MARK: - État d'Oli
// One observable model for the whole app. Watchers fill it, views read it, the notch controller
// reacts to `openRequest` to unfold on the right section.

enum Section: String, CaseIterable, Identifiable {
    case home, claude, terminal, projects, sites, agenda, instagram, chat

    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return "Aujourd’hui"
        case .claude: return "Claude Code"
        case .terminal: return "Terminal"
        case .projects: return "Projets"
        case .sites: return "Sites"
        case .agenda: return "Agenda"
        case .instagram: return "Instagram"
        case .chat: return "Demander à Oli"
        }
    }
    var icon: String {
        switch self {
        case .home: return "sun.max.fill"
        case .claude: return "sparkles"
        case .terminal: return "chevron.left.forwardslash.chevron.right"
        case .projects: return "square.stack.3d.up.fill"
        case .sites: return "globe.europe.africa.fill"
        case .agenda: return "calendar"
        case .instagram: return "camera.fill"
        case .chat: return "bubble.left.and.text.bubble.right.fill"
        }
    }
    var tint: Color {
        switch self {
        case .home: return Palette.beurre
        case .claude: return Palette.lilas
        case .terminal: return Palette.cream
        case .projects: return Palette.tomate
        case .sites: return Palette.menthe
        case .agenda: return Palette.ciel
        case .instagram: return Palette.rose
        case .chat: return Palette.beurre
        }
    }
}

/// How Oli feels — drives the mascot.
enum Mood: Equatable {
    case calm, busy, waiting, happy, alarm
}

// MARK: Claude Code sessions

struct ClaudeSession: Identifiable, Equatable {
    enum Phase: Equatable { case working, waiting, done, idle }
    let id: String
    var project: String
    var cwd: String
    var terminal: String
    var phase: Phase
    var activity: String          // « Edit · page.tsx », « Réfléchit… », « Terminé »
    var updatedAt: Date
}

struct Approval: Identifiable, Equatable {
    let id: String                // request id (one HTTP request waiting)
    let sessionId: String
    let project: String
    let tool: String
    let summary: String           // command or file, one line
    let detail: String            // longer text (diff, full command)
    let createdAt: Date
}

struct ChatLine: Identifiable, Equatable {
    enum Who { case me, oli }
    let id = UUID()
    let who: Who
    var text: String
}

@MainActor
final class OliModel: ObservableObject {
    static let shared = OliModel()

    // Notch
    @Published var expanded = false
    @Published var section: Section = .home
    /// Sticky while typing in the terminal or the chat, so the notch does not fold under you.
    @Published var holdOpen = false
    /// Short message shown in the folded notch (« Garage Martin est en panne »), with its colour.
    @Published var flash: (text: String, tint: Color)? = nil
    /// Set by watchers: the controller unfolds on this section, then clears it.
    @Published var openRequest: Section? = nil

    // Oli
    @Published var alarm = false            // a client site is down: Oli turns red
    @Published var panic = false            // first seconds of an outage
    @Published var cheer = false            // short happy moment (session finished, site back)
    @Published var soundOn: Bool = UserDefaults.standard.object(forKey: "soundOn") as? Bool ?? true {
        didSet { UserDefaults.standard.set(soundOn, forKey: "soundOn") }
    }

    // Claude Code
    @Published var sessions: [ClaudeSession] = []
    @Published var approvals: [Approval] = []
    @Published var hooksInstalled = false

    // Espace client
    @Published var projects: [EspaceProject] = []
    @Published var projectsSynced: Date? = nil
    @Published var projectsError: String? = nil

    // Sites
    @Published var sites: [SiteCheck] = []
    @Published var sitesSynced: Date? = nil
    @Published var siteAudits: [String: SiteAudit] = OliModel.loadAudits() {
        didSet { if let d = try? JSONEncoder().encode(siteAudits) { UserDefaults.standard.set(d, forKey: "siteAudits") } }
    }
    @Published var sitesManual: String = UserDefaults.standard.string(forKey: "sitesManual") ?? "" {
        didSet { UserDefaults.standard.set(sitesManual, forKey: "sitesManual") }
    }

    // Agenda
    @Published var agenda: [AgendaEvent] = []
    @Published var agendaSynced: Date? = nil
    @Published var agendaError: String? = nil

    // Instagram
    @Published var instagram: SocialSnapshot? = nil

    // Chat
    @Published var chat: [ChatLine] = []
    @Published var chatBusy = false

    // Briefing shown on the home section (morning / Friday), until dismissed
    @Published var briefing: (kind: Briefing.Kind, text: String)? = nil

    /// Bumped when a secret changes, so views recompute what is connected.
    @Published var secretsVersion = 0

    private init() {
        NotificationCenter.default.addObserver(forName: .oliSecretsChanged, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { OliModel.shared.secretsVersion += 1 }
        }
    }

    private static func loadAudits() -> [String: SiteAudit] {
        guard let d = UserDefaults.standard.data(forKey: "siteAudits"),
              let a = try? JSONDecoder().decode([String: SiteAudit].self, from: d) else { return [:] }
        return a
    }

    // MARK: Derived

    var mood: Mood {
        if alarm { return .alarm }
        if !approvals.isEmpty { return .waiting }
        if cheer { return .happy }
        if sessions.contains(where: { $0.phase == .working }) { return .busy }
        return .calm
    }

    var siteTargets: [SiteTarget] {
        SiteMonitor.targets(espace: projects.map { ($0.name, $0.liveUrl) }, manual: sitesManual)
    }

    /// Only what is connected shows up in the rail.
    var sections: [Section] {
        _ = secretsVersion
        let s = Secrets.shared
        return Section.allCases.filter { sec in
            switch sec {
            case .home, .terminal: return true
            case .claude:    return hooksInstalled || !sessions.isEmpty
            case .projects:  return s.has(.espaceToken)
            case .sites:     return !siteTargets.isEmpty
            case .agenda:    return s.has(.agendaURL)
            case .instagram: return s.has(.instagramToken)
            case .chat:      return s.has(.anthropic)
            }
        }
    }

    var nextEvent: AgendaEvent? {
        let now = Date()
        return agenda.first { !$0.isAllDay && $0.end > now } ?? agenda.first { $0.end > now }
    }

    var espaceBase: String { EspaceAPI.base(Secrets.shared[.espaceURL]) }

    // MARK: Actions

    /// Unfold the notch on a section (alerts, shortcuts, briefing).
    func open(_ section: Section) { openRequest = section }

    /// A one-line message in the folded notch for a few seconds.
    func say(_ text: String, tint: Color = Palette.cream, seconds: Double = 8) {
        flash = (text, tint)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            if self?.flash?.text == text { self?.flash = nil }
        }
    }

    func celebrate() {
        cheer = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in self?.cheer = false }
    }
}
