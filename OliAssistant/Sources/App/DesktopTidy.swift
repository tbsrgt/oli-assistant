import Foundation

// MARK: - « Oli range ton bureau »
// Les fichiers posés en vrac sur le Bureau (et/ou dans Téléchargements) partent dans « Rangé par
// Oli », rangés par type, par mois ou les deux, selon ce qui est choisi dans l'onglet ✨ de l'encoche. Rien n'est jamais supprimé :
// on déplace seulement, les dossiers et les fichiers cachés ne bougent pas, un nom déjà pris
// devient « nom (2) ». Chaque rangement est noté dans un journal, et « Annuler » remet tout en place.

enum DesktopTidy {
    static let folderName = "Rangé par Oli"

    struct Move: Codable, Sendable, Equatable {
        let from: String
        let to: String
    }

    struct Report: Sendable {
        var moves: [Move] = []
        var byCategory: [String: Int] = [:]
        var errors: [String] = []

        /// « 12 fichiers rangés : 5 captures d'écran, 4 images, 3 PDF »
        var summary: String {
            guard !moves.isEmpty else { return errors.isEmpty ? "Rien à ranger, c’est déjà propre ✨" : "Je n’ai rien pu ranger : \(errors[0])" }
            let parts = byCategory.sorted { $0.value > $1.value }.prefix(3).map { "\($0.value) \($0.key.lowercased())" }
            return "\(moves.count) fichier\(moves.count > 1 ? "s" : "") rangé\(moves.count > 1 ? "s" : "") dans « \(folderName) » : "
                + parts.joined(separator: ", ") + ". Rien n’est supprimé."
        }
    }

    // MARK: Categories (pure)

