import SwiftUI

// MARK: - Onglet ✉︎ : les mails
// Les 40 derniers mails, triés par catégorie (Oli d'abord, Claude ensuite). On change une catégorie
// d'un clic sur sa pastille. « Ranger » range sur le serveur tout ce qui n'est pas « À traiter ».

struct MailIslandView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var mail = MailCenter.shared
    @State private var adding = false

    private var shown: [OliMail] {
        guard let f = mail.filter else { return mail.mails }
        return mail.mails.filter { (mail.categories[$0.uid] ?? .important) == f }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .trailing) {
                IslandViewTitle(icon: "envelope.fill", color: "#FF8A52", title: "Mails", subtitle: "")
                HStack(spacing: 8) {
                    accountMenu
                    Spacer()
                }
                .padding(.leading, 124)
                if mail.isConnected {
                    Button { Task { await mail.refresh() } } label: {
                        Group {
                            if mail.loading { ProgressView().controlSize(.mini) }
                            else { Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold)) }
                        }
                        .foregroundColor(Color(hex: "#8E939C")).frame(width: 24, height: 22)
                    }
                    .buttonStyle(.plain).help("Relever les mails")
                }
            }

            if adding || !mail.isConnected {
                AddMailboxForm(first: !mail.isConnected) { adding = false }
                    .padding(.leading, 60)
                Spacer(minLength: 0)
            } else if let e = mail.error, mail.mails.isEmpty {
                Text(e).font(.system(size: 11.5)).foregroundColor(Color(hex: "#FF8D97")).padding(.leading, 60)
                Spacer()
            } else {
                filters
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        if shown.isEmpty && !mail.loading {
                            Text(mail.filter == nil ? "Boîte de réception vide ✨" : "Rien dans « \(mail.filter!.label) »")
                                .font(.system(size: 11.5)).foregroundColor(Color(hex: "#8E939C")).padding(8)
                        }
                        ForEach(shown) { m in row(m) }
                    }
                    .padding(.bottom, 4)
                }
                .clipped()
                Divider().overlay(Color.white.opacity(0.06))
                footer
            }
        }
        .padding(.horizontal, 4)
        .onAppear { if mail.lastSync == nil || Date().timeIntervalSince(mail.lastSync!) > 60 { Task { await mail.refresh() } } }
    }

    /// The mailbox shown, to switch, add or remove one.
    private var accountMenu: some View {
        Menu {
            ForEach(mail.boxes) { b in
                Button { mail.switchTo(b) } label: {
                    Label(b.address, systemImage: b.id == mail.box?.id ? "checkmark" : (b.isGmail ? "g.circle" : "envelope"))
                }
            }
            Divider()
            Button { adding = true } label: { Label("Ajouter une boîte (Gmail, iCloud…)", systemImage: "plus") }
            if let b = mail.box, MailAccounts.extras.contains(where: { $0.id == b.id }) {
                Button(role: .destructive) {
                    MailAccounts.remove(b)
                    if let first = MailAccounts.all.first { mail.switchTo(first) }
                } label: { Label("Retirer \(b.address) d’Oli", systemImage: "minus.circle") }
            }
        } label: {
            HStack(spacing: 5) {
                Text(mail.box?.address ?? "Ajouter une boîte").font(.system(size: 11, weight: .semibold))
                if let u = mail.unread { Text("· \(u) non lu\(u > 1 ? "s" : "")").font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C")) }
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold)).opacity(0.6)
            }
            .foregroundColor(Color(hex: "#C5C8CD"))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.07)))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help("Changer de boîte mail, ou en ajouter une")
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                chip("Tout", count: mail.mails.count, color: "#C5C8CD", on: mail.filter == nil) { mail.filter = nil }
                ForEach(MailCategory.allCases, id: \.self) { c in
                    let n = mail.mails.filter { (mail.categories[$0.uid] ?? .important) == c }.count
                    if n > 0 { chip(c.label, count: n, color: c.color, on: mail.filter == c) { mail.filter = mail.filter == c ? nil : c } }
                }
            }
        }
    }

    private func chip(_ text: String, count: Int, color: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(text).font(.system(size: 10.5, weight: .semibold))
                Text("\(count)").font(.system(size: 9.5, weight: .bold)).opacity(0.7)
            }
            .foregroundColor(on ? .white : Color(hex: color))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(on ? Color(hex: color).opacity(0.85) : Color(hex: color).opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    private func row(_ m: OliMail) -> some View {
        let cat = mail.categories[m.uid] ?? .important
        return HStack(alignment: .center, spacing: 10) {
            Circle().fill(m.unread ? Color(hex: "#3B9EFF") : Color.clear).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(m.fromName).font(.system(size: 11.5, weight: m.unread ? .bold : .semibold))
                        .foregroundColor(Color(hex: "#F5F6F8")).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(timeLabel(m.date)).font(.system(size: 10)).foregroundColor(Color(hex: "#6B7079"))
                }
                Text(m.subject).font(.system(size: 11.5, weight: m.unread ? .semibold : .regular))
                    .foregroundColor(Color(hex: "#D5D8DD")).lineLimit(1)
                Text(mail.summaries[m.uid] ?? m.snippet).font(.system(size: 10.5))
                    .foregroundColor(Color(hex: mail.summaries[m.uid] == nil ? "#6B7079" : "#A9AEB7")).lineLimit(1)
            }
            Menu {
                ForEach(MailCategory.allCases, id: \.self) { c in
                    Button { mail.set(m.uid, c) } label: { Label(c.label, systemImage: c.icon) }
                }
            } label: {
                CategoryChip(cat: cat, sparkle: mail.byClaudeOnly(m.uid))
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .help("Changer la catégorie")
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(hex: "#16171A")))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { mail.open(m) }
        .help("Double-clic : ouvrir le mail")
    }

    private func timeLabel(_ d: Date) -> String {
        let fr = Locale(identifier: "fr_FR")
        if Calendar.current.isDateInToday(d) { return d.formatted(.dateTime.hour().minute().locale(fr)) }
        if Calendar.current.isDateInYesterday(d) { return "hier" }
        return d.formatted(.dateTime.day().month(.abbreviated).locale(fr))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(mail.result ?? "Claude ne lit que l’expéditeur, l’objet et le début.")
                .font(.system(size: 10.5, weight: mail.result == nil ? .regular : .semibold))
                .foregroundColor(Color(hex: mail.result == nil ? "#6B7079" : "#4ADE80"))
                .lineLimit(2)
            Spacer()
            if mail.canUndo {
                Button("Annuler") { Task { await mail.undo() } }
                    .buttonStyle(.plain).font(.system(size: 10.5, weight: .semibold)).foregroundColor(Color(hex: "#FF8A52"))
                    .help("Remettre dans la boîte de réception les mails du dernier rangement")
            }
            Button { Task { await mail.classifyWithClaude() } } label: {
                HStack(spacing: 4) {
                    if mail.classifying { ProgressView().controlSize(.mini) } else { Image(systemName: "sparkles") }
                    Text("Classer avec Claude").font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(Color(hex: "#E07950"))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Color(hex: "#E07950").opacity(0.15)))
            }
            .buttonStyle(.plain).disabled(mail.classifying || mail.mails.isEmpty)
            Button { Task { await mail.tidy() } } label: {
                HStack(spacing: 4) {
                    if mail.moving { ProgressView().controlSize(.mini) } else { Image(systemName: "tray.and.arrow.down.fill") }
                    Text(mail.toTidy.isEmpty ? "Ranger" : "Ranger \(mail.toTidy.count)").font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Capsule().fill(Color(hex: mail.toTidy.isEmpty ? "#3A3C42" : "#FF5B37")))
            }
            .buttonStyle(.plain).disabled(mail.toTidy.isEmpty || mail.moving)
            .help("Range sur le serveur, dans « Oli/… », tout ce qui n’est pas « À traiter ». Rien n’est supprimé.")
        }
    }
}

