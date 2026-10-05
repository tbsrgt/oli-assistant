import Foundation

// « Oli range ton bureau » sur un faux bureau temporaire. Lancer : scripts/test-tidy.sh

@main
enum DesktopTidyTests {
    nonisolated(unsafe) static var failures = 0
    static func check(_ label: String, _ ok: Bool, _ detail: String = "") {
        if ok { print("  ✓ \(label)") } else { print("  ✗ \(label)  \(detail)"); failures += 1 }
    }

    static func main() throws {
        print("Catégories")
        check("capture d'écran", DesktopTidy.category(for: "Capture d’écran 2026-10-05 à 09.30.12.png") == "Captures d’écran")
        check("screenshot", DesktopTidy.category(for: "Screenshot 2026-10-05.png") == "Captures d’écran")
        check("photo", DesktopTidy.category(for: "IMG_2041.HEIC") == "Images")
        check("pdf", DesktopTidy.category(for: "Devis.pdf") == "PDF")
        check("apk", DesktopTidy.category(for: "Oli-Android.apk") == "Archives et installeurs")
        check("figma", DesktopTidy.category(for: "maquette.fig") == "Design")
        check("sans extension", DesktopTidy.category(for: "notes") == "Autres")
        check("nom libre", DesktopTidy.freeName("a.pdf") { $0 == "a.pdf" || $0 == "a (2).pdf" } == "a (3).pdf")

        print("Ranger puis annuler")
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("oli-tidy-\(UUID().uuidString)")
        let desk = root.appendingPathComponent("Desktop")
        let journal = root.appendingPathComponent("journal.json")
        try fm.createDirectory(at: desk.appendingPathComponent("PIPOU AGENCY"), withIntermediateDirectories: true)
        let files = ["Devis.pdf", "photo.jpg", "Capture d’écran 1.png", "notes", ".cache-secret"]
        for f in files { try Data(f.utf8).write(to: desk.appendingPathComponent(f)) }
        // Same name already in the tidy folder: must not be overwritten.
        try fm.createDirectory(at: desk.appendingPathComponent("Rangé par Oli/PDF"), withIntermediateDirectories: true)
        try Data("ancien".utf8).write(to: desk.appendingPathComponent("Rangé par Oli/PDF/Devis.pdf"))

        let r = DesktopTidy.tidy(desktop: desk, journal: journal)
        check("4 fichiers rangés", r.moves.count == 4, "\(r.moves.count) \(r.errors)")
        check("le dossier reste sur le bureau", fm.fileExists(atPath: desk.appendingPathComponent("PIPOU AGENCY").path))
        check("le fichier caché ne bouge pas", fm.fileExists(atPath: desk.appendingPathComponent(".cache-secret").path))
        let pdf2 = desk.appendingPathComponent("Rangé par Oli/PDF/Devis (2).pdf")
        check("homonyme : renommé, rien d'écrasé", fm.fileExists(atPath: pdf2.path)
              && (try? String(contentsOf: desk.appendingPathComponent("Rangé par Oli/PDF/Devis.pdf"), encoding: .utf8)) == "ancien")
        check("capture rangée", fm.fileExists(atPath: desk.appendingPathComponent("Rangé par Oli/Captures d’écran/Capture d’écran 1.png").path))
        check("résumé lisible", r.summary.contains("4 fichiers rangés"), r.summary)

        let back = DesktopTidy.undo(journal: journal)
        check("annuler remet les 4", back == 4, "\(back)")
        for f in files { check("\(f) de retour", fm.fileExists(atPath: desk.appendingPathComponent(f).path)) }
        check("l'ancien fichier rangé avant est toujours là", fm.fileExists(atPath: desk.appendingPathComponent("Rangé par Oli/PDF/Devis.pdf").path))
        check("les dossiers vidés par l'annulation disparaissent", !fm.fileExists(atPath: desk.appendingPathComponent("Rangé par Oli/Images").path))
        let total = (try? fm.subpathsOfDirectory(atPath: desk.path))?.filter { !$0.hasSuffix("/") }.count ?? 0
        check("aucun fichier perdu", total >= 6, "\(total)")

        print("Bureau déjà rangé")
        let r2 = DesktopTidy.tidy(desktop: root.appendingPathComponent("vide-\(UUID().uuidString)"), journal: journal)
        check("bureau introuvable : message, pas de plantage", r2.moves.isEmpty && !r2.errors.isEmpty)

        print("Où, quoi, comment")
        let root2 = fm.temporaryDirectory.appendingPathComponent("oli-tidy2-\(UUID().uuidString)")
        let d2 = root2.appendingPathComponent("Desktop"), dl = root2.appendingPathComponent("Downloads")
        try fm.createDirectory(at: d2, withIntermediateDirectories: true)
        try fm.createDirectory(at: dl, withIntermediateDirectories: true)
        for f in ["a.pdf", "b.png", "c.zip"] { try Data(f.utf8).write(to: d2.appendingPathComponent(f)) }
        for f in ["setup.dmg", "facture.pdf"] { try Data(f.utf8).write(to: dl.appendingPathComponent(f)) }
        let old = Date().addingTimeInterval(-40 * 86400)
        try fm.setAttributes([.modificationDate: old, .creationDate: old], ofItemAtPath: dl.appendingPathComponent("setup.dmg").path)
        let roots: [DesktopTidy.Source: URL] = [.desktop: d2, .downloads: dl]

        var o = DesktopTidy.Options()
        o.categories = ["PDF"]
        check("seulement les PDF du Bureau", DesktopTidy.plan(o, roots: roots).moves.map { ($0.from as NSString).lastPathComponent } == ["a.pdf"])
        o.sources = [.desktop, .downloads]
        check("PDF du Bureau et des Téléchargements", DesktopTidy.plan(o, roots: roots).moves.count == 2)
        o.categories = DesktopTidy.allCategories; o.minAgeDays = 30
        let oldOnly = DesktopTidy.plan(o, roots: roots).moves.map { ($0.from as NSString).lastPathComponent }
        check("plus de 30 jours : seulement le vieil installeur", oldOnly == ["setup.dmg"], "\(oldOnly)")
        o.minAgeDays = 0; o.grouping = .month
        let month = DesktopTidy.monthFolder(Date())
        let pm = DesktopTidy.plan(o, roots: roots)
        check("par mois : « \(month) »", pm.moves.contains { $0.to.hasSuffix("Rangé par Oli/\(month)/a.pdf") }, "\(pm.moves.map(\.to))")
        check("le vieux fichier va dans son mois", pm.moves.contains { $0.to.contains(DesktopTidy.monthFolder(old)) && $0.to.hasSuffix("setup.dmg") })
        o.grouping = .typeMonth
        check("type puis mois", DesktopTidy.plan(o, roots: roots).moves.contains { $0.to.hasSuffix("Rangé par Oli/PDF/\(month)/a.pdf") })
        check("l'aperçu ne bouge rien", fm.fileExists(atPath: d2.appendingPathComponent("a.pdf").path))
        let r3 = DesktopTidy.tidy(o, roots: roots, journal: journal)
        check("5 rangés dans les deux dossiers", r3.moves.count == 5, "\(r3.moves.count) \(r3.errors)")
        check("annuler remet les 5", DesktopTidy.undo(journal: journal) == 5)
        check("plus aucun dossier « Rangé par Oli » vide", !fm.fileExists(atPath: d2.appendingPathComponent("Rangé par Oli").path)
              && !fm.fileExists(atPath: dl.appendingPathComponent("Rangé par Oli").path))
        try? fm.removeItem(at: root2)   // the temporary test folder only

        try? fm.removeItem(at: root)   // the temporary test folder only
        if failures > 0 { print("\(failures) échec(s)"); exit(1) }
        print("Rangement du bureau : tout passe")
    }
}
