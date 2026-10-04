import SwiftUI

// MARK: - Aujourd'hui
// What matters right now, most urgent first; each line jumps to its section.

struct HomeSection: View {
    @EnvironmentObject var model: OliModel

    private struct Item: Identifiable {
        let id: String
        let icon: String
        let color: Color
        let title: String
        let detail: String
        let urgent: Bool
        let go: Section
    }

    private var items: [Item] {
        var out: [Item] = []
        if let a = model.approvals.first {
            out.append(Item(id: "approval", icon: "hand.raised.fill", color: Palette.beurre,
                            title: "Claude attend ton accord", detail: "\(a.project) · \(a.summary)", urgent: true, go: .claude))
        }
        let down = model.sites.filter { $0.status == .down }
        if !down.isEmpty {
            out.append(Item(id: "down", icon: "exclamationmark.triangle.fill", color: Palette.alerte,
                            title: down.count == 1 ? "\(down[0].name) est en panne" : "\(down.count) sites en panne",
                            detail: down[0].reason ?? "injoignable", urgent: true, go: .sites))
        }
        let late = model.projects.filter(\.isLate)
        if !late.isEmpty {
            out.append(Item(id: "late", icon: "clock.badge.exclamationmark.fill", color: Palette.alerte,
                            title: late.count == 1 ? "\(late[0].name) est en retard" : "\(late.count) projets en retard",
                            detail: late[0].stepLabel, urgent: true, go: .projects))
        }
        let working = model.sessions.filter { $0.phase == .working }
        if let w = working.first {
            out.append(Item(id: "claude", icon: "sparkles", color: Palette.lilas,
                            title: working.count == 1 ? "Claude travaille sur \(w.project)" : "\(working.count) sessions Claude en cours",
                            detail: w.activity, urgent: false, go: .claude))
        }
        if let e = model.nextEvent {
            let when = e.isToday ? e.timeLabel : e.isTomorrow ? "demain \(e.timeLabel)" : "\(e.dayLabel) \(e.timeLabel)"
            out.append(Item(id: "agenda", icon: "calendar", color: Palette.ciel, title: e.title, detail: when, urgent: false, go: .agenda))
        }
        let active = model.projects.filter { !$0.isDone && !$0.isLate }
        if let p = active.first {
            out.append(Item(id: "projects", icon: "square.stack.3d.up.fill", color: Palette.tomate,
                            title: active.count == 1 ? p.name : "\(active.count) projets en cours",
                            detail: "\(p.name) · \(p.dueLabel) · \(p.stepLabel)", urgent: false, go: .projects))
        }
        if down.isEmpty, !model.sites.isEmpty {
            let warn = model.sites.filter { $0.status == .warning || !(model.siteAudits[$0.url]?.issues.isEmpty ?? true) }
            out.append(Item(id: "sites", icon: "globe.europe.africa.fill", color: warn.isEmpty ? Palette.menthe : Palette.beurre,
                            title: "\(model.sites.count) site\(model.sites.count > 1 ? "s" : "") en ligne",
                            detail: warn.first.map { $0.reason ?? model.siteAudits[$0.url]?.issues.first ?? "à surveiller" } ?? "tout va bien",
                            urgent: false, go: .sites))
        }
        if let s = model.instagram, s.fetchedAt != nil {
            let r = s.reminders()
            out.append(Item(id: "insta", icon: "camera.fill", color: r.isEmpty ? Palette.rose : Palette.beurre,
                            title: "Instagram", detail: s.error ?? (r.isEmpty ? "\(s.followersLabel) · \(s.lastPostLabel())" : r.joined(separator: " · ")),
                            urgent: false, go: .instagram))
        }
        return out
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                if let b = model.briefing {
                    Card(tint: Palette.beurre) {
                        HStack {
                            Text(b.kind == .morning ? "Le mot d’Oli" : "Le récap de la semaine")
                                .font(Typo.display(14, .bold)).foregroundStyle(Palette.beurre)
                            Spacer()
                            Button { model.briefing = nil } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                                .buttonStyle(.plain).foregroundStyle(Palette.sand)
                        }
                        Text(markdown(b.text))
                            .font(Typo.text(12)).foregroundStyle(Palette.cream)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
                if items.isEmpty && model.briefing == nil {
                    EmptyNote(icon: "sun.max", text: "Tout est calme. Branche l’espace client, tes sites ou l’agenda dans les Réglages pour que je te tienne au courant.")
                } else {
                    VStack(spacing: 2) {
                        ForEach(items) { i in
                            Row(color: i.color, icon: i.icon, title: i.title, detail: i.detail, strong: i.urgent,
                                action: { withAnimation { model.section = i.go } }) {
                                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.dust)
                            }
                        }
                    }
                }
                if model.briefing == nil {
                    HStack(spacing: 8) {
                        ActionButton(title: "Briefing", icon: "sun.horizon.fill", tint: Palette.beurre) { BriefingDesk.show(.morning) }
                        ActionButton(title: "Récap de la semaine", icon: "calendar.badge.checkmark", tint: Palette.sand) { BriefingDesk.show(.friday) }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}