extension MailCenter {
    /// The user's own choice wins over a later refresh, like Claude's.
    func set(_ uid: Int, _ c: MailCategory) {
        categories[uid] = c
        markDecided(uid)
    }

    func byClaudeOnly(_ uid: Int) -> Bool { summaries[uid] != nil }
}

/// Category pill of a mail; keeps its colours inside a Menu (plain button style).
struct CategoryChip: View {
    let cat: MailCategory
    var sparkle = false
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: cat.icon).font(.system(size: 8.5, weight: .bold))
            Text(cat.label).font(.system(size: 10, weight: .semibold))
            if sparkle { Image(systemName: "sparkles").font(.system(size: 7.5)) }
            Image(systemName: "chevron.down").font(.system(size: 6.5, weight: .bold)).opacity(0.6)
        }
        .foregroundColor(Color(hex: cat.color))
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(Color(hex: cat.color).opacity(0.15)))
        .contentShape(Capsule())
    }
}

// MARK: - Onglet 📅 : l'agenda en bento
// En haut quatre tuiles : Prochain RDV, Appels à prendre, Nouveautés, Nouveau RDV.
// Dessous, le détail de la tuile choisie (la semaine, les appels, les nouveautés, le formulaire).

struct AgendaIslandView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var oc = OculotAgenda.shared

    enum Pane { case upcoming, calls, news, create, unlock }
    @State private var pane: Pane = .upcoming
    @State private var afterUnlock: Pane = .calls
    @State private var busy: String? = nil

    private var connected: Bool { ConnectionKind.agenda.isConnected || oc.isUnlocked }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .trailing) {
                IslandViewTitle(icon: "calendar", color: "#FFB547", title: "Agenda", subtitle: subtitle)
                Button { NSWorkspace.shared.open(AgendaPoller.calendarURL) } label: {
                    Label("Ouvrir", systemImage: "arrow.up.right").font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(Color(hex: "#8E939C"))
                }
                .buttonStyle(.plain)
            }
            if !connected {
                connectPrompt
            } else {
                bento
                Group {
                    switch pane {
                    case .upcoming: upcomingList
                    case .calls:    callsList
                    case .news:     newsList
                    case .create:   NewRdvForm(oc: oc) { pane = .upcoming }
                    case .unlock:   UnlockAgendaForm(oc: oc) { pane = afterUnlock }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                if let e = oc.error, pane != .unlock {
                    Text(e).font(.system(size: 10.5)).foregroundColor(Color(hex: "#FF8D97"))
                }
            }
        }
        .padding(.horizontal, 4)
        .onAppear { AgendaPoller.shared.pollNow(); Task { await oc.refresh() } }
        .onChange(of: pane) { old, _ in if old == .news { oc.markSeen() } }
    }

    private var subtitle: String {
        guard let e = state.nextEvent else { return connected ? "rien de prévu sur 14 jours" : "pas encore branché" }
        let mins = Int(e.start.timeIntervalSinceNow / 60)
        if e.start <= Date() { return "en cours : \(e.title)" }
        if mins < 60 { return "prochain dans \(max(1, mins)) min" }
        if e.isToday { return "prochain à \(e.timeLabel)" }
        return "prochain \(e.dayLabel) à \(e.timeLabel)"
    }

    private var connectPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Branche ton agenda : Oli te montre ta journée, les appels à prendre, te rappelle tes rendez-vous et t’ouvre la visio d’un clic.")
                .font(.system(size: 12)).foregroundColor(Color(hex: "#C5C8CD")).fixedSize(horizontal: false, vertical: true)
            Button { OneClickConnect.start(.agenda) } label: {
                Text("Connecter mon agenda").font(.system(size: 11.5, weight: .bold)).foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 6).background(Capsule().fill(Color(hex: "#FF5B37")))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.leading, 60).padding(.top, 6)
    }

    // MARK: Bento

    private var bento: some View {
        let next = state.nextEvent
        let calls = oc.callsToTake
        let news = oc.news
        return HStack(spacing: 6) {
            tile(icon: "calendar.badge.clock", color: "#FFB547", title: "Prochain RDV",
                 value: next.map { $0.start <= Date() ? "En cours" : $0.isToday ? $0.timeLabel : $0.isTomorrow ? "Demain \($0.timeLabel)" : $0.dayLabel } ?? "Libre",
                 detail: next?.title ?? "rien sur 14 jours", on: pane == .upcoming, wide: true,
                 trailing: next?.meetingURL.map { url in AnyView(joinButton(url)) }) { pane = .upcoming }
            tile(icon: "phone.fill", color: "#22C55E", title: "Appels à prendre",
                 value: oc.isUnlocked ? "\(calls.count)" : "🔒",
                 detail: oc.isUnlocked ? (calls.first.map { "\(rdvWhen($0)) · \($0.who.isEmpty ? $0.titre : $0.who)" } ?? "aucun en attente") : "débloquer",
                 on: pane == .calls, alert: !calls.isEmpty) { open(.calls) }
            tile(icon: "sparkles", color: "#A78BFA", title: "Nouveautés",
                 value: oc.isUnlocked ? "\(news.count)" : "🔒",
                 detail: oc.isUnlocked ? (news.first?.titre ?? "rien de neuf") : "débloquer",
                 on: pane == .news, alert: !news.isEmpty) { open(.news) }
            Button { open(.create) } label: {
                VStack(spacing: 4) {
                    Image(systemName: "plus").font(.system(size: 16, weight: .bold))
                    Text("Nouveau RDV").font(.system(size: 10.5, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(width: 92, height: 58)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: pane == .create ? "#E04A28" : "#FF5B37")))
            }
            .buttonStyle(.plain)
        }
    }

    private func open(_ p: Pane) {
        if oc.isUnlocked || p == .upcoming { pane = p } else { afterUnlock = p; pane = .unlock }
    }

    private func tile(icon: String, color: String, title: String, value: String, detail: String, on: Bool,
                      wide: Bool = false, alert: Bool = false, trailing: AnyView? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: icon).font(.system(size: 8.5, weight: .bold)).foregroundColor(Color(hex: color))
                        Text(title).font(.system(size: 9.5, weight: .semibold)).foregroundColor(Color(hex: "#8E939C")).lineLimit(1)
                        if alert { Circle().fill(Color(hex: color)).frame(width: 5, height: 5) }
                    }
                    Text(value).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundColor(Color(hex: "#F5F6F8"))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(detail).font(.system(size: 10)).foregroundColor(Color(hex: "#A9AEB7")).lineLimit(1)
                }
                Spacer(minLength: 0)
                if let trailing { trailing }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: wide ? .infinity : 150, minHeight: 58, maxHeight: 58, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: on ? "#1E2024" : "#16171A")))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(hex: color).opacity(on ? 0.6 : 0.12), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func joinButton(_ url: URL) -> some View {
        Button { NSWorkspace.shared.open(url) } label: {
            Image(systemName: "video.fill").font(.system(size: 10, weight: .bold)).foregroundColor(.white)
                .frame(width: 26, height: 26).background(Circle().fill(Color(hex: "#22C55E")))
        }
        .buttonStyle(.plain).help("Rejoindre la visio")
    }

    // MARK: Panes

    private var days: [(day: Date, events: [AgendaEvent])] {
        let cal = Calendar.current
        let now = Date()
        let upcoming = state.agendaEvents.filter { $0.end > now || cal.isDateInToday($0.start) }.sorted { $0.start < $1.start }
        let grouped = Dictionary(grouping: upcoming) { cal.startOfDay(for: $0.start) }
        return grouped.keys.sorted().map { ($0, grouped[$0]!) }
    }

    private var upcomingList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if days.isEmpty {
                    Text("Rien de prévu sur les 14 prochains jours 🎉").font(.system(size: 11.5)).foregroundColor(Color(hex: "#8E939C")).padding(6)
                }
                ForEach(days, id: \.day) { d in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(dayTitle(d.day)).font(.system(size: 9.5, weight: .bold)).kerning(0.5)
                            .foregroundColor(Color(hex: Calendar.current.isDateInToday(d.day) ? "#FFB547" : "#6B7079"))
                        ForEach(d.events) { e in eventRow(e) }
                    }
                }
            }
        }
    }

    private var callsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 5) {
                if oc.callsToTake.isEmpty {
                    Text("Aucun appel en attente : tout le monde est servi 👌").font(.system(size: 11.5)).foregroundColor(Color(hex: "#8E939C")).padding(6)
                }
                ForEach(oc.callsToTake) { r in
                    rdvRow(r) {
                        if !r.tel.isEmpty, let u = URL(string: "tel:" + r.tel.filter { $0.isNumber || $0 == "+" }) {
                            Button { NSWorkspace.shared.open(u) } label: {
                                Image(systemName: "phone.fill").font(.system(size: 10)).foregroundColor(Color(hex: "#22C55E"))
                                    .frame(width: 26, height: 24).background(Capsule().fill(Color(hex: "#22C55E").opacity(0.15)))
                            }
                            .buttonStyle(.plain).help(r.tel)
                        }
                        if oc.isAdmin {
                            Button {
                                busy = r.id
                                Task { _ = await oc.take(r); busy = nil }
                            } label: {
                                HStack(spacing: 4) {
                                    if busy == r.id { ProgressView().controlSize(.mini) }
                                    Text("Je le prends").font(.system(size: 10.5, weight: .bold))
                                }
                                .foregroundColor(.white).padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Capsule().fill(Color(hex: "#22C55E")))
                            }
                            .buttonStyle(.plain).disabled(busy != nil)
                        }
                    }
                }
            }
        }
    }

    private var newsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 5) {
                if oc.news.isEmpty {
                    Text("Rien de nouveau depuis ta dernière visite.").font(.system(size: 11.5)).foregroundColor(Color(hex: "#8E939C")).padding(6)
                }
                ForEach(oc.news) { r in
                    rdvRow(r) {
                        Text("par \(oc.team[r.creePar] ?? r.creePar)").font(.system(size: 10)).foregroundColor(Color(hex: "#8E939C"))
                    }
                }
            }
        }
    }

    private func rdvRow<T: View>(_ r: OculotRdv, @ViewBuilder trailing: () -> T) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(r.journee ? "Journée" : r.debut).font(.system(size: 11.5, weight: .bold, design: .rounded)).foregroundColor(Color(hex: "#E4E6EA"))
                Text(rdvDay(r)).font(.system(size: 9.5)).foregroundColor(Color(hex: "#6B7079"))
            }
            .frame(width: 58, alignment: .trailing)
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: r.isCall ? "#22C55E" : "#FFB547")).frame(width: 3, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(r.titre).font(.system(size: 11.5, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8")).lineLimit(1)
                Text([r.who, r.lieu].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 10)).foregroundColor(Color(hex: "#8E939C")).lineLimit(1)
            }
            Spacer(minLength: 4)
            trailing()
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(hex: "#16171A")))
    }

    private func rdvDay(_ r: OculotRdv) -> String {
        guard let s = r.start else { return r.date }
        let cal = Calendar.current
        if cal.isDateInToday(s) { return "aujourd’hui" }
        if cal.isDateInTomorrow(s) { return "demain" }
        return s.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Locale(identifier: "fr_FR")))
    }

    private func rdvWhen(_ r: OculotRdv) -> String { "\(rdvDay(r)) \(r.debut)" }

    private func dayTitle(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "AUJOURD’HUI" }
        if cal.isDateInTomorrow(d) { return "DEMAIN" }
        return d.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_FR"))).uppercased()
    }

    private func eventRow(_ e: AgendaEvent) -> some View {
        let now = Date()
        let live = e.start <= now && e.end > now
        let past = e.end <= now
        let soon = !live && e.start.timeIntervalSince(now) < 3600 && e.start > now
        return HStack(spacing: 10) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(e.timeLabel).font(.system(size: 11.5, weight: .bold, design: .rounded))
                if !e.isAllDay {
                    Text(e.end.formatted(.dateTime.hour().minute().locale(Locale(identifier: "fr_FR"))))
                        .font(.system(size: 9.5, design: .rounded)).foregroundColor(Color(hex: "#6B7079"))
                }
            }
            .foregroundColor(Color(hex: "#E4E6EA")).frame(width: 58, alignment: .trailing)
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: live ? "#22C55E" : soon ? "#FF5B37" : "#FFB547")).frame(width: 3, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(e.title).font(.system(size: 11.5, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8")).lineLimit(1)
                    if live { badge("en cours", "#22C55E") }
                    else if soon { badge("dans \(max(1, Int(e.start.timeIntervalSince(now) / 60))) min", "#FF5B37") }
                }
                if !e.location.isEmpty {
                    Text(e.location).font(.system(size: 10)).foregroundColor(Color(hex: "#8E939C")).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let link = e.meetingURL {
                Button { NSWorkspace.shared.open(link) } label: {
                    Label("Rejoindre", systemImage: "video.fill").font(.system(size: 10.5, weight: .bold)).foregroundColor(.white)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(Color(hex: live || soon ? "#22C55E" : "#2A2C31")))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(hex: live ? "#13251A" : "#16171A")))
        .opacity(past ? 0.45 : 1)
    }

    private func badge(_ t: String, _ c: String) -> some View {
        Text(t).font(.system(size: 9, weight: .bold)).foregroundColor(Color(hex: c))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(Color(hex: c).opacity(0.15)))
    }
}

