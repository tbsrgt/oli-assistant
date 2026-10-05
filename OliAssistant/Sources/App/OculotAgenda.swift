import Foundation

// MARK: - Agenda Oculot en direct (au-delà du lien iCal)
// Avec le mot de passe de l'agenda (Trousseau), Oli lit l'agenda de l'équipe comme le site :
// les appels à prendre (rendez-vous prospect / appel sans personne dessus), les nouveautés
// (créés par quelqu'un d'autre depuis ta dernière visite), et il peut prendre un appel ou créer un
// rendez-vous. Même fonction Supabase que agenda.oculot.studio (oculot_agenda_api), mêmes règles.

struct OculotRdv: Identifiable, Equatable, Sendable {
    let id: String
    let type: String          // prospect, appel, client, prod, indispo
    let titre: String
    let date: String          // AAAA-MM-JJ (heure de Paris)
    let debut: String         // HH:MM
    let fin: String
    let journee: Bool
    let participants: [String]
    let lieu: String
    let creePar: String
    let creeLe: Double        // ms
    let entreprise: String
    let tel: String
    let ville: String

    static let paris = TimeZone(identifier: "Europe/Paris")!

    var start: Date? {
        var c = Calendar(identifier: .gregorian); c.timeZone = Self.paris
        let d = date.split(separator: "-").compactMap { Int($0) }
        let t = (journee ? "00:00" : debut).split(separator: ":").compactMap { Int($0) }
        guard d.count == 3, t.count == 2 else { return nil }
        return c.date(from: DateComponents(year: d[0], month: d[1], day: d[2], hour: t[0], minute: t[1]))
    }

    var isCall: Bool { type == "prospect" || type == "appel" }
    var who: String { [entreprise, ville].filter { !$0.isEmpty }.joined(separator: " · ") }
}

enum OculotAgendaParsing {
    static func rdvs(_ json: [String: Any]) -> [OculotRdv] {
        (json["rdv"] as? [[String: Any]] ?? []).compactMap { d in
            guard let id = d["id"] as? String, (d["supprime"] as? Bool) != true, (d["masque"] as? Bool) != true else { return nil }
            let p = d["prospect"] as? [String: Any] ?? [:]
            return OculotRdv(id: id, type: d["type"] as? String ?? "", titre: d["titre"] as? String ?? "(sans titre)",
                             date: d["date"] as? String ?? "", debut: d["debut"] as? String ?? "", fin: d["fin"] as? String ?? "",
                             journee: d["journee"] as? Bool ?? false, participants: d["participants"] as? [String] ?? [],
                             lieu: d["lieu"] as? String ?? "", creePar: d["creePar"] as? String ?? "",
                             creeLe: (d["creeLe"] as? Double) ?? Double(d["creeLe"] as? Int ?? 0),
                             entreprise: p["entreprise"] as? String ?? "", tel: p["tel"] as? String ?? "", ville: p["ville"] as? String ?? "")
        }
    }

    /// Calls nobody has taken yet, from now on, soonest first.
    static func callsToTake(_ all: [OculotRdv], now: Date = Date()) -> [OculotRdv] {
        all.filter { $0.isCall && $0.participants.isEmpty && ($0.start ?? .distantPast) > now.addingTimeInterval(-3600) }
            .sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
    }

    /// Created by someone else in the last 7 days, still to come, not seen yet.
    static func news(_ all: [OculotRdv], seen: Set<String>, me: String?, now: Date = Date()) -> [OculotRdv] {
        let weekAgo = (now.timeIntervalSince1970 - 7 * 86400) * 1000
        return all.filter { !seen.contains($0.id) && $0.creeLe >= weekAgo && $0.creePar != (me ?? "")
                            && ($0.start ?? .distantPast) > now.addingTimeInterval(-3600) }
            .sorted { $0.creeLe > $1.creeLe }
    }

    /// Same shape of id as the site: lowercase letters and digits.
    static func newId() -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<16).map { _ in chars.randomElement()! })
    }

    /// The JSON the site writes for a new appointment.
    static func payload(type: String, titre: String, start: Date, minutes: Int, lieu: String, notes: String,
                        participants: [String], me: String, now: Date = Date()) -> [String: Any] {
        var c = Calendar(identifier: .gregorian); c.timeZone = OculotRdv.paris
        let end = start.addingTimeInterval(Double(minutes) * 60)
        let day = c.dateComponents([.year, .month, .day], from: start)
        let hm = { (d: Date) -> String in let x = c.dateComponents([.hour, .minute], from: d); return String(format: "%02d:%02d", x.hour ?? 0, x.minute ?? 0) }
        let ms = (now.timeIntervalSince1970 * 1000).rounded()
        return ["type": type, "titre": titre, "date": String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0),
                "debut": hm(start), "fin": hm(end), "journee": false, "statut": "confirme", "participants": participants,
                "client": "", "lieu": lieu, "notes": notes, "recur": "none", "recurFin": "", "supprime": false,
                "creePar": me, "creeLe": ms, "majPar": me, "majLe": ms,
                "histo": [["par": me, "le": ms, "quoi": "crée le rendez-vous (Oli)"]]]
    }
}

