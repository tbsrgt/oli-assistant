import SwiftUI
import WidgetKit

// MARK: - Widget d'Oli (bureau et Centre de notifications)
// Lit l'instantané écrit par l'app (OliWidgetStore) : aucune requête réseau, aucun secret.
// Petit : Oli + l'état global. Moyen : Oli + sites, prochain projet, prochain rendez-vous.
// Un clic ouvre Oli (oli://) et déplie l'encoche.

@main
struct OliWidgetBundle: WidgetBundle {
    var body: some Widget { OliWidget() }
}

struct OliWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: OliWidgetStore.kind, provider: OliProvider()) { entry in
            OliWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [OliWidgetColors.visorTop, OliWidgetColors.visorBottom],
                                   startPoint: .top, endPoint: .bottom)
                }
                .widgetURL(URL(string: "oli://ouvrir"))
        }
        .configurationDisplayName("Oli")
        .description("L’état du studio en un coup d’œil : sites, projets, agenda.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Timeline

struct OliEntry: TimelineEntry {
    let date: Date
    let snapshot: OliWidgetSnapshot?

    /// L'app n'a rien publié depuis plus d'une heure : elle ne tourne sans doute plus.
    var isStale: Bool {
        guard let s = snapshot else { return true }
        return date.timeIntervalSince(s.generatedAt) > 3600
    }
}

struct OliProvider: TimelineProvider {
    func placeholder(in context: Context) -> OliEntry {
        OliEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (OliEntry) -> Void) {
        let snap = OliWidgetStore.read()
        completion(OliEntry(date: Date(), snapshot: context.isPreview && snap == nil ? .preview : snap))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<OliEntry>) -> Void) {
        let now = Date()
        let snap = OliWidgetStore.read()
        // Une entrée maintenant, puis à chaque fin de rendez-vous (le suivant prend la place),
        // à minuit (les J-n changent) et au passage en « pause » si l'app se tait.
        var dates: Set<Date> = [now]
        let horizon = now.addingTimeInterval(12 * 3600)
        if let snap {
            for e in snap.events where e.end > now && e.end < horizon { dates.insert(e.end) }
            let stale = snap.generatedAt.addingTimeInterval(3601)
            if stale > now && stale < horizon { dates.insert(stale) }
        }
        if let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime),
           midnight < horizon {
            dates.insert(midnight)
        }
        let entries = dates.sorted().map { OliEntry(date: $0, snapshot: snap) }
        // L'app recharge la timeline dès qu'elle publie ; ceci n'est qu'un filet de sécurité.
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
    }
}

// MARK: - Textes

enum OliWidgetText {
    static func globalLine(_ entry: OliEntry) -> (text: String, color: Color) {
        guard let s = entry.snapshot else { return ("Ouvre Oli pour commencer", OliWidgetColors.muted) }
        if entry.isStale { return ("Oli fait une pause", OliWidgetColors.muted) }
        let down = s.sitesDown.count
        if down == 1 { return ("1 site en panne", OliWidgetColors.down) }
        if down > 1 { return ("\(down) sites en panne", OliWidgetColors.down) }
        return ("Tout va bien", OliWidgetColors.cream)
    }

    static func sitesLine(_ s: OliWidgetSnapshot) -> String {
        if s.sites.isEmpty { return "Aucun site surveillé" }
        let down = s.sitesDown
        let online = s.sitesOnline
        if down.isEmpty { return online == 1 ? "1 site en ligne" : "\(online) sites en ligne" }
        if down.count == 1 { return "\(down[0].name) en panne" }
        return "\(down.count) en panne · \(online) en ligne"
    }

