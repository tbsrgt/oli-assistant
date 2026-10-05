import AppKit

// MARK: - Mails : ce qu'Oli sait de la boîte, et le rangement avec Claude
// Toutes les 5 min, Oli lit les 40 derniers mails de la boîte de réception (sans les marquer lus)
// et fait un premier tri tout seul. « Classer avec Claude » demande à Claude un tri plus fin et une
// phrase de résumé. « Ranger » déplace dans « Oli/<Catégorie> » sur le serveur ce qui n'est pas « À
// traiter » : rien n'est supprimé, et « Annuler » remet tout dans la boîte de réception.
// Claude ne voit que l'expéditeur, l'objet et le début de chaque mail ; il ne peut rien envoyer.

@MainActor
final class MailCenter: ObservableObject {
    static let shared = MailCenter()
    private init() {}

    @Published private(set) var mails: [OliMail] = []
    @Published private(set) var unread: Int? = nil
    @Published private(set) var loading = false
    @Published private(set) var error: String? = nil
    @Published private(set) var lastSync: Date? = nil
    @Published var categories: [Int: MailCategory] = [:]
    @Published private(set) var summaries: [Int: String] = [:]
    @Published private(set) var byClaude: Set<Int> = []
    @Published private(set) var classifying = false
    @Published private(set) var moving = false
    @Published var result: String? = nil
    @Published var filter: MailCategory? = nil
    @Published private(set) var canUndo = false
    @Published private(set) var box: MailBox? = nil

    private var timer: Timer?

    var isConnected: Bool { !MailAccounts.all.isEmpty }
    var boxes: [MailBox] { MailAccounts.all }

    /// Shows another mailbox: what was sorted for the previous one is forgotten.
    func switchTo(_ b: MailBox) {
        MailAccounts.select(b)
        mails = []; unread = nil; categories = [:]; summaries = [:]; byClaude = []
        error = nil; result = nil; filter = nil; lastSync = nil
        box = b
        canUndo = !loadJournal().isEmpty
        Task { await refresh() }
    }
    var toTidy: [OliMail] { mails.filter { (categories[$0.uid] ?? .important) != .important } }
    var importantCount: Int { mails.filter { (categories[$0.uid] ?? .important) == .important }.count }

    func start() {
        guard timer == nil else { return }
        box = MailAccounts.selected
        canUndo = !loadJournal().isEmpty
        let t = Timer(timeInterval: 300, repeats: true) { _ in Task { @MainActor in await MailCenter.shared.refresh() } }
        t.tolerance = 30
        RunLoop.main.add(t, forMode: .common)
        timer = t
        Task { await refresh() }
    }

    // MARK: Server

    private struct Account: Sendable { let user: String; let password: String; let host: String; let port: Int; var token: String? = nil }

    private var account: Account? {
        guard let b = MailAccounts.selected else { return nil }
        if box?.id != b.id { box = b }
        let preset = ImapClient.preset(for: b.address)
        // A custom incoming server only for the Settings mailbox.
        let custom = b.id == EmailSender.account?.address.lowercased() ? KeychainStore.shared.get("mail-imap-host") : nil
        let host = custom.flatMap { $0.isEmpty ? nil : $0 } ?? preset.host
        return Account(user: b.address, password: MailAccounts.cleanAppPassword(b.password), host: host, port: preset.port)
    }

    private func withServer<T: Sendable>(_ body: @Sendable @escaping (ImapClient) async throws -> T) async throws -> T {
        guard var a = account else { throw ImapError.failed("aucune boîte mail connectée") }
        if MailAccounts.selected?.google == true {
            a.token = try await GoogleOAuth.accessToken(refresh: a.password)
        }
        let acc = a
        return try await Task.detached {
            let c = ImapClient(host: acc.host, port: acc.port)
            try await c.connect()
            if let t = acc.token { try await c.authenticate(user: acc.user, accessToken: t) }
            else { try await c.login(acc.user, acc.password) }
            let r = try await body(c)
            await c.logout()
            return r
        }.value
    }

