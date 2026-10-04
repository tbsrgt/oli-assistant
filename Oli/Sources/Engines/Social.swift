import Foundation

// MARK: - Réseaux sociaux : Instagram en lecture (phase 5a)
// Pure parsing + rules (no AppState) so scripts/test-social.swift can compile it alone.
// Two kinds of token work:
//   • « Instagram API with Instagram Login » (token starting with IG…) → graph.instagram.com, /me
//   • « Instagram API with Facebook Login » (page-linked pro account, EAA… token) → graph.facebook.com,
//     account id found through /me/accounts (or typed in Settings).
// Read only: Oli never posts, likes or answers on its own.

struct SocialPost: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let caption: String
    let timestamp: Date
    let likes: Int
    let comments: Int
    let permalink: String
}

struct SocialComment: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let username: String
    let text: String
    let timestamp: Date
    let postPermalink: String
}

struct SocialSnapshot: Codable, Sendable, Equatable {
    static let quietDays = 6
    static let commentWindowDays = 14

    var username: String = ""
    var followers: Int? = nil
    var mediaCount: Int? = nil
    var posts: [SocialPost] = []
    var unanswered: [SocialComment] = []
    var fetchedAt: Date? = nil
    var error: String? = nil

    var lastPostAt: Date? { posts.map(\.timestamp).max() }
    /// Whole days since the last post (nil when there is no post).
    func daysSinceLastPost(now: Date = Date()) -> Int? {
        lastPostAt.map { Int(now.timeIntervalSince($0) / 86400) }
    }
    func postsSince(_ date: Date) -> [SocialPost] { posts.filter { $0.timestamp >= date } }

    /// Reminders in French, most pressing first (empty when all is fine or nothing was read).
    func reminders(now: Date = Date()) -> [String] {
        guard fetchedAt != nil, error == nil else { return [] }
        var out: [String] = []
        if !unanswered.isEmpty {
            out.append(unanswered.count == 1 ? "1 commentaire sans réponse" : "\(unanswered.count) commentaires sans réponse")
        }
        if let d = daysSinceLastPost(now: now), d >= Self.quietDays {
            out.append("pas de post depuis \(d) jours")
        } else if posts.isEmpty {
            out.append("aucun post publié")
        }
        return out
    }

    var followersLabel: String {
        guard let f = followers else { return "abonnés ?" }
        return f == 1 ? "1 abonné" : "\(f.formatted(.number.locale(Locale(identifier: "fr_FR")))) abonnés"
    }
    func lastPostLabel(now: Date = Date()) -> String {
        guard let d = daysSinceLastPost(now: now) else { return "aucun post" }
        if d == 0 { return "dernier post aujourd’hui" }
        if d == 1 { return "dernier post hier" }
        return "dernier post il y a \(d) j"
    }
}

enum SocialParse {
    /// Graph API dates look like "2026-10-02T09:15:00+0000".
    static func date(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        if let d = f.date(from: s) { return d }
        let iso = ISO8601DateFormatter()
        return iso.date(from: s)
    }

