import Foundation

// MARK: - Connexion à agenda.oculot.studio
// With the agenda password, reads the team and the caller's role (Supabase RPC used by the site),
// then asks the site for the member's personal iCal link. No link to copy by hand.

enum AgendaLogin {
    struct Member: Identifiable, Hashable, Sendable { let id: String; let name: String }
    struct Team: Sendable { let members: [Member]; let me: String? }   // me: set for a « closer »

    static let rpc = URL(string: "https://skyqbuunpwvzvabxhjug.supabase.co/rest/v1/rpc/oculot_agenda_api")!
    static let publicKey = "sb_publishable_U6EQgiXNfeuQ6pp9zjH4ew_sG4AOJRQ"   // public key, shipped in the site's JS
    static let push = URL(string: "https://agenda.oculot.studio/api/push")!

    enum Failure: Error, LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
    }

    /// Team members the caller may pick (admins), or the caller themself for a « closer ».
    static func team(password: String) async throws -> Team {
        var req = URLRequest(url: rpc, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(publicKey, forHTTPHeaderField: "apikey")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["p_code": password, "p_action": "lire", "p_args": [String: Any]()])
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { throw Failure.message("Agenda injoignable.") }
        let j = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        if j["erreur"] != nil || j["equipe"] == nil { throw Failure.message("Mot de passe de l’agenda refusé.") }
        let raw = j["equipe"] as? [[String: Any]] ?? []
        let moi = j["moi"] as? [String: Any] ?? [:]
        if (moi["role"] as? String) == "closer", let m = moi["membre"] as? String, !m.isEmpty {
            let name = raw.first { ($0["id"] as? String) == m }?["nom"] as? String ?? m
            return Team(members: [Member(id: m, name: name)], me: m)
        }
        let admins = raw.compactMap { d -> Member? in
            guard let id = d["id"] as? String, let nom = d["nom"] as? String, (d["role"] as? String) != "closer" else { return nil }
            return Member(id: id, name: nom)
        }
        return Team(members: admins, me: nil)
    }

    /// The member's personal iCal link (https).
    static func calendarLink(password: String, member: String) async throws -> String {
        var req = URLRequest(url: push, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["type": "lien_ics", "code": password, "membre": member])
        guard let (data, resp) = try? await URLSession.shared.data(for: req) else { throw Failure.message("Agenda injoignable.") }
        let j = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard (resp as? HTTPURLResponse)?.statusCode == 200, let url = j["url"] as? String, !url.isEmpty else {
            throw Failure.message("L’agenda n’a pas donné de lien de calendrier.")
        }
        return url
    }

    /// The member whose name matches the Mac user's first name, if any.
    static func guess(_ members: [Member]) -> Member? {
        let first = NSFullUserName().split(separator: " ").first.map { $0.lowercased() } ?? ""
        return members.first { $0.name.lowercased().hasPrefix(first) && !first.isEmpty } ?? (members.count == 1 ? members[0] : nil)
    }
}
