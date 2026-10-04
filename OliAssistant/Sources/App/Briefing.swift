import Foundation

// MARK: - Briefing du matin, récap du vendredi, état d'Oculot pour le chat (phase 6)
// Written locally from what Oli already knows (espace client + sites), no AI call, so it works
// without any API key. Shown once in the chat view on the first hover of the morning, and on the
// first hover of Friday afternoon.

/// Plain facts the texts are built from (kept separate from AppState so the wording is testable).
struct BriefingFacts {
    struct Project {
        let name: String
        let step: String
        let progress: Int
        let daysLeft: Int?
        let inactiveDays: Int
        let isDone: Bool
        let isNew: Bool              // created in the last 7 days
        let doneThisWeek: [String]   // step labels completed in the last 7 days
    }
    struct Site {
        let name: String
        let down: Bool
        let reason: String?
        let issues: [String]
    }
    struct Incident { let name: String; let at: Date }
    struct Social {
        let username: String
        let followers: Int?
        let lastPostDays: Int?
        let postsThisWeek: Int
        let reminders: [String]
        let error: String?
    }

    var firstName: String?
    var projects: [Project] = []
    var sites: [Site] = []
    var incidentsThisWeek: [Incident] = []
    var espaceConfigured = true
    /// Sites in the watch list not checked yet (first pass still running).
    var sitesPending = 0
    /// Instagram, nil when no token is set.
    var social: Social? = nil
    /// Today's appointments ("10:00 · Rendez-vous Garage Martin"), nil when no calendar is linked.
    var agendaToday: [String]? = nil
}

enum Briefing {
    // MARK: Texts

    static func morning(_ f: BriefingFacts, now: Date = Date()) -> String {
        let hello = f.firstName.map { "Bonjour \($0) !" } ?? "Bonjour !"
        var lines: [String] = []

        if let today = f.agendaToday {
            if today.isEmpty { lines.append("Agenda : rien de prévu aujourd’hui.") }
            else {
                lines.append("**Aujourd’hui, \(today.count) rendez-vous :**")
                for e in today.prefix(5) { lines.append("- \(e)") }
            }
            lines.append("")
        }

        let active = f.projects.filter { !$0.isDone }
        if !f.espaceConfigured {
            lines.append("L’espace client n’est pas encore branché : ajoute le jeton d’équipe dans Réglages → Integrations.")
        } else if active.isEmpty {
            lines.append("Aucun projet en cours dans l’espace client.")
        } else {
            let late = active.filter { ($0.daysLeft ?? 1) < 0 }
            let soon = active.filter { if let d = $0.daysLeft { return d >= 0 && d <= 7 } else { return false } }
                .sorted { ($0.daysLeft ?? 0) < ($1.daysLeft ?? 0) }
            lines.append("**\(active.count) projet\(active.count > 1 ? "s" : "") en cours.**")
            for p in late { lines.append("- 🔴 **\(p.name)** est en retard de \(-(p.daysLeft ?? 0)) j (\(p.step)).") }
            for p in soon {
                let when = p.daysLeft == 0 ? "aujourd’hui" : p.daysLeft == 1 ? "demain" : "dans \(p.daysLeft!) j"
                lines.append("- **\(p.name)** : échéance \(when), on en est à « \(p.step) » (\(p.progress) %).")
            }
            for p in active where p.inactiveDays >= 7 && !late.contains(where: { $0.name == p.name }) {
                lines.append("- \(p.name) : rien de neuf depuis \(p.inactiveDays) j, un petit mot au client ?")
            }
            for p in active where p.isNew { lines.append("- Nouveau projet : **\(p.name)**.") }
            if late.isEmpty && soon.isEmpty && !active.contains(where: { $0.inactiveDays >= 7 || $0.isNew }) {
                lines.append("- Rien d’urgent cette semaine.")
            }
        }

        lines.append("")
        lines.append(sitesLine(f.sites, pending: f.sitesPending))
        let warned = f.sites.filter { !$0.down && !$0.issues.isEmpty }
        for s in warned.prefix(3) { lines.append("- \(s.name) : \(s.issues.prefix(2).joined(separator: ", ")).") }

        if let s = f.social {
            lines.append("")
            if let e = s.error { lines.append("Instagram : \(e).") }
            else if s.reminders.isEmpty { lines.append("Instagram : rien à traiter\(s.followers.map { ", \($0) abonnés" } ?? "").") }
            else { lines.append("**Instagram : \(s.reminders.joined(separator: ", ")).**") }
        }

        lines.append("")
        lines.append("Bonne journée ✨")
        return hello + "\n\n" + lines.joined(separator: "\n")
    }

