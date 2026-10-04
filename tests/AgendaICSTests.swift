import Foundation

// Tests du parseur iCal de l'agenda Oculot. Lancer : scripts/test-ics.sh

@main
enum AgendaICSTests {

    nonisolated(unsafe) static var failures = 0

    static func check(_ label: String, _ ok: Bool, _ detail: String = "") {
        if ok { print("  ✓ \(label)") }
        else  { print("  ✗ \(label)  \(detail)"); failures += 1 }
    }

    static func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    static let sample = """
    BEGIN:VCALENDAR\r
    VERSION:2.0\r
    PRODID:-//Google Inc//Google Calendar 70.9054//EN\r
    X-WR-TIMEZONE:Europe/Paris\r
    BEGIN:VTIMEZONE\r
    TZID:Europe/Paris\r
    BEGIN:STANDARD\r
    DTSTART:19701025T030000\r
    TZOFFSETFROM:+0200\r
    TZOFFSETTO:+0100\r
    END:STANDARD\r
    END:VTIMEZONE\r
    BEGIN:VEVENT\r
    UID:utc-1@google.com\r
    DTSTART:20261006T130000Z\r
    DTEND:20261006T140000Z\r
    SUMMARY:Point client Concept Rénovation\\, bilan\r
    LOCATION:12 rue de la République\\, 13001 Marseille\r
    DESCRIPTION:Ordre du jour\\nRejoindre : https://meet.google.com/abc-defg-hij\\n\r
     Suite du texte replié sur la ligne suivante.\r
    BEGIN:VALARM\r
    TRIGGER:-PT10M\r
    DESCRIPTION:Ceci ne doit pas remplacer la description\r
    ACTION:DISPLAY\r
    END:VALARM\r
    END:VEVENT\r
    BEGIN:VEVENT\r
    UID:tzid-1@google.com\r
    DTSTART;TZID=Europe/Paris:20261007T093000\r
    DTEND;TZID=Europe/Paris:20261007T101500\r
    SUMMARY:Appel prospect\r
    LOCATION:https://zoom.us/j/123456789?pwd=xyz\r
    END:VEVENT\r
    BEGIN:VEVENT\r
    UID:allday-1@google.com\r
    DTSTART;VALUE=DATE:20261008\r
    DTEND;VALUE=DATE:20261009\r
    SUMMARY:Salon des artisans\r
    END:VEVENT\r
    BEGIN:VEVENT\r
    UID:weekly-1@google.com\r
    DTSTART;TZID=Europe/Paris:20260914T100000\r
    DTEND;TZID=Europe/Paris:20260914T101500\r
    RRULE:FREQ=WEEKLY;BYDAY=MO,WE\r
    EXDATE;TZID=Europe/Paris:20261007T100000\r
    SUMMARY:Stand-up\r
    END:VEVENT\r
    BEGIN:VEVENT\r
    UID:weekly-1@google.com\r
    RECURRENCE-ID;TZID=Europe/Paris:20261014T100000\r
    DTSTART;TZID=Europe/Paris:20261014T110000\r
    DTEND;TZID=Europe/Paris:20261014T111500\r
    SUMMARY:Stand-up (décalé)\r
    END:VEVENT\r
    BEGIN:VEVENT\r
    UID:daily-1@google.com\r
    DTSTART:20261005T160000Z\r
    DURATION:PT30M\r
    RRULE:FREQ=DAILY;INTERVAL=2;COUNT=3\r
    SUMMARY:Relance devis\r
    END:VEVENT\r
    BEGIN:VEVENT\r
    UID:until-1@google.com\r
    DTSTART:20261006T150000Z\r
    DTEND:20261006T153000Z\r
    RRULE:FREQ=DAILY;UNTIL=20261007T235959Z\r
    SUMMARY:Veille\r
    END:VEVENT\r
    BEGIN:VEVENT\r
    UID:monthly-1@google.com\r
    DTSTART:20261010T090000Z\r
    DTEND:20261010T100000Z\r
    RRULE:FREQ=MONTHLY;BYMONTHDAY=10\r
    SUMMARY:Facturation\r
    END:VEVENT\r
    BEGIN:VEVENT\r
    UID:cancelled-1@google.com\r
    DTSTART:20261006T090000Z\r
    DTEND:20261006T100000Z\r
    STATUS:CANCELLED\r
    SUMMARY:Annulé\r
    END:VEVENT\r
    BEGIN:VEVENT\r
    UID:past-1@google.com\r
    DTSTART:20260901T090000Z\r
    DTEND:20260901T100000Z\r
    SUMMARY:Vieux rendez-vous\r
    END:VEVENT\r
    BEGIN:VEVENT\r
    UID:far-1@google.com\r
    DTSTART:20261201T090000Z\r
    DTEND:20261201T100000Z\r
    SUMMARY:Trop loin\r
    END:VEVENT\r
    BEGIN:VEVENT\r
    UID:teams-1@google.com\r
    DTSTART:20261009T140000Z\r
    DTEND:20261009T143000Z\r
    SUMMARY:Démo Teams\r
    DESCRIPTION:Lien : https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc. À bientôt.\r
    END:VEVENT\r
    END:VCALENDAR\r

    """

