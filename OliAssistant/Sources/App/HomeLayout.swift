import SwiftUI
import AppKit
import Combine

// MARK: - Accueil personnalisable (bento)
// L'accueil d'Oli est une grille de tuiles façon bento. Dans Réglages → Accueil on choisit les
// tuiles, leur ordre et leur taille (petite = 1 case, large = 2 cases). La même disposition sert
// dans l'encoche (version compacte, 2 rangées) et dans la bulle d'Oli sur le bureau (tout).

enum HomeTileKind: String, Codable, CaseIterable, Identifiable {
    case today, sites, agenda, mail, projects, instagram, github, vercel, claude, automations, connections

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today:       return "Aujourd’hui"
        case .sites:       return "Sites"
        case .agenda:      return "Agenda"
        case .mail:        return "Mails"
        case .projects:    return "Projets"
        case .instagram:   return "Instagram"
        case .github:      return "GitHub"
        case .vercel:      return "Vercel"
        case .claude:      return "Quota Claude"
        case .automations: return "Automatisations"
        case .connections: return "Connexions"
        }
    }

    var why: String {
        switch self {
        case .today:       return "L’heure, la date et ton prochain rendez-vous"
        case .sites:       return "Sites en ligne, pannes, liens cassés"
        case .agenda:      return "Le prochain rendez-vous"
        case .mail:        return "Non lus et mails à traiter"
        case .projects:    return "Projets de l’espace client et échéances"
        case .instagram:   return "Abonnés et rappels de publication"
        case .github:      return "Pull requests et builds"
        case .vercel:      return "Dernier déploiement"
        case .claude:      return "Ce qu’il reste de ton forfait Claude"
        case .automations: return "Tes routines actives, et un bouton pour en lancer une"
        case .connections: return "Services branchés à Oli"
        }
    }

    var icon: String {
        switch self {
        case .today:       return "sun.max.fill"
        case .sites:       return "globe"
        case .agenda:      return "calendar"
        case .mail:        return "envelope.fill"
        case .projects:    return "folder.fill"
        case .instagram:   return "camera.fill"
        case .github:      return "chevron.left.forwardslash.chevron.right"
        case .vercel:      return "triangle.fill"
        case .claude:      return "sparkles"
        case .automations: return "bolt.fill"
        case .connections: return "puzzlepiece.extension.fill"
        }
    }

    var color: String {
        switch self {
        case .today:       return "#FFD65C"
        case .sites:       return "#22C55E"
        case .agenda:      return "#FFB547"
        case .mail:        return "#FF8A52"
        case .projects:    return "#FF5B37"
        case .instagram:   return "#E1306C"
        case .github:      return "#F4505E"
        case .vercel:      return "#7C5CFF"
        case .claude:      return "#E07950"
        case .automations: return "#3B9EFF"
        case .connections: return "#A78BFA"
        }
    }

    /// Pill shown in the island for this tile (focus on tap).
    var pillId: String? {
        switch self {
        case .sites:     return "integration_sites"
        case .agenda:    return "integration_agenda"
        case .projects:  return "integration_espace"
        case .instagram: return "integration_instagram"
        case .github:    return "integration_github"
        case .vercel:    return "integration_vercel"
        default:         return nil
        }
    }

    /// Service to connect before the tile has anything to say.
    var connection: ConnectionKind? {
        switch self {
        case .agenda:    return .agenda
        case .mail:      return .email
        case .projects:  return .espace
        case .instagram: return .instagram
        case .github:    return .github
        case .vercel:    return .vercel
        case .sites:     return nil   // sites from the espace + manual list, never « not connected »
        default:         return nil
        }
    }
}

enum HomeTileSize: String, Codable, CaseIterable {
    case small, wide
    var label: String { self == .small ? "Petite" : "Large" }
    var span: Int { self == .small ? 1 : 2 }
}

struct HomeTile: Codable, Identifiable, Equatable {
    var kind: HomeTileKind
    var size: HomeTileSize
    var visible: Bool
    var id: String { kind.rawValue }
}

enum HomeStyle: String, Codable, CaseIterable {
    case bento, list
    var label: String { self == .bento ? "Bento" : "Liste" }
}

