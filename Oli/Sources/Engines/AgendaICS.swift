import Foundation

// MARK: - Agenda Oculot : parseur iCalendar (Foundation seul, sans AppKit)
// Lit le flux .ics secret d'un agenda Google : VEVENT, dates UTC / TZID / journée entière,
// dépliage des lignes, échappements, RRULE DAILY/WEEKLY minimal, EXDATE, RECURRENCE-ID.
// Compilable seul avec `swiftc` pour les tests (scripts/test-ics.sh).

struct AgendaEvent: Identifiable, Hashable, Sendable {
    let id: String              // uid + horodatage de début (unique par occurrence)
    let uid: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let location: String
    let description: String
    let url: String?
    let meetingURL: URL?

    var isToday: Bool { Calendar.current.isDateInToday(start) }
    var isTomorrow: Bool { Calendar.current.isDateInTomorrow(start) }

    /// « 14:30 » ou « Journée » pour les événements sur la journée entière.
    var timeLabel: String {
        if isAllDay { return "Journée" }
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "HH:mm"
        return f.string(from: start)
    }

    /// « lun. 6 oct. » (vide si c'est aujourd'hui : l'en-tête le dit déjà).
    var dayLabel: String {
        if isToday { return "" }
        if isTomorrow { return "demain" }
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "EEE d MMM"
        return f.string(from: start)
    }

    /// « lundi 6 octobre · 14:30 – 15:30 » ou « lundi 6 octobre · journée entière ».
    var fullDateLabel: String {
        let day = DateFormatter(); day.locale = Locale(identifier: "fr_FR"); day.dateFormat = "EEEE d MMMM"
        let d = day.string(from: start)
        if isAllDay { return "\(d) · journée entière" }
        let t = DateFormatter(); t.locale = Locale(identifier: "fr_FR"); t.dateFormat = "HH:mm"
        let s = t.string(from: start)
        guard end > start else { return "\(d) · \(s)" }
        let dayEnd = day.string(from: end)
        let e = t.string(from: end)
        return dayEnd == d ? "\(d) · \(s) – \(e)" : "\(d) · \(s) → \(dayEnd) \(e)"
    }

    /// Premier segment du lieu (avant la virgule), ou vide si c'est juste un lien de visio.
    var shortLocation: String {
        let loc = location.trimmingCharacters(in: .whitespacesAndNewlines)
        if loc.isEmpty { return meetingURL == nil ? "" : "Visio" }
        if loc.hasPrefix("http") { return meetingURL == nil ? "Lien" : "Visio" }
        let first = loc.split(separator: ",", maxSplits: 1).first.map(String.init) ?? loc
        return first.trimmingCharacters(in: .whitespaces)
    }

    /// Minutes avant le début (négatif si déjà commencé).
    func minutesUntilStart(from now: Date = Date()) -> Int {
        Int((start.timeIntervalSince(now) / 60).rounded(.down))
    }
}

enum AgendaICS {

    // MARK: - Entrée

