import SwiftUI

// MARK: - Projets (espace client)

struct ProjectsSection: View {
    @EnvironmentObject var model: OliModel
    @State private var open: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 6) {
                if let e = model.projectsError { Tag(text: e, tint: Palette.alerte) }
                if model.projects.isEmpty {
                    EmptyNote(icon: "square.stack.3d.up", text: model.projectsSynced == nil ? "Lecture de l’espace client…" : "Aucun projet en cours.")
                }
                ForEach(model.projects) { p in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 9) {
                            Dot(color: color(p))
                            Text(p.name).font(Typo.text(13, .bold)).foregroundStyle(Palette.cream).lineLimit(1)
                            Tag(text: p.kindLabel, tint: Palette.dust)
                            Spacer()
                            Tag(text: p.isDone ? "terminé" : p.dueLabel, tint: color(p))
                        }
                        HStack(spacing: 8) {
                            Progress(value: Double(p.stepsDone) / Double(max(1, p.steps.count)), tint: color(p))
                            Text("\(p.stepsDone)/\(p.steps.count) · \(p.stepLabel)")
                                .font(Typo.text(11)).foregroundStyle(Palette.sand).lineLimit(1).frame(width: 200, alignment: .leading)
                        }
                        if open == p.id { ProjectDetail(project: p) }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(open == p.id ? Palette.card : .clear))
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.spring(response: 0.3)) { open = open == p.id ? nil : p.id } }
                }
            }
        }
    }

    private func color(_ p: EspaceProject) -> Color {
        if p.isDone { return Palette.menthe }
        if p.isLate { return Palette.alerte }
        if let d = p.daysLeft, d <= 3 { return Palette.tomate }
        if let d = p.daysLeft, d <= 7 { return Palette.beurre }
        return Palette.sand
    }
}

private struct ProjectDetail: View {
    let project: EspaceProject

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(project.steps.enumerated()), id: \.offset) { _, s in
                HStack(spacing: 7) {
                    Image(systemName: s.state == "done" ? "checkmark.circle.fill" : s.state == "doing" ? "circle.lefthalf.filled" : "circle")
                        .font(.system(size: 10)).foregroundStyle(s.state == "done" ? Palette.menthe : s.state == "doing" ? Palette.tomate : Palette.dust)
                    Text(s.label).font(Typo.text(11.5)).foregroundStyle(s.state == "todo" ? Palette.sand : Palette.cream)
                }
            }
            if let n = project.notes.first {
                Text("Dernier mot (\(n.author)) : « \(n.body) »").font(Typo.text(11)).foregroundStyle(Palette.sand).lineLimit(2)
            } else if !project.contact.isEmpty {
                Text("Contact : \(project.contact)").font(Typo.text(11)).foregroundStyle(Palette.sand)
            }
            HStack(spacing: 8) {
                if let u = project.adminURL { ActionButton(title: "Fiche", icon: "arrow.up.right") { NSWorkspace.shared.open(u) } }
                if !project.liveUrl.isEmpty { ActionButton(title: "Site", icon: "globe", tint: Palette.menthe) { openURL(project.liveUrl) } }
                if !project.previewUrl.isEmpty { ActionButton(title: "Aperçu", icon: "eye", tint: Palette.sand) { openURL(project.previewUrl) } }
                if let dir = RepoFinder.localFolder(for: project.repo) {
                    ActionButton(title: "Claude Code", icon: "sparkles", tint: Palette.lilas) { TerminalCommands.open(folder: dir, runClaude: true) }
                }
            }
        }
        .padding(.top, 4)
    }
}

/// Local clone of a client's GitHub repo (top level of ~ and ~/refontes).
@MainActor
enum RepoFinder {
    private static var cache: [String: String?] = [:]
    static func localFolder(for repo: String) -> String? {
        guard !repo.isEmpty else { return nil }
        if let hit = cache[repo] { return hit }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let found = LocalRepoFinder.find(repo: repo, roots: [home, home.appendingPathComponent("refontes")])?.path
        cache[repo] = found
        return found
    }
}