@MainActor
final class OculotAgenda: ObservableObject {
    static let shared = OculotAgenda()
    private init() {}

    @Published private(set) var rdvs: [OculotRdv] = []
    @Published private(set) var team: [String: String] = [:]      // id → nom
    @Published private(set) var role: String = ""
    @Published private(set) var lastSync: Date? = nil
    @Published var error: String? = nil
    @Published private(set) var seen: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "agendaSeen.v1") ?? [])

    private var timer: Timer?

    var password: String? { KeychainStore.shared.get("agenda-password") }
    var me: String? { KeychainStore.shared.get("agenda-member") }
    var isUnlocked: Bool { password != nil && me != nil }
    var isAdmin: Bool { role == "admin" }

    var callsToTake: [OculotRdv] { OculotAgendaParsing.callsToTake(rdvs) }
    var news: [OculotRdv] { OculotAgendaParsing.news(rdvs, seen: seen, me: me) }

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 120, repeats: true) { _ in Task { @MainActor in await OculotAgenda.shared.refresh() } }
        t.tolerance = 20
        RunLoop.main.add(t, forMode: .common)
        timer = t
        Task { await refresh() }
    }

    // MARK: RPC

    private func call(_ action: String, _ args: [String: Any] = [:]) async throws -> [String: Any] {
        guard let pw = password else { throw AgendaLogin.Failure.message("Agenda verrouillé.") }
        var req = URLRequest(url: AgendaLogin.rpc, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(AgendaLogin.publicKey, forHTTPHeaderField: "apikey")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["p_code": pw, "p_action": action, "p_args": args])
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { throw AgendaLogin.Failure.message("Agenda injoignable.") }
        let j = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        if let e = j["erreur"] as? String { throw AgendaLogin.Failure.message(Self.explain(e)) }
        return j
    }

    static func explain(_ code: String) -> String {
        switch code {
        case "code_invalide": return "Mot de passe de l’agenda refusé."
        case "trop_essais":   return "Trop d’essais, réessaie dans 15 minutes."
        case "deja_pris":     return "Quelqu’un a déjà pris cet appel."
        case "reserve_admin": return "Réservé aux admins de l’agenda."
        case "hors_regles":   return "Ce créneau ne respecte pas les règles de l’agenda."
        case "rdv_inconnu":   return "Ce rendez-vous n’existe plus."
        default:              return "L’agenda a refusé (\(code))."
        }
    }

    func refresh() async {
        guard isUnlocked else { return }
        do {
            let j = try await call("lire")
            let fresh = OculotAgendaParsing.rdvs(j)
            if lastSync != nil {
                let before = Set(rdvs.map(\.id))
                StarPower.shared.newAppointments(fresh.filter { !before.contains($0.id) }, me: me)
            }
            rdvs = fresh
            team = Dictionary((j["equipe"] as? [[String: Any]] ?? []).compactMap { d in
                (d["id"] as? String).map { ($0, d["nom"] as? String ?? $0) } }, uniquingKeysWith: { a, _ in a })
            role = (j["moi"] as? [String: Any])?["role"] as? String ?? ""
            lastSync = Date()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Checks the password, remembers it (Trousseau) with who you are in the team.
    func unlock(password pw: String, member: String?) async -> (ok: Bool, members: [AgendaLogin.Member]) {
        do {
            let t = try await AgendaLogin.team(password: pw)
            guard let m = member ?? t.me ?? AgendaLogin.guess(t.members)?.id else { return (false, t.members) }
            KeychainStore.shared.set("agenda-password", value: pw)
            KeychainStore.shared.set("agenda-member", value: m)
            error = nil
            await refresh()
            return (true, t.members)
        } catch {
            self.error = error.localizedDescription
            return (false, [])
        }
    }

    func take(_ r: OculotRdv) async -> Bool {
        guard let me else { return false }
        do {
            _ = try await call("rdv_prendre", ["id": r.id, "moi": me])
            SoundEngine.shared.play("approve")
            await refresh()
            AgendaPoller.shared.pollNow()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func create(type: String, titre: String, start: Date, minutes: Int, lieu: String, notes: String, participants: [String]) async -> Bool {
        guard let me else { return false }
        let data = OculotAgendaParsing.payload(type: type, titre: titre, start: start, minutes: minutes, lieu: lieu, notes: notes,
                                               participants: participants.isEmpty ? [me] : participants, me: me)
        do {
            _ = try await call("ecrire", ["id": OculotAgendaParsing.newId(), "data": data])
            SoundEngine.shared.play("approve")
            appendAppLog("oli.log", "Rendez-vous créé depuis Oli : \(titre)")
            await refresh()
            AgendaPoller.shared.pollNow()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func markSeen() {
        seen.formUnion(rdvs.map(\.id))
        UserDefaults.standard.set(Array(seen.suffix(2000)), forKey: "agendaSeen.v1")
    }
}
