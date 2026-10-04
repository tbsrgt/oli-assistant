import Foundation

// MARK: - Instantané pour le widget d'Oli
// Compilé dans l'app ET dans l'extension widget (voir project.yml).
// L'app écrit ~/Library/Application Support/Oli/widget/snapshot.json ; le widget (sandboxé) le lit
// grâce à une exception de sandbox en lecture seule sur ce seul dossier. Pas d'App Group : sans
// équipe Apple Developer (signature ad hoc), un App Group n'est pas provisionnable.

struct OliWidgetSnapshot: Codable, Sendable, Equatable {
    struct Site: Codable, Sendable, Equatable {
        let name: String
        /// "ok", "warning", "down", "unknown" (SiteStatus.rawValue).
        let status: String
    }
    struct Project: Codable, Sendable, Equatable {
        let name: String
        /// Échéance (minuit local), nil si le projet n'a pas de date.
        let dueDate: Date?
        let step: String
    }
    struct Event: Codable, Sendable, Equatable {
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
    }

    static let currentVersion = 1

    var version: Int = OliWidgetSnapshot.currentVersion
    var generatedAt: Date
    var sites: [Site]
    var nextProject: Project?
    /// Prochains rendez-vous (quelques-uns, pour que le widget avance seul quand l'un se termine).
    var events: [Event]

    var sitesDown: [Site] { sites.filter { $0.status == "down" } }
    var sitesOnline: Int { sites.filter { $0.status == "ok" || $0.status == "warning" }.count }

    /// Prochain rendez-vous à une date donnée : en cours ou à venir, les journées entières en dernier.
    func nextEvent(at date: Date) -> Event? {
        events.first { !$0.isAllDay && $0.end > date } ?? events.first { $0.end > date }
    }

    /// Comparaison sans l'horodatage : l'app ne réécrit le fichier que si le contenu change.
    func sameContent(as other: OliWidgetSnapshot) -> Bool {
        sites == other.sites && nextProject == other.nextProject && events == other.events
    }
}

enum OliWidgetStore {
    static let kind = "OliWidget"

    /// Vrai dossier personnel, même depuis la sandbox (où NSHomeDirectory() pointe vers le conteneur).
    static var realHome: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    /// ~/Library/Application Support/Oli/widget/ : le seul dossier que le widget a le droit de lire.
    static var directory: URL {
        realHome.appendingPathComponent("Library/Application Support/Oli/widget", isDirectory: true)
    }
    static var fileURL: URL { directory.appendingPathComponent("snapshot.json") }

    static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
    static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    static func read() -> OliWidgetSnapshot? {
        guard let data = try? Data(contentsOf: fileURL),
              let snap = try? makeDecoder().decode(OliWidgetSnapshot.self, from: data),
              snap.version == OliWidgetSnapshot.currentVersion else { return nil }
        return snap
    }

    static func write(_ snap: OliWidgetSnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try makeEncoder().encode(snap)
        try data.write(to: fileURL, options: .atomic)
    }
}
