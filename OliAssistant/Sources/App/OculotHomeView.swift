import SwiftUI
import AppKit

// MARK: - Accueil Oculot
// What the main card shows when Oli opens and no Claude Code session is running: one line per
// thing that matters to the studio (sites, projects, Instagram), most urgent first, each line
// jumping to its pill. Replaces the generic « Claude Code · Connected » card, which said nothing.
// Réglages → Accueil switches it to a bento of tiles (HomeBentoView) or back to this list.

struct OculotHomeView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var layout = HomeLayoutStore.shared

    private struct Line: Identifiable {
        let id: String
        let icon: String
        let tint: String       // hex
        let title: String
        let detail: String
        let urgent: Bool
        let pill: String?      // pill to focus on click
        let url: URL?          // fallback when the pill is not active
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        let name = resolveUserFirstName().map { " \($0)" } ?? ""
        return (h < 5 || h >= 18 ? "Bonsoir" : "Bonjour") + name
    }
    private var day: String {
        Date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Locale(identifier: "fr_FR")))
    }

    private var lines: [Line] {
        var out: [Line] = []

        // Sites
        let checks = state.siteChecks
        let down = checks.filter { $0.status == .down }
        let warn = checks.filter { $0.status == .warning || ($0.status == .ok && !(state.siteAudits[$0.url]?.issues.isEmpty ?? true)) }
        if !down.isEmpty {
            out.append(Line(id: "sites", icon: "exclamationmark.triangle.fill", tint: "#F4505E",
                            title: "Panne",
                            detail: down.count == 1 ? "\(down[0].name) · \(down[0].reason ?? "injoignable")" : "\(down.count) sites : " + down.map(\.name).joined(separator: ", "),
                            urgent: true, pill: SitesPoller.pillId, url: nil))
        } else if !checks.isEmpty {
            // The problem itself first: « 17 liens cassés » says more than the host name.
            let first = warn.first.map { c in c.reason ?? state.siteAudits[c.url]?.issues.first ?? "à surveiller" }
            let detail = warn.count > 1 ? "\(checks.count) en ligne · \(warn.count) à surveiller"
                       : first.map { "\(checks.count) en ligne · \($0)" } ?? "\(checks.count) en ligne, tout va bien"
            out.append(Line(id: "sites", icon: "globe", tint: warn.isEmpty ? "#22C55E" : "#FFD65C",
                            title: "Sites", detail: detail,
                            urgent: false, pill: SitesPoller.pillId, url: nil))
        } else if !SitesPoller.targets.isEmpty {
            out.append(Line(id: "sites", icon: "globe", tint: "#8E939C", title: "Sites", detail: "vérification en cours…",
                            urgent: false, pill: SitesPoller.pillId, url: nil))
        }

        // Agenda: next appointment (only once a calendar link is set)
        if KeychainStore.shared.get("agenda-ics-url") != nil {
            if let e = state.nextEvent {
                let soon = e.start.timeIntervalSinceNow < 3600 && e.end > Date()
                let when = e.isToday ? e.timeLabel : e.isTomorrow ? "demain \(e.timeLabel)" : "\(e.dayLabel) \(e.timeLabel)"
                out.append(Line(id: "agenda", icon: "calendar", tint: soon ? "#FF5B37" : "#FFD65C",
                                title: "Agenda", detail: "\(when) · \(e.title)", urgent: false,
                                pill: "integration_agenda", url: e.meetingURL ?? AgendaPoller.calendarURL))
            } else if state.agendaLastSync != nil {
                out.append(Line(id: "agenda", icon: "calendar", tint: "#8E939C", title: "Agenda",
                                detail: "rien de prévu sur 14 jours", urgent: false,
                                pill: "integration_agenda", url: AgendaPoller.calendarURL))
            }
        }

        // Projects (espace client)
        let active = state.espaceClients.filter { !$0.isDone }
        if KeychainStore.shared.get("espace-token") == nil {
            out.append(Line(id: "espace", icon: "folder", tint: "#8E939C", title: "Espace client",
                            detail: "jeton à ajouter dans Réglages", urgent: false, pill: nil, url: nil))
        } else if !active.isEmpty {
            let next = active.sorted { ($0.daysLeft ?? 9999) < ($1.daysLeft ?? 9999) }.first!
            let late = active.filter { ($0.daysLeft ?? 0) < 0 }
            let title = late.isEmpty ? "Projets" : "Retard"
            let lead = late.isEmpty ? (active.count > 1 ? "\(active.count) en cours · " : "") : ""
            let detail = lead + "\(next.name) · \(next.daysLabel) · \(next.stepLabel)"
            out.append(Line(id: "espace", icon: "folder.fill", tint: late.isEmpty ? (next.urgency == .calm ? "#FF5B37" : next.urgency.hex) : "#F4505E",
                            title: title, detail: detail, urgent: !late.isEmpty,
                            pill: "integration_espace", url: EspacePoller.adminURL))
        } else if state.espaceLastSync != nil {
            out.append(Line(id: "espace", icon: "folder", tint: "#8E939C", title: "Aucun projet en cours", detail: "",
                            urgent: false, pill: "integration_espace", url: EspacePoller.adminURL))
        }

        // Instagram (only once a token is set)
        if let s = state.social, s.fetchedAt != nil {
            let reminders = s.reminders()
            let title = "Insta"
            let detail = s.error ?? (reminders.isEmpty ? "\(s.followersLabel) · \(s.lastPostLabel())" : reminders.joined(separator: " · "))
            out.append(Line(id: "instagram", icon: "camera.fill", tint: s.error != nil ? "#F4505E" : reminders.isEmpty ? "#E1306C" : "#FFD65C",
                            title: title, detail: detail, urgent: false, pill: SocialPoller.pillId,
                            url: URL(string: s.username.isEmpty ? "https://www.instagram.com" : "https://www.instagram.com/\(s.username)/")))
        }

        // Urgent lines first, otherwise the fixed order above (a plain sort is not stable and would reshuffle).
        return out.filter(\.urgent) + out.filter { !$0.urgent }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(greeting)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                Text(day)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#8E939C"))
            }
            .lineLimit(1)
            .padding(.leading, 8)
            .padding(.trailing, 28)   // keep clear of the card's corner button
            if layout.style == .bento && !layout.visibleTiles.isEmpty {
                // Réglages → Accueil : the tiles chosen there, two rows fit in the notch.
                HomeBentoView(state: state, columns: 3, tileHeight: 38, spacing: 5, maxRows: 2)
                    .padding(.leading, 4)
                    .padding(.top, 2)
            } else {
            if lines.isEmpty {
                Text("Branche l’espace client ou ajoute des sites dans Réglages pour que je te tienne au courant.")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#8E939C"))
                    .padding(.leading, 8)
            }
            ForEach(lines) { line in
                Button(action: { open(line) }) {
                    HStack(spacing: 6) {
                        Image(systemName: line.icon)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color(hex: line.tint))
                            .frame(width: 14)
                        Text(line.title)
                            .font(.system(size: 11, weight: line.urgent ? .bold : .semibold))
                            .foregroundColor(Color(hex: line.urgent ? "#FF8D97" : "#C5C8CD"))
                            .lineLimit(1)
                            .fixedSize()
                            .frame(minWidth: 44, alignment: .leading)
                        Text(line.detail)
                            .font(.system(size: 10.5))
                            .foregroundColor(Color(hex: line.urgent ? "#FF8D97" : "#9398A1"))
                            .lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(line.urgent ? Color(hex: "#F4505E").opacity(0.10) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            }
        }
        .padding(.top, 8)
        .padding(.leading, 100)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Focus the pill when it is in the island, else open the web page.
    private func open(_ line: Line) {
        if let pill = line.pill, state.tasks.contains(where: { $0.id == pill }) {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { state.focusId = pill }
        } else if let url = line.url {
            NSWorkspace.shared.open(url)
        }
    }
}