    func refresh() async {
        guard isConnected, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let (list, count) = try await withServer { c -> ([OliMail], Int?) in
                let unseen = await c.unseen()
                let total = try await c.select("INBOX")
                return (try await c.recent(40, total: total), unseen)
            }
            // Same mailbox, already loaded once: what is new may be a mail from Oculot (mode étoile).
            if lastSync != nil {
                let before = Set(mails.map(\.uid))
                StarPower.shared.newMails(list.filter { !before.contains($0.uid) })
            }
            mails = list
            unread = count
            error = nil
            lastSync = Date()
            // Keep Claude's choices; a first guess for the others.
            for m in list where categories[m.uid] == nil || !byClaude.contains(m.uid) {
                categories[m.uid] = MailParsing.guess(m)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// A category chosen by Claude or by hand: a refresh no longer guesses over it.
    func markDecided(_ uid: Int) { byClaude.insert(uid) }

    // MARK: Claude

    func classifyWithClaude() async {
        guard !mails.isEmpty, !classifying else { return }
        guard let claude = ClaudeService.claudeCodePath else {
            result = "Claude n’est pas connecté : Réglages → Agents → Connecter Claude."
            return
        }
        classifying = true
        defer { classifying = false }
        let list = mails.map { m -> [String: Any] in
            ["uid": m.uid, "de": "\(m.fromName) <\(m.fromAddress)>", "objet": m.subject, "debut": String(m.snippet.prefix(160))]
        }
        let json = (try? JSONSerialization.data(withJSONObject: list)).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
        let cats = MailCategory.allCases.map(\.rawValue).joined(separator: ", ")
        let system = """
        Tu tries la boîte mail d'un membre d'Oculot Studio (studio web, clients artisans et PME). \
        Catégories possibles : \(cats). « important » = un humain attend une réponse ou une action \
        (client, prospect, partenaire, rendez-vous, urgence) : ce mail reste dans la boîte de réception. \
        « clients » = échanges avec des clients sans action immédiate. « notifications » = messages automatiques \
        (GitHub, Vercel, alertes, confirmations). Réponds UNIQUEMENT par un tableau JSON, sans texte autour : \
        [{"uid": 123, "cat": "factures", "resume": "phrase de 8 mots max en français"}].
        """
        let r = await ClaudeService.runClaudeCode(claude: claude, prompt: "Classe ces mails :\n" + json, session: nil, system: system)
        let parsed = MailParsing.parseClassification(r.0 ?? "")
        guard !parsed.isEmpty else {
            result = r.2.map { "Claude n’a pas pu classer : \($0)" } ?? "Claude n’a pas répondu comme prévu, réessaie."
            return
        }
        for (uid, v) in parsed {
            categories[uid] = v.0
            if !v.1.isEmpty { summaries[uid] = v.1 }
            byClaude.insert(uid)
        }
        result = "Claude a classé \(parsed.count) mail\(parsed.count > 1 ? "s" : "") : \(toTidy.count) à ranger, \(importantCount) à traiter."
        SoundEngine.shared.play("approve")
    }

    // MARK: Ranger / annuler

    private struct JournalEntry: Codable { let mailbox: String; let uid: Int?; let messageId: String }
    /// One journal per mailbox: « Annuler » only touches the box it was tidied in.
    private var journalKey: String { "mailTidyJournal.v1." + (MailAccounts.selected?.id ?? "") }

    private func loadJournal() -> [JournalEntry] {
        (UserDefaults.standard.data(forKey: journalKey)).flatMap { try? JSONDecoder().decode([JournalEntry].self, from: $0) } ?? []
    }

    /// Moves every mail not « À traiter » into « Oli/<Catégorie> ». Only after the user's click.
    func tidy() async {
        let groups = Dictionary(grouping: toTidy) { categories[$0.uid] ?? .important }
        guard !groups.isEmpty, !moving else { return }
        moving = true
        defer { moving = false }
        let plan: [(String, [OliMail])] = groups.compactMap { cat, ms in cat.folder.map { ($0, ms) } }
        do {
            let entries = try await withServer { c -> [JournalEntry] in
                let d = await c.delimiter()
                await c.create("Oli")
                var out: [JournalEntry] = []
                for (folder, ms) in plan {
                    let box = "Oli" + d + folder
                    await c.create(box)
                    try await c.select("INBOX")
                    let map = try await c.move(ms.map(\.uid), to: box)
                    out += ms.map { JournalEntry(mailbox: box, uid: map[$0.uid], messageId: $0.messageId) }
                }
                return out
            }
            if let d = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(d, forKey: journalKey) }
            canUndo = true
            let moved = Set(plan.flatMap { $0.1.map(\.uid) })
            mails.removeAll { moved.contains($0.uid) }
            let parts = plan.sorted { $0.1.count > $1.1.count }.prefix(3).map { "\($0.1.count) \($0.0.lowercased())" }
            result = "\(moved.count) mail\(moved.count > 1 ? "s" : "") rangé\(moved.count > 1 ? "s" : "") dans « Oli » : " + parts.joined(separator: ", ") + ". Rien n’est supprimé."
            SoundEngine.shared.play("approve")
            appendAppLog("oli.log", "Mails rangés : \(moved.count)")
        } catch {
            result = error.localizedDescription
        }
    }

    func undo() async {
        let journal = loadJournal()
        guard !journal.isEmpty, !moving else { return }
        moving = true
        defer { moving = false }
        do {
            let back = try await withServer { c -> Int in
                var n = 0
                for (box, entries) in Dictionary(grouping: journal, by: \.mailbox) {
                    guard (try? await c.select(box)) != nil else { continue }
                    var uids = entries.compactMap(\.uid)
                    // Server without COPYUID: find them again by Message-ID.
                    for e in entries where e.uid == nil && !e.messageId.isEmpty {
                        let items = (try? await c.command("UID SEARCH HEADER Message-ID \(MailParsing.quote(e.messageId))")) ?? []
                        uids += items.flatMap { $0.text.split(separator: " ").dropFirst(2).compactMap { Int($0) } }
                    }
                    n += (try? await c.move(uids, to: "INBOX").count).map { $0 == 0 ? uids.count : $0 } ?? 0
                }
                return n
            }
            UserDefaults.standard.removeObject(forKey: journalKey)
            canUndo = false
            result = "\(back) mail\(back > 1 ? "s" : "") remis dans la boîte de réception."
            await refresh()
        } catch {
            result = error.localizedDescription
        }
    }

    // MARK: Open one mail

    func open(_ m: OliMail) {
        let id = m.messageId.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let gmail = MailAccounts.selected?.isGmail == true
        let url = gmail ? URL(string: "https://mail.google.com/mail/u/0/#search/rfc822msgid%3A\(id)")
                        : URL(string: "message://%3C\(id)%3E")
        if let url, !id.isEmpty { NSWorkspace.shared.open(url) }
    }
}