// MARK: - Débloquer l'agenda (mot de passe, une fois)

struct UnlockAgendaForm: View {
    @ObservedObject var oc: OculotAgenda
    let done: () -> Void
    @State private var pw = ""
    @State private var members: [AgendaLogin.Member] = []
    @State private var member: String? = nil
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pour voir les appels à prendre, les nouveautés et créer des rendez-vous, Oli a besoin du mot de passe de l’agenda Oculot (gardé dans le Trousseau).")
                .font(.system(size: 11)).foregroundColor(Color(hex: "#C5C8CD")).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                SecureField("Mot de passe de l’agenda", text: $pw)
                    .textFieldStyle(.plain).font(.system(size: 12))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.07)))
                    .frame(width: 230)
                    .onSubmit(go)
                if !members.isEmpty {
                    ForEach(members) { m in
                        Button { member = m.id; go() } label: {
                            Text(m.name).font(.system(size: 11, weight: .semibold))
                                .foregroundColor(member == m.id ? .white : Color(hex: "#C5C8CD"))
                                .padding(.horizontal, 9).padding(.vertical, 5)
                                .background(Capsule().fill(member == m.id ? Color(hex: "#FF5B37") : Color.white.opacity(0.07)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button(action: go) {
                    HStack(spacing: 4) {
                        if busy { ProgressView().controlSize(.mini) }
                        Text("Débloquer").font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(.white).padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Color(hex: pw.isEmpty ? "#3A3C42" : "#FF5B37")))
                }
                .buttonStyle(.plain).disabled(pw.isEmpty || busy)
            }
            if !members.isEmpty && member == nil {
                Text("Qui es-tu dans l’équipe ? Clique sur ton prénom.").font(.system(size: 10.5)).foregroundColor(Color(hex: "#FFD65C"))
            }
            if let e = oc.error { Text(e).font(.system(size: 10.5)).foregroundColor(Color(hex: "#FF8D97")) }
        }
    }

    private func go() {
        guard !pw.isEmpty, !busy else { return }
        busy = true
        Task {
            let r = await oc.unlock(password: pw, member: member)
            busy = false
            if r.ok { done() } else if !r.members.isEmpty { members = r.members }
        }
    }
}