// MARK: - Sites

struct SitesSection: View {
    @EnvironmentObject var model: OliModel
    @State private var open: String? = nil

    private var sorted: [SiteCheck] {
        model.sites.sorted { a, b in a.status.order != b.status.order ? a.status.order < b.status.order : a.name < b.name }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 4) {
                if model.sites.isEmpty {
                    EmptyNote(icon: "globe.europe.africa", text: model.siteTargets.isEmpty ? "Aucun site à surveiller. Ajoute-en dans les Réglages." : "Première vérification en cours…")
                }
                ForEach(sorted) { s in
                    let audit = model.siteAudits[s.url]
                    let issue = s.reason ?? audit?.issues.first
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 9) {
                            Dot(color: color(s, audit))
                            Text(s.name).font(Typo.text(13, s.status == .down ? .bold : .semibold))
                                .foregroundStyle(s.status == .down ? Palette.alerte : Palette.cream).lineLimit(1)
                            if s.name != s.shortHost { Text(s.shortHost).font(Typo.text(11)).foregroundStyle(Palette.dust).lineLimit(1) }
                            Spacer()
                            Text(issue ?? s.latencyLabel).font(Typo.text(11.5, issue == nil ? .regular : .semibold))
                                .foregroundStyle(issue == nil ? Palette.sand : color(s, audit)).lineLimit(1)
                        }
                        if open == s.id { SiteDetail(site: s, audit: audit) }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(open == s.id ? Palette.card : s.status == .down ? Palette.alerte.opacity(0.08) : .clear))
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.spring(response: 0.3)) { open = open == s.id ? nil : s.id } }
                }
            }
        }
        .onAppear { if model.alarm, let d = sorted.first(where: { $0.status == .down }) { open = d.id } }
    }

    private func color(_ s: SiteCheck, _ a: SiteAudit?) -> Color {
        switch s.status {
        case .down: return Palette.alerte
        case .warning: return Palette.beurre
        case .ok: return (a?.issues.isEmpty ?? true) ? Palette.menthe : Palette.beurre
        case .unknown: return Palette.dust
        }
    }
}

private struct SiteDetail: View {
    let site: SiteCheck
    let audit: SiteAudit?
    @EnvironmentObject var model: OliModel

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Tag(text: site.httpLabel, tint: Palette.sand)
                Tag(text: site.latencyLabel, tint: (site.latencyMs ?? 0) > SiteCheck.slowMs ? Palette.beurre : Palette.sand)
                Tag(text: site.tlsLabel, tint: (site.tlsDaysLeft ?? 99) < SiteCheck.tlsWarningDays ? Palette.beurre : Palette.sand)
            }
            if let a = audit {
                HStack(spacing: 6) {
                    Tag(text: a.pagespeedLabel, tint: (a.pagespeed ?? 100) < SiteAudit.pagespeedWarning ? Palette.beurre : Palette.sand)
                    Tag(text: a.domainLabel, tint: (a.domainDaysLeft ?? 99) < SiteAudit.domainWarningDays ? Palette.beurre : Palette.sand)
                    if let ok = a.sitemapOK { Tag(text: ok ? "sitemap \(a.sitemapCount ?? 0) URL" : "pas de sitemap", tint: ok ? Palette.sand : Palette.beurre) }
                }
                ForEach(a.issues, id: \.self) { i in
                    Text("• " + i).font(Typo.text(11.5)).foregroundStyle(Palette.beurre)
                }
                if !a.brokenLinks.isEmpty {
                    Text(a.brokenLinks.prefix(4).joined(separator: "  ·  ")).font(Typo.mono(10.5)).foregroundStyle(Palette.sand).lineLimit(2)
                }
            }
            HStack(spacing: 8) {
                ActionButton(title: "Ouvrir", icon: "globe", tint: Palette.menthe) { openURL(site.url) }
                ActionButton(title: "Revérifier", icon: "arrow.clockwise", tint: Palette.sand) {
                    SitesWatcher.shared.refresh(); SitesWatcher.shared.audit(force: site.url)
                }
                if let p = model.projects.first(where: { SiteMonitor.normalize($0.liveUrl) == site.url }),
                   let dir = RepoFinder.localFolder(for: p.repo) {
                    ActionButton(title: "Corriger avec Claude Code", icon: "sparkles", tint: Palette.lilas) {
                        TerminalCommands.open(folder: dir, runClaude: true)
                    }
                }
            }
        }
    }
}