    static func json(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Graph error message, if the answer is an error.
    static func error(_ data: Data) -> String? {
        guard let err = json(data)?["error"] as? [String: Any] else { return nil }
        let msg = err["message"] as? String ?? "erreur Instagram"
        if (err["code"] as? Int) == 190 { return "jeton Instagram expiré ou invalide" }
        return msg
    }

    /// Profile: (username, followers, media count).
    static func profile(_ data: Data) -> (String, Int?, Int?)? {
        guard let j = json(data), j["error"] == nil else { return nil }
        let name = j["username"] as? String ?? ""
        return (name, j["followers_count"] as? Int, j["media_count"] as? Int)
    }

    static func posts(_ data: Data) -> [SocialPost] {
        guard let items = json(data)?["data"] as? [[String: Any]] else { return [] }
        return items.compactMap { m in
            guard let id = m["id"] as? String, let ts = date(m["timestamp"] as? String) else { return nil }
            return SocialPost(id: id, caption: (m["caption"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                              timestamp: ts, likes: m["like_count"] as? Int ?? 0,
                              comments: m["comments_count"] as? Int ?? 0, permalink: m["permalink"] as? String ?? "")
        }.sorted { $0.timestamp > $1.timestamp }
    }

    /// Comments left by others with no reply from the account, newer than `since`.
    static func unanswered(_ data: Data, ownUsername: String, post: SocialPost, since: Date) -> [SocialComment] {
        guard let items = json(data)?["data"] as? [[String: Any]] else { return [] }
        let me = ownUsername.lowercased()
        return items.compactMap { c in
            guard let id = c["id"] as? String, let ts = date(c["timestamp"] as? String), ts >= since else { return nil }
            let author = (c["username"] as? String ?? "")
            if !me.isEmpty && author.lowercased() == me { return nil }
            let replies = ((c["replies"] as? [String: Any])?["data"] as? [[String: Any]]) ?? []
            if replies.contains(where: { ($0["username"] as? String ?? "").lowercased() == me && !me.isEmpty }) { return nil }
            return SocialComment(id: id, username: author, text: (c["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                                 timestamp: ts, postPermalink: post.permalink)
        }
    }

    /// First Instagram business account id in a /me/accounts answer (Facebook Login).
    static func businessAccountId(_ data: Data) -> String? {
        guard let pages = json(data)?["data"] as? [[String: Any]] else { return nil }
        for p in pages {
            if let ig = p["instagram_business_account"] as? [String: Any], let id = ig["id"] as? String { return id }
        }
        return nil
    }

    /// Instagram Login tokens start with "IG"; Facebook Login tokens with "EAA".
    static func usesInstagramLogin(_ token: String) -> Bool { token.hasPrefix("IG") }
}

// MARK: - Network

enum SocialFetcher {
    static let version = "v21.0"

    private static func get(_ url: URL) async -> Data? {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 30
        let s = URLSession(configuration: cfg)
        defer { s.finishTasksAndInvalidate() }
        return try? await s.data(from: url).0
    }

    private static func url(_ host: String, _ path: String, _ query: [String: String]) -> URL? {
        var c = URLComponents(string: "https://\(host)/\(version)/\(path)")
        c?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        return c?.url
    }

    /// Reads profile, last 12 posts and the comments of the 6 most recent commented posts.
    static func fetch(token: String, accountId manualId: String?) async -> SocialSnapshot {
        var snap = SocialSnapshot()
        snap.fetchedAt = Date()
        let igLogin = SocialParse.usesInstagramLogin(token)
        let host = igLogin ? "graph.instagram.com" : "graph.facebook.com"

        var account = manualId?.trimmingCharacters(in: .whitespaces) ?? ""
        if account.isEmpty {
            if igLogin {
                account = "me"
            } else {
                guard let u = url(host, "me/accounts", ["fields": "instagram_business_account", "access_token": token]),
                      let d = await get(u) else { snap.error = "Instagram injoignable"; return snap }
                if let e = SocialParse.error(d) { snap.error = e; return snap }
                guard let id = SocialParse.businessAccountId(d) else {
                    snap.error = "aucun compte Instagram pro relié à une page Facebook"
                    return snap
                }
                account = id
            }
        }

        guard let pu = url(host, account, ["fields": "username,followers_count,media_count", "access_token": token]),
              let pd = await get(pu) else { snap.error = "Instagram injoignable"; return snap }
        if let e = SocialParse.error(pd) { snap.error = e; return snap }
        if let (name, followers, media) = SocialParse.profile(pd) {
            snap.username = name; snap.followers = followers; snap.mediaCount = media
        }

        guard let mu = url(host, "\(account)/media", ["fields": "id,caption,timestamp,like_count,comments_count,permalink",
                                                      "limit": "12", "access_token": token]),
              let md = await get(mu) else { return snap }
        if let e = SocialParse.error(md) { snap.error = e; return snap }
        snap.posts = SocialParse.posts(md)

        let since = Date().addingTimeInterval(-Double(SocialSnapshot.commentWindowDays) * 86400)
        for post in snap.posts.filter({ $0.comments > 0 }).prefix(6) {
            guard let cu = url(host, "\(post.id)/comments", ["fields": "id,text,username,timestamp,replies{username}",
                                                             "limit": "50", "access_token": token]),
                  let cd = await get(cu) else { continue }
            snap.unanswered += SocialParse.unanswered(cd, ownUsername: snap.username, post: post, since: since)
        }
        snap.unanswered.sort { $0.timestamp > $1.timestamp }
        return snap
    }
}