// MARK: - Nouveau rendez-vous

struct NewRdvForm: View {
    @ObservedObject var oc: OculotAgenda
    let done: () -> Void

    @State private var titre = ""
    @State private var type = "appel"
    @State private var start = NewRdvForm.nextSlot()
    @State private var minutes = 30
    @State private var lieu = ""
    @State private var who: Set<String> = []
    @State private var busy = false
    @State private var ok = false

    private static let types: [(String, String)] = [("appel", "Appel"), ("client", "Client"), ("prospect", "Prospect"), ("prod", "Prod"), ("indispo", "Indispo")]

    static func nextSlot() -> Date {
        let now = Date().addingTimeInterval(3600)
        let c = Calendar.current
        let m = c.component(.minute, from: now)
        return c.date(bySettingHour: c.component(.hour, from: now), minute: m < 30 ? 30 : 0, second: 0, of: now)
            .map { m < 30 ? $0 : $0.addingTimeInterval(3600) } ?? now
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Titre du rendez-vous", text: $titre)
                    .textFieldStyle(.plain).font(.system(size: 12.5, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.07)))
                ForEach(Self.types, id: \.0) { t in pill(t.1, on: type == t.0) { type = t.0 } }
            }
            HStack(spacing: 8) {
                DatePicker("", selection: $start, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.field).labelsHidden().environment(\.locale, Locale(identifier: "fr_FR"))
                    .frame(width: 170)
                ForEach([15, 30, 45, 60, 90], id: \.self) { m in pill(m < 60 ? "\(m) min" : m == 60 ? "1 h" : "1 h 30", on: minutes == m) { minutes = m } }
                TextField("Lieu ou lien visio", text: $lieu)
                    .textFieldStyle(.plain).font(.system(size: 11.5))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.07)))
            }
            HStack(spacing: 6) {
                Text("Avec").font(.system(size: 10.5, weight: .semibold)).foregroundColor(Color(hex: "#8E939C"))
                ForEach(oc.team.sorted { $0.value < $1.value }, id: \.key) { m in
                    pill(m.value, on: who.contains(m.key)) { if who.contains(m.key) { who.remove(m.key) } else { who.insert(m.key) } }
                }
                Spacer()
                if ok { Label("Créé", systemImage: "checkmark.circle.fill").font(.system(size: 11, weight: .bold)).foregroundColor(Color(hex: "#4ADE80")) }
                Button("Annuler", action: done).buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundColor(Color(hex: "#8E939C"))
                Button {
                    busy = true
                    Task {
                        let t = titre.trimmingCharacters(in: .whitespaces)
                        ok = await oc.create(type: type, titre: t, start: start, minutes: minutes,
                                             lieu: lieu.trimmingCharacters(in: .whitespaces), notes: "", participants: Array(who))
                        busy = false
                        if ok { DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { done() } }
                    }
                } label: {
                    HStack(spacing: 4) {
                        if busy { ProgressView().controlSize(.mini) } else { Image(systemName: "plus") }
                        Text("Créer le rendez-vous").font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(.white).padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Color(hex: titre.trimmingCharacters(in: .whitespaces).isEmpty ? "#3A3C42" : "#FF5B37")))
                }
                .buttonStyle(.plain)
                .disabled(titre.trimmingCharacters(in: .whitespaces).isEmpty || busy)
            }
        }
        .onAppear { if let me = oc.me, who.isEmpty { who = [me] } }
    }

    private func pill(_ t: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(.system(size: 10.5, weight: .semibold)).lineLimit(1)
                .foregroundColor(on ? .white : Color(hex: "#9398A1"))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(on ? Color(hex: "#FF5B37").opacity(0.85) : Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Ajouter une boîte mail
// Adresse, puis : Gmail / iCloud → Oli ouvre la page du mot de passe d'application et le reprend au
// presse-papiers dès qu'on clique « Copier » ; les autres → le mot de passe de la boîte. Oli vérifie
// la connexion (IMAP) avant de garder quoi que ce soit, dans le Trousseau.

struct AddMailboxForm: View {
    var first = false
    let done: () -> Void

    @State private var address = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String? = nil
    @State private var watching = false
    @State private var startCount = 0
    @State private var deadline = Date.distantPast

    private var appPage: URL? { MailAccounts.appPasswordPage(for: address) }
    private var validAddress: Bool { address.range(of: #"^[^@\s]+@[^@\s]+\.[a-z]{2,}$"#, options: [.regularExpression, .caseInsensitive]) != nil }
    private let tick = Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(first ? "Branche ta boîte mail : Oli te montre ce qui compte et range le reste avec Claude. Rien n’est jamais supprimé."
                       : "Ajoute une boîte : tu passeras de l’une à l’autre en haut de la page.")
                .font(.system(size: 11.5)).foregroundColor(Color(hex: "#C5C8CD")).fixedSize(horizontal: false, vertical: true)
            if !GoogleOAuth.isConfigured {
                HStack(spacing: 8) {
                    Button { NSWorkspace.shared.open(URL(string: "https://console.cloud.google.com/auth/clients/create")!) } label: {
                        Text("Préparer « Se connecter avec Google »").font(.system(size: 11, weight: .bold)).foregroundColor(Color(hex: "#4285F4"))
                            .padding(.horizontal, 12).padding(.vertical, 6).background(Capsule().fill(Color(hex: "#4285F4").opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                    Text("Une fois : crée le client « Application de bureau », télécharge le JSON. Oli le trouve tout seul.")
                        .font(.system(size: 10.5)).foregroundColor(Color(hex: "#8E939C")).fixedSize(horizontal: false, vertical: true)
                }
            }
            if GoogleOAuth.isConfigured {
                HStack(spacing: 10) {
                    Button(action: google) {
                        HStack(spacing: 7) {
                            if busy { ProgressView().controlSize(.mini) }
                            else { Text("G").font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundColor(Color(hex: "#4285F4")) }
                            Text(busy ? "Autorise Oli sur la page Google…" : "Se connecter avec Google")
                                .font(.system(size: 11.5, weight: .bold)).foregroundColor(Color(hex: "#1F1F1F"))
                        }
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Capsule().fill(Color.white))
                    }
                    .buttonStyle(.plain).disabled(busy)
                    Text("Gmail en un clic, sans mot de passe. Pour une autre boîte :")
                        .font(.system(size: 10.5)).foregroundColor(Color(hex: "#8E939C"))
                }
            }
            HStack(spacing: 8) {
                field("ton.adresse@gmail.com", text: $address, secure: false).frame(width: 240)
                if validAddress, let page = appPage {
                    Button {
                        startCount = NSPasteboard.general.changeCount
                        deadline = Date().addingTimeInterval(300)
                        watching = true
                        error = nil
                        NSWorkspace.shared.open(page)
                    } label: {
                        HStack(spacing: 5) {
                            if watching { ProgressView().controlSize(.mini) } else { Image(systemName: "key.fill") }
                            Text(watching ? "Copie le mot de passe sur la page…" : "Créer le mot de passe d’application")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(.white).padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(Color(hex: "#FF5B37")))
                    }
                    .buttonStyle(.plain)
                }
            }
            if validAddress, appPage != nil {
                Text(address.lowercased().contains("gmail") || address.lowercased().contains("googlemail")
                     ? "Sur Google : donne-lui le nom « Oli », clique « Créer », puis copie les 16 lettres. Oli s’occupe du reste. Pas de page ? Active d’abord la validation en deux étapes."
                     : "Sur Apple : Connexion et sécurité → Mots de passe pour app → « + », nomme-le « Oli », puis copie-le. Oli s’occupe du reste.")
                    .font(.system(size: 10.5)).foregroundColor(Color(hex: "#8E939C")).fixedSize(horizontal: false, vertical: true)
                if address.lowercased().contains("gmail") {
                    Link("Activer la validation en deux étapes", destination: URL(string: "https://myaccount.google.com/signinoptions/twosv")!)
                        .font(.system(size: 10.5))
                }
            }
            HStack(spacing: 8) {
                field(appPage == nil ? "Mot de passe de la boîte" : "ou colle le mot de passe d’application ici", text: $password, secure: true)
                    .frame(width: 240)
                    .onSubmit(connect)
                Button(action: connect) {
                    HStack(spacing: 4) {
                        if busy { ProgressView().controlSize(.mini) }
                        Text("Connecter").font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(.white).padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Color(hex: validAddress && !password.isEmpty ? "#3B9EFF" : "#3A3C42")))
                }
                .buttonStyle(.plain).disabled(!validAddress || password.isEmpty || busy)
                if !first { Button("Annuler", action: done).buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundColor(Color(hex: "#8E939C")) }
            }
            if let error {
                Text(error).font(.system(size: 10.5)).foregroundColor(Color(hex: "#FF8D97")).fixedSize(horizontal: false, vertical: true)
            }
        }
        .onReceive(tick) { _ in watchClipboard() }
    }

    private func field(_ placeholder: String, text: Binding<String>, secure: Bool) -> some View {
        Group {
            if secure { SecureField(placeholder, text: text) } else { TextField(placeholder, text: text) }
        }
        .textFieldStyle(.plain).font(.system(size: 12))
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.07)))
    }

    /// Only while waiting, only an app password's exact shape (16 lowercase letters).
    private func watchClipboard() {
        guard watching else { return }
        if Date() > deadline { watching = false; return }
        let pb = NSPasteboard.general
        guard pb.changeCount != startCount else { return }
        startCount = pb.changeCount
        let text = pb.string(forType: .string) ?? ""
        guard MailAccounts.looksLikeAppPassword(text) else { return }
        watching = false
        password = MailAccounts.cleanAppPassword(text)
        connect(clearClipboardAt: pb.changeCount)
    }

    private func connect() { connect(clearClipboardAt: nil) }

    /// « Se connecter avec Google »: the browser, a click on « Autoriser », and the box is there.
    private func google() {
        busy = true
        error = nil
        let hint = validAddress ? address.trimmingCharacters(in: .whitespaces).lowercased() : nil
        Task {
            let problem = await MailAccounts.connectGoogle(hint: hint)
            busy = false
            if let problem { error = problem; return }
            NSApp.activate(ignoringOtherApps: true)
            done()
        }
    }

    private func connect(clearClipboardAt: Int?) {
        guard validAddress, !password.isEmpty, !busy else { return }
        busy = true
        error = nil
        let box = MailBox(address: address.trimmingCharacters(in: .whitespaces).lowercased(),
                          password: MailAccounts.cleanAppPassword(password))
        Task {
            let problem = await MailAccounts.test(box)
            if let n = clearClipboardAt, NSPasteboard.general.changeCount == n { NSPasteboard.general.clearContents() }
            busy = false
            if let problem { error = problem; return }
            MailAccounts.add(box)
            SoundEngine.shared.play("approve")
            appendAppLog("oli.log", "Boîte mail ajoutée : \(box.domain)")
            MailCenter.shared.switchTo(box)
            NotificationCenter.default.post(name: .oliConnectionsChanged, object: nil)
            done()
        }
    }
}