    static func fridayRecap(_ f: BriefingFacts, now: Date = Date()) -> String {
        let hello = f.firstName.map { "Bon vendredi \($0) !" } ?? "Bon vendredi !"
        var lines = ["Le récap de la semaine :", ""]

        let advanced = f.projects.filter { !$0.doneThisWeek.isEmpty }
        let steps = advanced.reduce(0) { $0 + $1.doneThisWeek.count }
        if steps == 0 {
            lines.append("- Aucune étape bouclée dans l’espace client cette semaine.")
        } else {
            lines.append("- **\(steps) étape\(steps > 1 ? "s" : "") bouclée\(steps > 1 ? "s" : "")** :")
            for p in advanced { lines.append("  - \(p.name) : \(p.doneThisWeek.joined(separator: ", "))") }
        }
        let delivered = f.projects.filter { $0.isDone && !$0.doneThisWeek.isEmpty }
        for p in delivered { lines.append("- 🎉 **\(p.name)** est terminé.") }
        let fresh = f.projects.filter(\.isNew)
        if !fresh.isEmpty { lines.append("- Nouveau\(fresh.count > 1 ? "x" : "") client\(fresh.count > 1 ? "s" : "") : \(fresh.map(\.name).joined(separator: ", ")).") }
        let nextWeek = f.projects.filter { !$0.isDone && ($0.daysLeft.map { $0 >= 0 && $0 <= 10 } ?? false) }
        if !nextWeek.isEmpty {
            lines.append("- La semaine prochaine : " + nextWeek.map { "\($0.name) (\($0.daysLeft == 0 ? "aujourd’hui" : "J-\($0.daysLeft!)"))" }.joined(separator: ", ") + ".")
        }

        if let s = f.social, s.error == nil {
            let posts = s.postsThisWeek == 0 ? "aucun post" : s.postsThisWeek == 1 ? "1 post" : "\(s.postsThisWeek) posts"
            lines.append("- Instagram : \(posts) cette semaine\(s.followers.map { ", \($0) abonnés" } ?? "")\(s.reminders.isEmpty ? "" : " (\(s.reminders.joined(separator: ", ")))").")
        }
        if f.incidentsThisWeek.isEmpty {
            lines.append("- Sites : aucune panne cette semaine.")
        } else {
            let names = Dictionary(grouping: f.incidentsThisWeek, by: \.name).map { "\($0.key) ×\($0.value.count)" }.sorted()
            lines.append("- Sites : \(f.incidentsThisWeek.count) panne\(f.incidentsThisWeek.count > 1 ? "s" : "") (\(names.joined(separator: ", "))).")
        }
        lines.append("")
        lines.append("Bon week-end 🌞")
        return hello + "\n\n" + lines.joined(separator: "\n")
    }

    /// Compact live context for the chat (any provider): what Oli knows right now.
    static func chatContext(_ f: BriefingFacts, now: Date = Date()) -> String {
        var out = ["État d’Oculot au \(now.formatted(date: .abbreviated, time: .shortened)) (données live d’Oli) :"]
        if !f.espaceConfigured {
            out.append("- Espace client non branché.")
        } else if f.projects.isEmpty {
            out.append("- Aucun projet dans l’espace client.")
        } else {
            for p in f.projects {
                let due = p.daysLeft.map { $0 < 0 ? "en retard de \(-$0) j" : "échéance J-\($0)" } ?? "sans échéance"
                out.append("- Projet \(p.name) : \(p.isDone ? "terminé" : "étape « \(p.step) », \(p.progress) %, \(due)"), dernière activité il y a \(p.inactiveDays) j.")
            }
        }
        if f.sites.isEmpty {
            out.append("- Aucun site surveillé.")
        } else {
            for s in f.sites {
                let state = s.down ? "EN PANNE (\(s.reason ?? "injoignable"))" : s.issues.isEmpty ? "en ligne" : "en ligne, à surveiller : \(s.issues.joined(separator: ", "))"
                out.append("- Site \(s.name) : \(state).")
            }
        }
        if let s = f.social {
            if let e = s.error { out.append("- Instagram : \(e).") }
            else {
                out.append("- Instagram @\(s.username) : \(s.followers.map { "\($0) abonnés" } ?? "abonnés ?"), dernier post \(s.lastPostDays.map { "il y a \($0) j" } ?? "inconnu"), \(s.postsThisWeek) post(s) cette semaine\(s.reminders.isEmpty ? "" : ", à traiter : \(s.reminders.joined(separator: ", "))").")
            }
        }
        return out.joined(separator: "\n")
    }

    static func sitesLine(_ sites: [BriefingFacts.Site], pending: Int = 0) -> String {
        if sites.isEmpty {
            return pending > 0 ? "Sites : première vérification en cours (\(pending) site\(pending > 1 ? "s" : ""))." : "Aucun site surveillé pour l’instant."
        }
        let down = sites.filter(\.down)
        if down.isEmpty { return "**Sites : les \(sites.count) sont en ligne.**" }
        return "**🔴 Sites en panne : " + down.map { "\($0.name) (\($0.reason ?? "injoignable"))" }.joined(separator: ", ") + ".**"
    }

    // MARK: When to show

    enum Kind: String { case morning, friday }

    /// Which text is due on this hover, if any. Morning: first hover between 5 h and 13 h.
    /// Friday: first hover on Friday from 15 h. Each at most once per day.
    static func due(now: Date, lastMorning: String?, lastFriday: String?, calendar: Calendar = .current) -> Kind? {
        let day = dayKey(now, calendar: calendar)
        let hour = calendar.component(.hour, from: now)
        let weekday = calendar.component(.weekday, from: now)   // 6 = vendredi (calendrier grégorien)
        if weekday == 6 && hour >= 15 && lastFriday != day { return .friday }
        if hour >= 5 && hour < 13 && lastMorning != day { return .morning }
        return nil
    }

    static func dayKey(_ d: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