    /// Parse le flux et renvoie les occurrences entre `now − 1 h` et `now + 14 j`, triées.
    static func parse(_ text: String, now: Date = Date()) -> [AgendaEvent] {
        let windowStart = now.addingTimeInterval(-3600)
        let windowEnd = now.addingTimeInterval(14 * 86400)
        let blocks = eventBlocks(unfold(text))

        // Occurrences modifiées (RECURRENCE-ID) : on retire l'occurrence générée correspondante.
        var overridden: Set<String> = []
        for b in blocks {
            if let uid = b.value("UID"), let rid = b.first("RECURRENCE-ID"), let d = parseDate(rid)?.date {
                overridden.insert("\(uid)@\(Int(d.timeIntervalSince1970))")
            }
        }

        var out: [AgendaEvent] = []
        for b in blocks {
            guard b.value("STATUS")?.uppercased() != "CANCELLED" else { continue }
            guard let dtstart = b.first("DTSTART"), let start = parseDate(dtstart) else { continue }
            let uid = b.value("UID") ?? UUID().uuidString
            let title = b.value("SUMMARY").map(unescape) ?? "(sans titre)"
            let location = b.value("LOCATION").map(unescape) ?? ""
            let description = b.value("DESCRIPTION").map(unescape) ?? ""
            let url = b.value("URL").map(unescape)
            let meeting = meetingLink(in: [location, description, url ?? ""])

            // Durée : DTEND, sinon DURATION, sinon 1 jour (journée entière) ou 0.
            let duration: TimeInterval
            if let dtend = b.first("DTEND"), let end = parseDate(dtend) {
                duration = max(0, end.date.timeIntervalSince(start.date))
            } else if let dur = b.value("DURATION"), let d = parseDuration(dur) {
                duration = d
            } else {
                duration = start.isAllDay ? 86400 : 0
            }

            let exdates = b.all("EXDATE").flatMap { parseDateList($0) }
            let isOverride = b.first("RECURRENCE-ID") != nil
            let starts: [Date]
            if let rrule = b.value("RRULE"), !isOverride {
                starts = expand(rrule: rrule, start: start, until: windowEnd)
            } else {
                starts = [start.date]
            }

            for s in starts {
                if exdates.contains(where: { abs($0.timeIntervalSince(s)) < 1 }) { continue }
                if start.isAllDay, exdates.contains(where: { start.calendar.isDate($0, inSameDayAs: s) }) { continue }
                let id = "\(uid)@\(Int(s.timeIntervalSince1970))"
                if !isOverride && overridden.contains(id) { continue }
                guard s >= windowStart, s <= windowEnd else { continue }
                out.append(AgendaEvent(id: id, uid: uid, title: title, start: s, end: s.addingTimeInterval(duration),
                                       isAllDay: start.isAllDay, location: location, description: description,
                                       url: url, meetingURL: meeting))
            }
        }
        return out.sorted { a, b in
            if a.start != b.start { return a.start < b.start }
            if a.isAllDay != b.isAllDay { return !a.isAllDay }   // journée entière après les horaires
            return a.title < b.title
        }
    }

    // MARK: - Lignes et propriétés

    struct Property {
        let name: String
        let params: [String: String]
        let value: String
    }

    struct Block {
        var props: [Property] = []
        func first(_ name: String) -> Property? { props.first { $0.name == name } }
        func all(_ name: String) -> [Property] { props.filter { $0.name == name } }
        func value(_ name: String) -> String? { first(name)?.value }
    }