@MainActor
final class HomeLayoutStore: ObservableObject {
    static let shared = HomeLayoutStore()

    private static let tilesKey = "homeLayout.tiles.v1"
    private static let styleKey = "homeLayout.style.v1"

    static let defaultTiles: [HomeTile] = [
        HomeTile(kind: .sites,       size: .small, visible: true),
        HomeTile(kind: .agenda,      size: .wide,  visible: true),
        HomeTile(kind: .mail,        size: .small, visible: true),
        HomeTile(kind: .projects,    size: .wide,  visible: true),
        HomeTile(kind: .claude,      size: .small, visible: true),
        HomeTile(kind: .today,       size: .small, visible: false),
        HomeTile(kind: .instagram,   size: .small, visible: true),
        HomeTile(kind: .github,      size: .small, visible: true),
        HomeTile(kind: .vercel,      size: .small, visible: true),
        HomeTile(kind: .automations, size: .small, visible: true),
        HomeTile(kind: .connections, size: .small, visible: true),
    ]

    @Published var tiles: [HomeTile] { didSet { save() } }
    @Published var style: HomeStyle { didSet { UserDefaults.standard.set(style.rawValue, forKey: Self.styleKey) } }

    private init() {
        let ud = UserDefaults.standard
        var loaded = (ud.data(forKey: Self.tilesKey)).flatMap { try? JSONDecoder().decode([HomeTile].self, from: $0) } ?? Self.defaultTiles
        // Tiles added in a later version: the mail one shows (it matters), the others land hidden.
        for k in HomeTileKind.allCases where !loaded.contains(where: { $0.kind == k }) {
            if k == .mail, let i = loaded.firstIndex(where: { $0.kind == .agenda }) {
                loaded.insert(HomeTile(kind: k, size: .small, visible: true), at: i + 1)
            } else {
                loaded.append(HomeTile(kind: k, size: .small, visible: false))
            }
        }
        tiles = loaded
        style = HomeStyle(rawValue: ud.string(forKey: Self.styleKey) ?? "") ?? .bento
    }

    var visibleTiles: [HomeTile] { tiles.filter(\.visible) }

    func reset() {
        tiles = Self.defaultTiles
        style = .bento
    }

    func move(from: IndexSet, to: Int) { tiles.move(fromOffsets: from, toOffset: to) }

    func move(_ kind: HomeTileKind, by delta: Int) {
        guard let i = tiles.firstIndex(where: { $0.kind == kind }) else { return }
        let j = max(0, min(tiles.count - 1, i + delta))
        guard i != j else { return }
        let t = tiles.remove(at: i)
        tiles.insert(t, at: j)
    }

    private func save() {
        if let d = try? JSONEncoder().encode(tiles) { UserDefaults.standard.set(d, forKey: Self.tilesKey) }
    }
}

// MARK: - What a tile says right now

struct HomeTileData {
    let value: String      // big, short: « 3/3 », « 14:30 », « 42 % »
    let detail: String     // one small line
    let tone: PillTone
}

