// Lecture Instagram d'Oli (Social.swift) sur des réponses d'exemple de l'API Graph.
//   scripts/test-social.sh
import Foundation

@main
struct TestSocial {
    static func main() {
        var failures = 0
        func expect(_ cond: Bool, _ msg: String) {
            print((cond ? "  ✓ " : "  ✗ ") + msg)
            if !cond { failures += 1 }
        }
        let now = SocialParse.date("2026-10-04T18:00:00+0000")!
        expect(SocialParse.date("2026-10-02T09:15:00+0000") != nil, "date Graph (+0000) lue")

        let profile = Data(#"{"username":"oculot.studio","followers_count":1234,"media_count":42,"id":"178"}"#.utf8)
        let p = SocialParse.profile(profile)
        expect(p?.0 == "oculot.studio" && p?.1 == 1234 && p?.2 == 42, "profil : nom, abonnés, nombre de posts")

        let media = Data(#"""
        {"data":[
          {"id":"m1","caption":" Refonte livrée ✨ ","timestamp":"2026-09-26T10:00:00+0000","like_count":31,"comments_count":2,"permalink":"https://instagram.com/p/m1"},
          {"id":"m2","caption":"Avant / après","timestamp":"2026-09-20T10:00:00+0000","like_count":12,"comments_count":0,"permalink":"https://instagram.com/p/m2"}
        ]}
        """#.utf8)
        let posts = SocialParse.posts(media)
        expect(posts.count == 2 && posts[0].id == "m1" && posts[0].caption == "Refonte livrée ✨" && posts[0].likes == 31, "posts triés du plus récent, légende nettoyée")

        let comments = Data(#"""
        {"data":[
          {"id":"c1","text":"Superbe !","username":"boulangerie_rose","timestamp":"2026-09-27T08:00:00+0000"},
          {"id":"c2","text":"Combien pour un site ?","username":"garage.martin","timestamp":"2026-09-28T08:00:00+0000",
           "replies":{"data":[{"id":"r1","username":"oculot.studio"}]}},
          {"id":"c3","text":"Merci à vous","username":"oculot.studio","timestamp":"2026-09-28T09:00:00+0000"},
          {"id":"c4","text":"Vieux commentaire","username":"ancien","timestamp":"2026-08-01T08:00:00+0000"}
        ]}
        """#.utf8)
        let since = now.addingTimeInterval(-14 * 86400)
        let un = SocialParse.unanswered(comments, ownUsername: "oculot.studio", post: posts[0], since: since)
        expect(un.map(\.id) == ["c1"], "sans réponse : ignore ceux auxquels on a répondu, les nôtres et les vieux (\(un.map(\.id)))")

        let accounts = Data(#"{"data":[{"id":"p1"},{"id":"p2","instagram_business_account":{"id":"1784"}}]}"#.utf8)
        expect(SocialParse.businessAccountId(accounts) == "1784", "compte pro trouvé via /me/accounts")
        expect(SocialParse.error(Data(#"{"error":{"message":"x","code":190}}"#.utf8)) == "jeton Instagram expiré ou invalide", "jeton expiré expliqué")
        expect(SocialParse.usesInstagramLogin("IGAAabc") && !SocialParse.usesInstagramLogin("EAAabc"), "type de jeton reconnu")

        var s = SocialSnapshot(username: "oculot.studio", followers: 1234, mediaCount: 42, posts: posts, unanswered: un, fetchedAt: now)
        expect(s.daysSinceLastPost(now: now) == 8, "dernier post il y a 8 j")
        expect(s.reminders(now: now) == ["1 commentaire sans réponse", "pas de post depuis 8 jours"], "rappels : commentaire puis silence (\(s.reminders(now: now)))")
        expect(s.followersLabel.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ") == "1 234 abonnés", "abonnés formatés à la française (\(s.followersLabel))")
        s.unanswered = []; s.posts = [SocialPost(id: "n", caption: "", timestamp: now.addingTimeInterval(-86400), likes: 0, comments: 0, permalink: "")]
        expect(s.reminders(now: now).isEmpty && s.lastPostLabel(now: now) == "dernier post hier", "tout va bien : aucun rappel")
        s.error = "jeton Instagram expiré ou invalide"
        expect(s.reminders(now: now).isEmpty, "en erreur : pas de faux rappel")

        print(failures == 0 ? "\nOK" : "\n\(failures) échec(s)")
        exit(failures == 0 ? 0 : 1)
    }
}
