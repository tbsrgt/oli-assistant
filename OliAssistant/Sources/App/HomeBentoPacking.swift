import Foundation

// MARK: - Rangement des tuiles bento (logique pure, testée par scripts/test-home.sh)
// Range les tuiles dans l'ordre choisi, en rangées de `columns` cases : une petite tuile prend
// 1 case, une large 2. Une large qui ne tient plus au bout d'une rangée passe à la suivante.

enum HomeBentoPacking {
    /// Rows in the chosen order. When the next tile does not fit at the end of a row, the first
    /// later tile that does fills the gap (a small one after a wide), so no hole is left.
    static func rows<T>(_ items: [T], span: (T) -> Int, columns: Int) -> [[T]] {
        guard columns > 0 else { return [] }
        var rest = items
        var rows: [[T]] = []
        while !rest.isEmpty {
            var row: [T] = []
            var used = 0
            while used < columns,
                  let i = rest.firstIndex(where: { used + max(1, min(span($0), columns)) <= columns }) {
                // Only jump ahead to fill a row already started.
                if i > 0 && row.isEmpty { break }
                let item = rest.remove(at: i)
                row.append(item); used += max(1, min(span(item), columns))
            }
            if row.isEmpty { row.append(rest.removeFirst()) }
            rows.append(row)
        }
        return rows
    }
}

// MARK: - Forme exacte des jetons (connexion en un clic)
// Oli ne garde du presse-papiers que ce qui a exactement la forme d'un jeton du service attendu.

enum TokenShape {
    static func pattern(_ service: String) -> String? {
        switch service {
        case "github":    return #"^(ghp_|gho_|github_pat_)[A-Za-z0-9_]{20,255}$"#
        case "vercel":    return #"^([A-Za-z0-9]{24}|vc[a-z]_[A-Za-z0-9_]{20,120})$"#
        case "instagram": return #"^(IGAA|EAA)[A-Za-z0-9_-]{30,400}$"#
        case "pagespeed": return #"^AIza[0-9A-Za-z_-]{35}$"#
        default:          return nil
        }
    }

    static func matches(_ s: String, service: String) -> Bool {
        guard let p = pattern(service) else { return false }
        return s.range(of: p, options: .regularExpression) != nil
    }
}