    static func category(for fileName: String) -> String {
        let lower = fileName.lowercased()
        if lower.hasPrefix("capture d’écran") || lower.hasPrefix("capture d'écran") || lower.hasPrefix("screenshot")
            || lower.hasPrefix("enregistrement de l’écran") || lower.hasPrefix("enregistrement de l'écran")
            || lower.hasPrefix("screen recording") {
            return "Captures d’écran"
        }
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "png", "jpg", "jpeg", "heic", "heif", "gif", "webp", "tiff", "tif", "bmp", "svg", "raw", "dng", "cr2", "nef", "avif":
            return "Images"
        case "mov", "mp4", "m4v", "avi", "mkv", "webm":
            return "Vidéos"
        case "mp3", "wav", "m4a", "aac", "flac", "aiff", "aif", "ogg":
            return "Musique"
        case "pdf":
            return "PDF"
        case "doc", "docx", "pages", "txt", "rtf", "md", "odt", "key", "ppt", "pptx", "numbers", "xls", "xlsx", "csv", "odp", "ods":
            return "Documents"
        case "zip", "rar", "7z", "tar", "gz", "tgz", "dmg", "pkg", "apk", "iso":
            return "Archives et installeurs"
        case "fig", "sketch", "psd", "ai", "xd", "blend", "afdesign", "afphoto", "indd":
            return "Design"
        case "swift", "js", "ts", "tsx", "jsx", "py", "html", "css", "json", "sh", "rb", "go", "kt", "java", "php", "sql", "yml", "yaml":
            return "Code"
        default:
            return "Autres"
        }
    }

    /// « nom.ext », « nom (2).ext », « nom (3).ext »… first one not in `taken`.
    static func freeName(_ name: String, taken: (String) -> Bool) -> String {
        guard taken(name) else { return name }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
            if !taken(candidate) { return candidate }
            n += 1
        }
    }

    // MARK: Options (Ranger → où, quoi, comment)

    enum Source: String, Codable, CaseIterable, Sendable {
        case desktop, downloads
        var label: String { self == .desktop ? "Bureau" : "Téléchargements" }
        var icon: String { self == .desktop ? "menubar.dock.rectangle" : "arrow.down.circle.fill" }
        var url: URL {
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(self == .desktop ? "Desktop" : "Downloads")
        }
    }

    enum Grouping: String, Codable, CaseIterable, Sendable {
        case type, month, typeMonth
        var label: String {
            switch self {
            case .type:      return "Par type"
            case .month:     return "Par mois"
            case .typeMonth: return "Type puis mois"
            }
        }
    }

    static let allCategories = ["Captures d’écran", "Images", "Vidéos", "Musique", "PDF", "Documents",
                                "Archives et installeurs", "Design", "Code", "Autres"]

    struct Options: Codable, Sendable, Equatable {
        var sources: [Source] = [.desktop]
        var categories: [String] = DesktopTidy.allCategories
        var minAgeDays = 0          // 0 = tout ; 7 / 30 = seulement ce qui traîne depuis
        var grouping: Grouping = .type

        private static let key = "tidyOptions.v1"
        static func load() -> Options {
            (UserDefaults.standard.data(forKey: key)).flatMap { try? JSONDecoder().decode(Options.self, from: $0) } ?? Options()
        }
        func save() {
            if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: Self.key) }
        }
    }

    static var desktopURL: URL { Source.desktop.url }

    private static var journalURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Oli/rangement/dernier.json")
    }

    /// « Octobre 2026 »
    static func monthFolder(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "LLLL yyyy"
        let s = f.string(from: date)
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    // MARK: Plan (what would move, nothing touched) / tidy / undo

    struct Plan: Sendable {
        var moves: [Move] = []
        var category: [String] = []          // same order as moves
        var errors: [String] = []
        var countByCategory: [String: Int] {
            category.reduce(into: [:]) { $0[$1, default: 0] += 1 }
        }
    }

    /// Loose files of the chosen folders, where each one would go. `roots` replaces the real
    /// folders (tests). Folders, hidden files and apps never move.
    static func plan(_ o: Options, roots: [Source: URL]? = nil, now: Date = Date()) -> Plan {
        let fm = FileManager.default
        var plan = Plan()
        var reserved = Set<String>()   // destinations already planned in this run
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .creationDateKey, .contentModificationDateKey]
        for source in o.sources {
            let root = roots?[source] ?? source.url
            let items: [URL]
            do {
                items = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
            } catch {
                plan.errors.append("accès à « \(source.label) » refusé (Réglages Système → Confidentialité → Fichiers et dossiers → Oli)")
                continue
            }
            let target = root.appendingPathComponent(folderName, isDirectory: true)
            for item in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let v = try? item.resourceValues(forKeys: Set(keys))
                if v?.isDirectory == true && v?.isPackage != true { continue }
                if item.pathExtension.lowercased() == "app" { continue }
                let name = item.lastPathComponent
                if name == ".DS_Store" || name.hasSuffix(".localized") { continue }
                let cat = category(for: name)
                guard o.categories.contains(cat) else { continue }
                let date = v?.creationDate ?? v?.contentModificationDate ?? now
                if o.minAgeDays > 0, now.timeIntervalSince(v?.contentModificationDate ?? date) < Double(o.minAgeDays) * 86400 { continue }
                var dir = target
                switch o.grouping {
                case .type:      dir = dir.appendingPathComponent(cat, isDirectory: true)
                case .month:     dir = dir.appendingPathComponent(monthFolder(date), isDirectory: true)
                case .typeMonth: dir = dir.appendingPathComponent(cat, isDirectory: true).appendingPathComponent(monthFolder(date), isDirectory: true)
                }
                let free = freeName(name) { n in
                    let p = dir.appendingPathComponent(n).path
                    return fm.fileExists(atPath: p) || reserved.contains(p)
                }
                let dest = dir.appendingPathComponent(free).path
                reserved.insert(dest)
                plan.moves.append(Move(from: item.path, to: dest))
                plan.category.append(cat)
            }
        }
        return plan
    }

    /// Runs the plan: moves only, never deletes. The journal makes « Annuler » possible.
    static func tidy(_ o: Options = .load(), roots: [Source: URL]? = nil, journal: URL? = nil) -> Report {
        let fm = FileManager.default
        let p = plan(o, roots: roots)
        var report = Report()
        report.errors = p.errors
        for (m, cat) in zip(p.moves, p.category) {
            let dest = URL(fileURLWithPath: m.to)
            do {
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard !fm.fileExists(atPath: m.to) else { continue }   // never overwrite
                try fm.moveItem(at: URL(fileURLWithPath: m.from), to: dest)
                report.moves.append(m)
                report.byCategory[cat, default: 0] += 1
            } catch {
                report.errors.append("\((m.from as NSString).lastPathComponent) : \(error.localizedDescription)")
            }
        }
        if !report.moves.isEmpty {
            let j = journal ?? journalURL
            try? fm.createDirectory(at: j.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? JSONEncoder().encode(report.moves).write(to: j)
        }
        return report
    }

    /// Desktop only, by type (tests and older callers).
    static func tidy(desktop: URL, journal: URL? = nil) -> Report {
        tidy(Options(), roots: [.desktop: desktop], journal: journal)
    }

    static var canUndo: Bool { FileManager.default.fileExists(atPath: journalURL.path) }

    /// Puts every file of the last tidy back where it was. A file the user moved since, or whose
    /// old place is taken again, stays where it is (nothing is overwritten). Returns how many came back.
    @discardableResult
    static func undo(journal: URL? = nil) -> Int {
        let fm = FileManager.default
        let j = journal ?? journalURL
        guard let data = try? Data(contentsOf: j),
              let moves = try? JSONDecoder().decode([Move].self, from: data) else { return 0 }
        var back = 0
        for m in moves where fm.fileExists(atPath: m.to) && !fm.fileExists(atPath: m.from) {
            if (try? fm.moveItem(atPath: m.to, toPath: m.from)) != nil { back += 1 }
        }
        try? fm.removeItem(at: j)   // the journal only (a small JSON file Oli wrote), never a user file
        // Folders Oli created and that are empty again go away, deepest first. rmdir() refuses a
        // non-empty folder, so no file can ever be removed by this.
        var dirs = Set<String>()
        for m in moves {
            var d = (m.to as NSString).deletingLastPathComponent
            while d.contains("/\(folderName)") {
                dirs.insert(d)
                d = (d as NSString).deletingLastPathComponent
            }
        }
        for d in dirs.sorted(by: { $0.count > $1.count }) {
            if (try? fm.contentsOfDirectory(atPath: d)) == [".DS_Store"] { unlink(d + "/.DS_Store") }
            rmdir(d)
        }
        return back
    }
}
