// Textes du briefing du matin et du récap du vendredi (Briefing.swift), sans l'app.
//   scripts/test-briefing.sh
import Foundation

@main
struct TestBriefing {
    static func main() {
        var failures = 0
        func expect(_ cond: Bool, _ msg: String) {
            print((cond ? "  ✓ " : "  ✗ ") + msg)
            if !cond { failures += 1 }
        }
        var f = BriefingFacts()
        f.firstName = "Tobias"
        f.projects = [
            .init(name: "Boulangerie Rose", step: "Maquette", progress: 40, daysLeft: 2, inactiveDays: 1, isDone: false, isNew: false, doneThisWeek: ["Brief et cadrage"]),
            .init(name: "Garage Martin", step: "Développement", progress: 70, daysLeft: -3, inactiveDays: 9, isDone: false, isNew: false, doneThisWeek: []),
            .init(name: "Atelier Bleu", step: "Brief et cadrage", progress: 0, daysLeft: 20, inactiveDays: 0, isDone: false, isNew: true, doneThisWeek: []),
            .init(name: "Fleuriste", step: "Terminé", progress: 100, daysLeft: nil, inactiveDays: 2, isDone: true, isNew: false, doneThisWeek: ["Mise en ligne"]),
        ]
        f.sites = [
            .init(name: "Boulangerie Rose", down: false, reason: nil, issues: ["1 lien cassé"]),
            .init(name: "Garage Martin", down: true, reason: "HTTP 503", issues: []),
        ]
        f.incidentsThisWeek = [.init(name: "Garage Martin", at: Date()), .init(name: "Garage Martin", at: Date())]

        let m = Briefing.morning(f)
        print("— Briefing du matin —\n\(m)\n")
        expect(m.hasPrefix("Bonjour Tobias !"), "salue par le prénom")
        expect(m.contains("**3 projets en cours.**"), "compte les projets en cours (hors terminés)")
        expect(m.contains("Garage Martin** est en retard de 3 j"), "projet en retard en premier")
        expect(m.contains("Boulangerie Rose** : échéance dans 2 j"), "échéance de la semaine")
        expect(!m.contains("Garage Martin : rien de neuf"), "un projet en retard n’est pas aussi signalé comme inactif")
        expect(m.contains("Nouveau projet : **Atelier Bleu**"), "nouveau projet signalé")
        expect(m.contains("Sites en panne : Garage Martin (HTTP 503)"), "site en panne mis en avant")
        expect(m.contains("Boulangerie Rose : 1 lien cassé"), "problème mineur d’un site listé")

        let r = Briefing.fridayRecap(f)
        print("— Récap du vendredi —\n\(r)\n")
        expect(r.contains("**2 étapes bouclées**"), "compte les étapes bouclées dans la semaine")
        expect(r.contains("🎉 **Fleuriste** est terminé"), "projet terminé cette semaine fêté")
        expect(r.contains("Sites : 2 pannes (Garage Martin ×2)"), "pannes de la semaine regroupées par site")

        let ctx = Briefing.chatContext(f)
        expect(ctx.contains("Site Garage Martin : EN PANNE (HTTP 503)") && ctx.contains("Projet Atelier Bleu"), "contexte du chat : projets et sites")

        var withIG = f
        withIG.social = .init(username: "oculot.studio", followers: 1234, lastPostDays: 8, postsThisWeek: 0,
                              reminders: ["2 commentaires sans réponse", "pas de post depuis 8 jours"], error: nil)
        expect(Briefing.morning(withIG).contains("**Instagram : 2 commentaires sans réponse, pas de post depuis 8 jours.**"), "briefing : rappels Instagram")
        expect(Briefing.fridayRecap(withIG).contains("- Instagram : aucun post cette semaine, 1234 abonnés"), "récap : posts Instagram de la semaine")
        expect(Briefing.chatContext(withIG).contains("Instagram @oculot.studio : 1234 abonnés"), "contexte du chat : Instagram")

        var withAgenda = f
        withAgenda.agendaToday = ["10:00 · Rendez-vous Garage Martin (visio)"]
        let ma = Briefing.morning(withAgenda)
        expect(ma.contains("**Aujourd’hui, 1 rendez-vous :**") && ma.contains("- 10:00 · Rendez-vous Garage Martin (visio)"), "briefing : rendez-vous du jour en tête")

        var empty = BriefingFacts(); empty.espaceConfigured = false
        let e = Briefing.morning(empty)
        expect(e.contains("L’espace client n’est pas encore branché") && e.contains("Aucun site surveillé"), "briefing sans données : explique quoi brancher")

        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Paris")!
        func at(_ s: String) -> Date { let f = ISO8601DateFormatter(); return f.date(from: s)! }
        let thuMorning = at("2026-10-08T07:30:00Z")   // jeudi 9 h 30 à Paris
        let friAfternoon = at("2026-10-09T14:00:00Z") // vendredi 16 h à Paris
        let evening = at("2026-10-08T19:00:00Z")      // jeudi 21 h
        expect(Briefing.due(now: thuMorning, lastMorning: nil, lastFriday: nil, calendar: cal) == .morning, "jeudi 9 h 30 : briefing du matin")
        expect(Briefing.due(now: thuMorning, lastMorning: "2026-10-08", lastFriday: nil, calendar: cal) == nil, "une seule fois par matin")
        expect(Briefing.due(now: evening, lastMorning: nil, lastFriday: nil, calendar: cal) == nil, "le soir : rien")
        expect(Briefing.due(now: friAfternoon, lastMorning: nil, lastFriday: nil, calendar: cal) == .friday, "vendredi 16 h : récap")
        expect(Briefing.due(now: friAfternoon, lastMorning: nil, lastFriday: "2026-10-09", calendar: cal) == nil, "récap une seule fois")

        print(failures == 0 ? "\nOK" : "\n\(failures) échec(s)")
        exit(failures == 0 ? 0 : 1)
    }
}
