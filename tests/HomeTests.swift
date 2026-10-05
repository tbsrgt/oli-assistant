import Foundation
import CoreGraphics

// Accueil bento, mouvement d'Oli sur le bureau, forme des jetons. Lancer : scripts/test-home.sh

@main
enum HomeTests {
    nonisolated(unsafe) static var failures = 0

    static func check(_ label: String, _ ok: Bool, _ detail: String = "") {
        if ok { print("  ✓ \(label)") } else { print("  ✗ \(label)  \(detail)"); failures += 1 }
    }

    static func inside(_ p: CGPoint, _ r: CGRect) -> Bool {
        p.x >= r.minX && p.x <= r.maxX && p.y >= r.minY && p.y <= r.maxY
    }

    static func main() {
        print("Rangement bento")
        let spans = { (s: Int) in s }
        let r1 = HomeBentoPacking.rows([1, 2, 1, 1, 2], span: spans, columns: 3)
        check("petites et larges rangées dans l'ordre", r1 == [[1, 2], [1, 1], [2]], "\(r1)")
        let r2 = HomeBentoPacking.rows([1, 1, 2], span: spans, columns: 3)
        check("une large qui ne tient plus passe à la rangée suivante", r2 == [[1, 1], [2]], "\(r2)")
        let r4 = HomeBentoPacking.rows([1, 2, 2, 1, 1], span: spans, columns: 2)
        check("une petite plus loin bouche le trou à côté d'une petite", r4 == [[1, 1], [2], [2], [1]], "\(r4)")
        let r5 = HomeBentoPacking.rows([2, 1, 2], span: spans, columns: 2)
        check("sans petite derrière, la rangée reste incomplète", r5 == [[2], [1], [2]], "\(r5)")
        let r3 = HomeBentoPacking.rows([2, 2], span: spans, columns: 1)
        check("une large prend toute la rangée sur une colonne", r3 == [[2], [2]], "\(r3)")
        check("rien à ranger", HomeBentoPacking.rows([Int](), span: spans, columns: 3).isEmpty)
        check("zéro colonne ne plante pas", HomeBentoPacking.rows([1], span: spans, columns: 0).isEmpty)

        print("Oli me suit")
        let c = CGPoint(x: 500, y: 500)
        check("souris tout près : Oli s'arrête pour qu'on le clique",
              DesktopOliMotionLogic.followStep(center: c, mouse: CGPoint(x: 530, y: 520)) == nil)
        if let n = DesktopOliMotionLogic.followStep(center: c, mouse: CGPoint(x: 900, y: 500)) {
            check("souris loin : Oli avance vers elle", n.x > c.x && n.x < 900)
            check("il se place sous la souris (y AppKit)", n.y < c.y)
        } else { check("souris loin : Oli avance", false) }
        let settled = CGPoint(x: 400 + 72, y: 400 - 72)
        check("déjà à sa place : il ne bouge plus",
              DesktopOliMotionLogic.followStep(center: settled, mouse: CGPoint(x: 400, y: 400)) == nil)

        print("Oli se promène")
        let step = DesktopOliMotionLogic.walkStep(center: c, target: CGPoint(x: 600, y: 500))
        check("un pas vers la cible, pas plus vite que 1,8 pt", step.map { $0.x > 500 && $0.x <= 501.8 } ?? false)
        check("arrivé : plus de pas", DesktopOliMotionLogic.walkStep(center: c, target: CGPoint(x: 501, y: 500)) == nil)
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        var seq: [CGFloat] = [0.0, 1.0]
        let far = DesktopOliMotionLogic.wanderTarget(from: CGPoint(x: 790, y: 300), bounds: bounds, random: { seq.removeFirst() })
        check("la balade reste dans l'écran", inside(far, bounds), "\(far)")
        for _ in 0..<200 {
            let t = DesktopOliMotionLogic.wanderTarget(from: CGPoint(x: 400, y: 300), bounds: bounds)
            if !inside(t, bounds) { check("cible aléatoire dans l'écran", false, "\(t)"); break }
        }

        print("Forme des jetons")
        check("jeton GitHub classique", TokenShape.matches("ghp_" + String(repeating: "a", count: 36), service: "github"))
        check("jeton GitHub fin", TokenShape.matches("github_pat_" + String(repeating: "B1_", count: 20), service: "github"))
        check("un mot de passe n'est pas un jeton GitHub", !TokenShape.matches("motdepasse123", service: "github"))
        check("phrase copiée ignorée", !TokenShape.matches("ghp_ abc def", service: "github"))
        check("jeton Vercel 24 caractères", TokenShape.matches("Abcdefghijklmnopqrstuvwx", service: "vercel"))
        check("un mot de 24 lettres avec espace refusé", !TokenShape.matches("Abcdefghijk mnopqrstuvwx", service: "vercel"))
        check("clé Google", TokenShape.matches("AIza" + String(repeating: "x", count: 35), service: "pagespeed"))
        check("jeton Instagram", TokenShape.matches("IGAA" + String(repeating: "Z", count: 120), service: "instagram"))
        check("service inconnu : rien", !TokenShape.matches("ghp_" + String(repeating: "a", count: 36), service: "email"))

        if failures > 0 { print("\(failures) échec(s)"); exit(1) }
        print("Accueil, mouvement et jetons : tout passe")
    }
}