    static func main() {
        // now = lundi 5 oct. 2026, 08:30 UTC (10:30 à Paris) ; fenêtre : −1 h → +14 j
        let now = utc(2026, 10, 5, 8, 30)
        let events = AgendaICS.parse(sample, now: now)
        let byUID: (String) -> [AgendaEvent] = { uid in events.filter { $0.uid == uid } }

        print("Dépliage et échappements")
        let pt = byUID("utc-1@google.com")
        check("un seul événement UTC", pt.count == 1, "\(pt.count)")
        if let e = pt.first {
            check("DTSTART UTC", e.start == utc(2026, 10, 6, 13, 0), "\(e.start)")
            check("durée 1 h", e.end.timeIntervalSince(e.start) == 3600)
            check("virgule déséchappée dans le titre", e.title == "Point client Concept Rénovation, bilan", e.title)
            check("ligne repliée recollée", e.description.contains("Suite du texte replié"), e.description)
            check("\\n déséchappé", e.description.contains("Ordre du jour\nRejoindre"))
            check("DESCRIPTION du VALARM ignorée", !e.description.contains("ne doit pas"))
            check("lien Meet détecté", e.meetingURL?.absoluteString == "https://meet.google.com/abc-defg-hij", "\(String(describing: e.meetingURL))")
            check("lieu court = première partie", e.shortLocation == "12 rue de la République", e.shortLocation)
            check("pas journée entière", !e.isAllDay)
        }

        print("TZID Europe/Paris")
        let ap = byUID("tzid-1@google.com")
        check("un événement TZID", ap.count == 1)
        if let e = ap.first {
            check("09:30 Paris = 07:30 UTC (heure d'été)", e.start == utc(2026, 10, 7, 7, 30), "\(e.start)")
            check("durée 45 min", e.end.timeIntervalSince(e.start) == 45 * 60)
            check("lien Zoom dans LOCATION", e.meetingURL?.host == "zoom.us")
            check("lieu court Visio", e.shortLocation == "Visio", e.shortLocation)
        }

        print("Journée entière")
        let ad = byUID("allday-1@google.com")
        check("un événement journée", ad.count == 1)
        if let e = ad.first {
            let expected = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 8))!
            check("isAllDay", e.isAllDay)
            check("début à minuit local", e.start == expected, "\(e.start)")
            check("durée 1 jour", e.end.timeIntervalSince(e.start) == 86400)
            check("timeLabel Journée", e.timeLabel == "Journée")
        }

        print("RRULE hebdo + EXDATE + RECURRENCE-ID")
        let su = byUID("weekly-1@google.com").sorted { $0.start < $1.start }
        check("4 occurrences dans 14 j (5, 12, 14 décalé, 19 oct.)", su.count == 4, "\(su.map { $0.start })")
        check("lundi 5 oct. 10:00 Paris", su.contains { $0.start == utc(2026, 10, 5, 8, 0) })
        check("mercredi 7 oct. exclu (EXDATE)", !su.contains { $0.start == utc(2026, 10, 7, 8, 0) })
        check("lundi 12 oct.", su.contains { $0.start == utc(2026, 10, 12, 8, 0) })
        check("mercredi 14 oct. 10:00 remplacé", !su.contains { $0.start == utc(2026, 10, 14, 8, 0) })
        check("mercredi 14 oct. 11:00 (RECURRENCE-ID)", su.contains { $0.start == utc(2026, 10, 14, 9, 0) && $0.title == "Stand-up (décalé)" })
        check("lundi 19 oct.", su.contains { $0.start == utc(2026, 10, 19, 8, 0) })
        check("ids uniques", Set(su.map(\.id)).count == su.count)

        print("RRULE quotidien INTERVAL/COUNT, DURATION")
        let rd = byUID("daily-1@google.com").sorted { $0.start < $1.start }
        check("3 occurrences (5, 7, 9 oct.)", rd.map(\.start) == [utc(2026, 10, 5, 16), utc(2026, 10, 7, 16), utc(2026, 10, 9, 16)], "\(rd.map(\.start))")
        check("DURATION PT30M", rd.first.map { $0.end.timeIntervalSince($0.start) == 1800 } ?? false)

        print("RRULE UNTIL")
        let un = byUID("until-1@google.com").sorted { $0.start < $1.start }
        check("2 occurrences (6, 7 oct.)", un.map(\.start) == [utc(2026, 10, 6, 15), utc(2026, 10, 7, 15)], "\(un.map(\.start))")

        print("Cas ignorés proprement")
        check("MONTHLY → occurrence de base seule", byUID("monthly-1@google.com").count == 1)
        check("STATUS:CANCELLED exclu", byUID("cancelled-1@google.com").isEmpty)
        check("événement passé exclu", byUID("past-1@google.com").isEmpty)
        check("événement > 14 j exclu", byUID("far-1@google.com").isEmpty)
        check("lien Teams, point final retiré", byUID("teams-1@google.com").first?.meetingURL?.absoluteString == "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc")

        print("Tri")
        check("trié par début", zip(events, events.dropFirst()).allSatisfy { $0.start <= $1.start })
        check("premier = Stand-up du 5 oct.", events.first?.uid == "weekly-1@google.com", events.first?.title ?? "nil")

        print("Utilitaires")
        check("unescape", AgendaICS.unescape(#"a\,b\;c\\d\nE"#) == "a,b;c\\d\nE")
        check("parseDuration P1DT2H30M", AgendaICS.parseDuration("P1DT2H30M") == 86400 + 2 * 3600 + 30 * 60)
        let p = AgendaICS.parseProperty(#"DTSTART;TZID="Europe/Paris";VALUE=DATE-TIME:20261007T093000"#)
        check("paramètre entre guillemets avec ':'", p?.params["TZID"] == "Europe/Paris" && p?.value == "20261007T093000")
        check("ligne sans ':' ignorée", AgendaICS.parseProperty("garbage") == nil)
        check("fuseau Windows → IANA", AgendaICS.windowsTimeZone("Romance Standard Time")?.identifier == "Europe/Paris")
        check("pas de lien hors visio", AgendaICS.meetingLink(in: ["voir https://oculot.studio"]) == nil)

        print(failures == 0 ? "\nTout passe." : "\n\(failures) échec(s).")
        exit(failures == 0 ? 0 : 1)
    }
}