extension HomeTileKind {
    @MainActor
    func data(_ state: AppState, now: Date = Date()) -> HomeTileData {
        if let c = connection, !c.isConnected {
            return HomeTileData(value: "—", detail: "Se connecter", tone: .neutral)
        }
        switch self {
        case .today:
            let time = now.formatted(.dateTime.hour().minute().locale(Locale(identifier: "fr_FR")))
            let day = now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_FR")))
            let next = state.nextEvent.map { e in (e.isToday ? e.timeLabel : "demain") + " · " + e.title }
            return HomeTileData(value: time, detail: next ?? day, tone: .neutral)
        case .sites:
            let checks = state.siteChecks
            let st = PillStatus.sites(state)
            if checks.isEmpty { return HomeTileData(value: "—", detail: st.text, tone: st.tone) }
            let up = checks.filter { $0.status != .down }.count
            return HomeTileData(value: "\(up)/\(checks.count)", detail: st.text, tone: st.tone)
        case .agenda:
            guard let e = state.nextEvent else { return HomeTileData(value: "Libre", detail: "Rien de prévu sur 14 jours", tone: .neutral) }
            let st = PillStatus.agenda(state, now: now)
            let value = e.start <= now ? "En cours" : e.isToday ? e.timeLabel : e.isTomorrow ? "Demain" : e.dayLabel
            return HomeTileData(value: value, detail: e.title, tone: st.tone)
        case .mail:
            let m = MailCenter.shared
            if let e = m.error, m.mails.isEmpty { return HomeTileData(value: "!", detail: e, tone: .alert) }
            let todo = m.importantCount
            return HomeTileData(value: m.unread.map(String.init) ?? "…", detail: m.lastSync == nil ? "Relève…" : todo == 0 ? "rien à traiter" : "\(todo) à traiter",
                                tone: todo > 0 ? .warn : .ok)
        case .projects:
            let active = state.espaceClients.filter { !$0.isDone }
            let st = PillStatus.espace(state)
            return HomeTileData(value: active.isEmpty ? "0" : "\(active.count)", detail: st.text, tone: st.tone)
        case .instagram:
            let st = PillStatus.instagram(state)
            let value = state.social?.followers.map { $0.formatted(.number.notation(.compactName).locale(Locale(identifier: "fr_FR"))) } ?? "—"
            return HomeTileData(value: value, detail: st.text, tone: st.tone)
        case .github:
            let st = PillStatus.github(state)
            let n = state.githubPulse.map { $0.myPRs.count + $0.toReview.count }
            return HomeTileData(value: n.map { "\($0) PR" } ?? "—", detail: st.text, tone: st.tone)
        case .vercel:
            let st = PillStatus.vercel(state)
            let d = state.vercelDeployments.first
            let value = d.map { $0.state == "READY" ? "OK" : $0.state == "ERROR" ? "Échec" : "…" } ?? "—"
            return HomeTileData(value: value, detail: st.text, tone: st.tone)
        case .claude:
            guard let u = state.claudePlanUsage, let pct = ClaudePlanGauge.dominantPct(u) else {
                return HomeTileData(value: "—", detail: "Quota inconnu", tone: .neutral)
            }
            return HomeTileData(value: "\(Int(pct.rounded())) %", detail: "du forfait utilisé",
                                tone: pct >= 90 ? .alert : pct >= 70 ? .warn : .ok)
        case .automations:
            let on = OliAutomations.enabledRoutines.count
            return HomeTileData(value: "\(on)", detail: on == 1 ? "routine active" : "routines actives", tone: on > 0 ? .ok : .neutral)
        case .connections:
            let all = ConnectionKind.allCases
            let on = all.filter(\.isConnected).count
            return HomeTileData(value: "\(on)/\(all.count)", detail: on == all.count ? "tout est branché" : "services branchés",
                                tone: .neutral)
        }
    }

    /// Tap on a tile: focus its pill in the island, else the most useful page.
    @MainActor
    func open(_ state: AppState) {
        if let c = connection, !c.isConnected {
            OneClickConnect.start(c)
            return
        }
        // Mails and agenda have their own page in the notch.
        if self == .mail || self == .agenda {
            NotificationCenter.default.post(name: .hookExpand, object: self == .mail ? IslandView.inbox : IslandView.agenda)
            return
        }
        if let pill = pillId, state.tasks.contains(where: { $0.id == pill }), state.mode == .expanded {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { state.focusId = pill }
            return
        }
        switch self {
        case .sites:       NotificationCenter.default.post(name: .openFullSettings, object: "integrations")
        case .agenda, .mail: break
        case .projects:    NSWorkspace.shared.open(EspacePoller.adminURL)
        case .instagram:
            let u = state.social?.username ?? ""
            NSWorkspace.shared.open(URL(string: u.isEmpty ? "https://www.instagram.com" : "https://www.instagram.com/\(u)/")!)
        case .github:      NSWorkspace.shared.open(URL(string: "https://github.com/pulls")!)
        case .vercel:      NSWorkspace.shared.open(URL(string: state.vercelDeployments.first.map { "https://\($0.url)" } ?? "https://vercel.com/dashboard")!)
        case .claude:      NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!)
        case .automations: NotificationCenter.default.post(name: .openFullSettings, object: "home")
        case .connections: NotificationCenter.default.post(name: .openFullSettings, object: "integrations")
        case .today:       NSWorkspace.shared.open(AgendaPoller.calendarURL)
        }
    }
}