// MARK: - Agenda

struct AgendaSection: View {
    @EnvironmentObject var model: OliModel

    private var days: [(String, [AgendaEvent])] {
        let groups = Dictionary(grouping: model.agenda) { Calendar.current.startOfDay(for: $0.start) }
        return groups.keys.sorted().map { d in
            let label = Calendar.current.isDateInToday(d) ? "Aujourd’hui" : Calendar.current.isDateInTomorrow(d) ? "Demain"
                : d.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_FR"))).capitalized
            return (label, groups[d]!.sorted { $0.start < $1.start })
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                if let e = model.agendaError { Tag(text: e, tint: Palette.alerte) }
                if model.agenda.isEmpty {
                    EmptyNote(icon: "calendar", text: model.agendaSynced == nil ? "Lecture de l’agenda…" : "Rien de prévu sur 14 jours.")
                }
                ForEach(days, id: \.0) { day, events in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(day).font(Typo.display(13, .bold)).foregroundStyle(Palette.ciel)
                        ForEach(events) { e in
                            Row(color: Palette.ciel, title: e.isAllDay ? "Journée" : e.timeLabel, detail: e.title,
                                action: { openURL(e.meetingURL?.absoluteString ?? AgendaWatcher.calendarURL.absoluteString) }) {
                                if e.meetingURL != nil { Tag(text: "visio", tint: Palette.ciel) }
                                if !e.location.isEmpty { Text(e.location).font(Typo.text(10.5)).foregroundStyle(Palette.dust).lineLimit(1) }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Instagram

struct InstagramSection: View {
    @EnvironmentObject var model: OliModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                if let s = model.instagram {
                    if let e = s.error {
                        Card(tint: Palette.alerte) { Text(e).font(Typo.text(12.5, .semibold)).foregroundStyle(Palette.alerte) }
                    } else {
                        HStack(spacing: 8) {
                            Tag(text: s.followersLabel, tint: Palette.rose)
                            Tag(text: s.lastPostLabel(), tint: (s.daysSinceLastPost() ?? 0) >= SocialSnapshot.quietDays ? Palette.beurre : Palette.sand)
                            Spacer()
                            ActionButton(title: "Ouvrir", icon: "arrow.up.right", tint: Palette.rose) { openURL("https://www.instagram.com/\(s.username)/") }
                        }
                        if !s.unanswered.isEmpty {
                            Text("Sans réponse").font(Typo.display(13)).foregroundStyle(Palette.beurre)
                            ForEach(s.unanswered.prefix(6)) { c in
                                Row(color: Palette.beurre, icon: "bubble.left.fill", title: "@" + c.username, detail: c.text,
                                    action: { openURL(c.postPermalink) })
                            }
                        }
                        Text("Derniers posts").font(Typo.display(13)).foregroundStyle(Palette.cream)
                        ForEach(s.posts.prefix(6)) { p in
                            Row(color: Palette.rose, icon: "photo", title: p.caption.isEmpty ? "Sans légende" : String(p.caption.prefix(50)),
                                detail: "♥ \(p.likes)  ·  \(p.comments) comm.", action: { openURL(p.permalink) })
                        }
                    }
                } else {
                    EmptyNote(icon: "camera", text: "Lecture d’Instagram…")
                }
            }
        }
    }
}