    /// Dépliage RFC 5545 : une ligne commençant par un espace ou une tabulation continue la précédente.
    static func unfold(_ text: String) -> [String] {
        var lines: [String] = []
        for raw in text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" }) {
            var line = String(raw)
            if line.hasSuffix("\r") { line.removeLast() }
            if let f = line.first, f == " " || f == "\t", !lines.isEmpty {
                lines[lines.count - 1] += String(line.dropFirst())
            } else {
                lines.append(line)
            }
        }
        return lines
    }

    /// Isole chaque VEVENT (en ignorant VALARM imbriqué, VTIMEZONE, etc.).
    static func eventBlocks(_ lines: [String]) -> [Block] {
        var blocks: [Block] = []
        var current: Block? = nil
        var depth = 0           // profondeur à l'intérieur d'un VEVENT (VALARM = 1)
        for line in lines {
            if line.hasPrefix("BEGIN:") {
                let kind = line.dropFirst(6).uppercased()
                if current != nil { depth += 1 }
                else if kind == "VEVENT" { current = Block(); depth = 0 }
                continue
            }
            if line.hasPrefix("END:") {
                let kind = line.dropFirst(4).uppercased()
                if current != nil {
                    if depth > 0 { depth -= 1 }
                    else if kind == "VEVENT" { blocks.append(current!); current = nil }
                }
                continue
            }
            guard current != nil, depth == 0, let p = parseProperty(line) else { continue }
            current!.props.append(p)
        }
        return blocks
    }

    /// `NAME;PARAM=VAL;PARAM2="a:b":valeur` → Property. Le ':' séparateur est le premier hors guillemets.
    static func parseProperty(_ line: String) -> Property? {
        var inQuotes = false
        var splitIndex: String.Index? = nil
        for i in line.indices {
            let c = line[i]
            if c == "\"" { inQuotes.toggle() }
            else if c == ":" && !inQuotes { splitIndex = i; break }
        }
        guard let idx = splitIndex else { return nil }
        let head = String(line[..<idx])
        let value = String(line[line.index(after: idx)...])
        let parts = head.split(separator: ";", omittingEmptySubsequences: true).map(String.init)
        guard let name = parts.first, !name.isEmpty else { return nil }
        var params: [String: String] = [:]
        for p in parts.dropFirst() {
            guard let eq = p.firstIndex(of: "=") else { continue }
            let k = String(p[..<eq]).uppercased()
            var v = String(p[p.index(after: eq)...])
            if v.hasPrefix("\""), v.hasSuffix("\""), v.count >= 2 { v = String(v.dropFirst().dropLast()) }
            params[k] = v
        }
        return Property(name: name.uppercased(), params: params, value: value)
    }

    /// Retire les échappements de texte : \n \N \, \; \\
    static func unescape(_ s: String) -> String {
        var out = ""
        var it = s.makeIterator()
        while let c = it.next() {
            guard c == "\\" else { out.append(c); continue }
            guard let n = it.next() else { out.append(c); break }
            switch n {
            case "n", "N": out.append("\n")
            case ",": out.append(",")
            case ";": out.append(";")
            case "\\": out.append("\\")
            default: out.append("\\"); out.append(n)
            }
        }
        return out
    }

    // MARK: - Dates

    struct ParsedDate {
        let date: Date
        let isAllDay: Bool
        let calendar: Calendar     // calendrier dans le fuseau de l'événement (pour RRULE/EXDATE)
    }

    static func parseDate(_ p: Property) -> ParsedDate? {
        parseDate(p.value, params: p.params)
    }

    static func parseDate(_ raw: String, params: [String: String]) -> ParsedDate? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        let digits = s.filter(\.isNumber)
        let isDateOnly = params["VALUE"]?.uppercased() == "DATE" || (s.count == 8 && digits.count == 8)
        guard digits.count >= 8,
              let y = Int(digits.prefix(4)),
              let mo = Int(digits.dropFirst(4).prefix(2)),
              let d = Int(digits.dropFirst(6).prefix(2)) else { return nil }

        var cal = Calendar(identifier: .gregorian)
        if isDateOnly {
            cal.timeZone = TimeZone.current
            guard let date = cal.date(from: DateComponents(year: y, month: mo, day: d)) else { return nil }
            return ParsedDate(date: date, isAllDay: true, calendar: cal)
        }
        guard digits.count >= 14 else { return nil }
        let h = Int(digits.dropFirst(8).prefix(2)) ?? 0
        let mi = Int(digits.dropFirst(10).prefix(2)) ?? 0
        let se = Int(digits.dropFirst(12).prefix(2)) ?? 0
        if s.hasSuffix("Z") {
            cal.timeZone = TimeZone(identifier: "UTC")!
        } else if let tzid = params["TZID"], let tz = TimeZone(identifier: tzid) ?? windowsTimeZone(tzid) {
            cal.timeZone = tz
        } else {
            cal.timeZone = TimeZone.current      // heure flottante → locale
        }
        guard let date = cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: se)) else { return nil }
        return ParsedDate(date: date, isAllDay: false, calendar: cal)
    }

    /// Quelques noms de fuseaux non-IANA rencontrés dans les exports (Outlook).
    static func windowsTimeZone(_ name: String) -> TimeZone? {
        let map = [
            "Romance Standard Time": "Europe/Paris",
            "W. Europe Standard Time": "Europe/Berlin",
            "Central European Standard Time": "Europe/Warsaw",
            "GMT Standard Time": "Europe/London",
        ]
        return map[name].flatMap { TimeZone(identifier: $0) }
    }

    /// EXDATE peut porter plusieurs dates séparées par des virgules.
    static func parseDateList(_ p: Property) -> [Date] {
        p.value.split(separator: ",").compactMap { parseDate(String($0), params: p.params)?.date }
    }

    /// DURATION `P1DT2H30M` → secondes.
    static func parseDuration(_ s: String) -> TimeInterval? {
        var total: TimeInterval = 0
        var num = ""
        var inTime = false
        var sign: TimeInterval = 1
        for c in s.uppercased() {
            switch c {
            case "-": sign = -1
            case "+", "P": continue
            case "T": inTime = true
            case "0"..."9": num.append(c)
            case "W": total += (Double(num) ?? 0) * 7 * 86400; num = ""
            case "D": total += (Double(num) ?? 0) * 86400; num = ""
            case "H": total += (Double(num) ?? 0) * 3600; num = ""
            case "M": total += (Double(num) ?? 0) * (inTime ? 60 : 0); num = ""
            case "S": total += (Double(num) ?? 0); num = ""
            default: return nil
            }
        }
        return total * sign
    }

    // MARK: - RRULE (DAILY / WEEKLY seulement)

    static let weekdayCodes = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]   // index = Calendar.weekday − 1

    /// Développe la règle depuis `start` jusqu'à `until` (fenêtre). Autres FREQ : première occurrence seule.
    static func expand(rrule: String, start: ParsedDate, until windowEnd: Date) -> [Date] {
        var rule: [String: String] = [:]
        for part in rrule.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            rule[String(kv[0]).uppercased()] = String(kv[1]).uppercased()
        }
        let freq = rule["FREQ"] ?? ""
        guard freq == "DAILY" || freq == "WEEKLY" else { return [start.date] }

        let interval = max(1, Int(rule["INTERVAL"] ?? "") ?? 1)
        let count = Int(rule["COUNT"] ?? "")
        var untilDate: Date? = nil
        if let u = rule["UNTIL"] {
            // UNTIL en UTC (…Z) ou DATE : on prend la fin de journée pour une DATE.
            if let p = parseDate(u, params: u.count == 8 ? ["VALUE": "DATE"] : [:]) {
                untilDate = p.isAllDay ? p.date.addingTimeInterval(86399) : p.date
            }
        }
        let cal = start.calendar
        let startWeekdayIdx = cal.component(.weekday, from: start.date) - 1            // 0 = dimanche
        let mondayBased = (startWeekdayIdx + 6) % 7                                    // 0 = lundi
        var byDay: Set<Int> = []
        if freq == "WEEKLY" {
            if let bd = rule["BYDAY"] {
                for code in bd.split(separator: ",") {
                    let c = String(code.suffix(2))                                     // ignore un éventuel préfixe numérique
                    if let i = weekdayCodes.firstIndex(of: c) { byDay.insert(i) }
                }
            }
            if byDay.isEmpty { byDay = [startWeekdayIdx] }
        }

        var out: [Date] = []
        var produced = 0
        var k = 0
        let maxIterations = 4000   // ≈ 11 ans jour par jour : garde-fou
        while k < maxIterations {
            guard let candidate = cal.date(byAdding: .day, value: k, to: start.date) else { break }
            if candidate > windowEnd { break }
            if let u = untilDate, candidate > u { break }
            let matches: Bool
            if freq == "DAILY" {
                matches = k % interval == 0
            } else {
                let weekIndex = (k + mondayBased) / 7
                let wd = cal.component(.weekday, from: candidate) - 1
                matches = weekIndex % interval == 0 && byDay.contains(wd)
            }
            if matches {
                produced += 1
                out.append(candidate)
                if let c = count, produced >= c { break }
            }
            k += 1
        }
        return out
    }

    // MARK: - Lien de visio

    static func meetingLink(in texts: [String]) -> URL? {
        let hosts = ["meet.google.com", "zoom.us", "teams.microsoft.com", "teams.live.com"]
        guard let re = try? NSRegularExpression(pattern: #"https?://[^\s<>"'\)]+"#) else { return nil }
        for t in texts where !t.isEmpty {
            let ns = t as NSString
            for m in re.matches(in: t, range: NSRange(location: 0, length: ns.length)) {
                var candidate = ns.substring(with: m.range)
                while let last = candidate.last, ".,;".contains(last) { candidate.removeLast() }
                if let u = URL(string: candidate), let host = u.host?.lowercased(),
                   hosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
                    return u
                }
            }
        }
        return nil
    }
}