    static func projectLine(_ s: OliWidgetSnapshot, now: Date) -> String {
        guard let p = s.nextProject else { return "Aucun projet en cours" }
        guard let due = p.dueDate else { return "\(p.name) · sans date" }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: due)).day ?? 0
        let label: String
        switch days {
        case ..<0: label = "en retard de \(-days) j"
        case 0:    label = "aujourd’hui"
        case 1:    label = "demain"
        default:   label = "J-\(days) · \(dayFormatter.string(from: due))"
        }
        return "\(p.name) · \(label)"
    }

    static func eventLine(_ s: OliWidgetSnapshot, now: Date) -> String {
        guard let e = s.nextEvent(at: now) else { return "Rien à l’agenda" }
        let cal = Calendar.current
        var when: String
        if e.start <= now { when = "en cours" }
        else if cal.isDate(e.start, inSameDayAs: now) { when = e.isAllDay ? "aujourd’hui" : timeFormatter.string(from: e.start) }
        else if cal.isDateInTomorrow(e.start) { when = e.isAllDay ? "demain" : "demain \(timeFormatter.string(from: e.start))" }
        else { when = dayFormatter.string(from: e.start) + (e.isAllDay ? "" : " \(timeFormatter.string(from: e.start))") }
        return "\(e.title) · \(when)"
    }

    /// « il y a 3 h »
    static func ago(_ date: Date, now: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: now)
    }

    // DateFormatter n'est pas Sendable : un formateur neuf à chaque rendu (quelques appels seulement).
    static var dayFormatter: DateFormatter {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "EEE d MMM"; return f
    }
    static var timeFormatter: DateFormatter {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "HH:mm"; return f
    }
}

// MARK: - Vues

struct OliWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: OliEntry

    private var alarm: Bool { !entry.isStale && !(entry.snapshot?.sitesDown.isEmpty ?? true) }

    var body: some View {
        switch family {
        case .systemMedium: mediumBody
        default: smallBody
        }
    }

    var smallBody: some View {
        let line = OliWidgetText.globalLine(entry)
        return VStack(alignment: .leading, spacing: 6) {
            OliStarView(alarm: alarm, asleep: entry.isStale)
                .frame(width: 64, height: 64)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, -8)
            Spacer(minLength: 0)
            Text("Oli")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(OliWidgetColors.cream.opacity(0.6))
            Text(line.text)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(line.color)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
    }

    var mediumBody: some View {
        let line = OliWidgetText.globalLine(entry)
        return HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                OliStarView(alarm: alarm, asleep: entry.isStale)
                    .frame(width: 72, height: 72)
                    .padding(.leading, -8)
                Text(line.text)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(line.color)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 100, alignment: .leading)

            VStack(alignment: .leading, spacing: 9) {
                if let s = entry.snapshot {
                    row("globe", OliWidgetText.sitesLine(s),
                        tint: entry.isStale ? OliWidgetColors.muted : (s.sitesDown.isEmpty ? OliWidgetColors.ok : OliWidgetColors.down))
                    row("folder", OliWidgetText.projectLine(s, now: entry.date), tint: OliWidgetColors.butter)
                    row("calendar", OliWidgetText.eventLine(s, now: entry.date), tint: OliWidgetColors.satellite)
                    if entry.isStale {
                        Text("Dernier relevé \(OliWidgetText.ago(s.generatedAt, now: entry.date))")
                            .font(.system(size: 10))
                            .foregroundStyle(OliWidgetColors.muted)
                    }
                } else {
                    Text("Lance Oli : ses sites, projets et rendez-vous s’afficheront ici.")
                        .font(.system(size: 12))
                        .foregroundStyle(OliWidgetColors.cream.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ symbol: String, _ text: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(OliWidgetColors.cream)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

// MARK: - Aperçu (galerie de widgets)

extension OliWidgetSnapshot {
    static var preview: OliWidgetSnapshot {
        let now = Date()
        return OliWidgetSnapshot(
            generatedAt: now,
            sites: [.init(name: "oculot.studio", status: "ok"), .init(name: "Site client", status: "ok"),
                    .init(name: "Boutique", status: "ok")],
            nextProject: .init(name: "Nouveau site", dueDate: now.addingTimeInterval(4 * 86400), step: "Maquette"),
            events: [.init(title: "Appel client", start: now.addingTimeInterval(3 * 3600),
                           end: now.addingTimeInterval(4 * 3600), isAllDay: false)])
    }
}
