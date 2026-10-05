import SwiftUI

// MARK: - Grille bento de l'accueil
// Range les tuiles visibles, dans l'ordre choisi, en rangées de `columns` cases : une petite
// tuile prend 1 case, une large 2. Une large qui ne tient plus au bout d'une rangée passe à la
// suivante. `maxRows` coupe ce qui ne tient pas (l'encoche n'a la place que pour 2 rangées).

struct HomeBentoView: View {
    @ObservedObject var state: AppState
    @ObservedObject var layout = HomeLayoutStore.shared
    @ObservedObject private var mail = MailCenter.shared   // the Mails tile follows the mailbox
    var columns: Int = 3
    var tileHeight: CGFloat = 44
    var spacing: CGFloat = 5
    var maxRows: Int? = nil
    var large: Bool = false        // desktop bubble: bigger type
    /// Tiles to show instead of the saved layout (Settings preview).
    var override: [HomeTile]? = nil

    var body: some View {
        let tiles = override ?? layout.visibleTiles
        let all = HomeBentoPacking.rows(tiles, span: { $0.size.span }, columns: columns)
        let rows = maxRows.map { Array(all.prefix($0)) } ?? all
        // A minute tick keeps « Aujourd'hui » and the agenda countdown fresh.
        TimelineView(.everyMinute) { tl in
            GeometryReader { geo in
                let unit = (geo.size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
                VStack(alignment: .leading, spacing: spacing) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: spacing) {
                            ForEach(row) { tile in
                                let span = CGFloat(min(tile.size.span, columns))
                                HomeTileView(kind: tile.kind, data: tile.kind.data(state, now: tl.date), large: large, wide: span > 1) {
                                    tile.kind.open(state)
                                }
                                .frame(width: unit * span + spacing * (span - 1), height: tileHeight)
                            }
                        }
                    }
                }
            }
        }
        .frame(height: CGFloat(rows.count) * tileHeight + CGFloat(max(0, rows.count - 1)) * spacing)
    }
}

struct HomeTileView: View {
    let kind: HomeTileKind
    let data: HomeTileData
    var large: Bool = false
    var wide: Bool = false
    let action: () -> Void

    private var notConnected: Bool { data.detail == "Se connecter" }
    private var detailColor: Color { Color(hex: data.tone == .neutral ? "#9398A1" : data.tone.hex) }

    /// Desktop bubble: icon badge, big value, name, one line of detail.
    private var largeContent: some View {
        HStack(alignment: .center, spacing: 9) {
            Image(systemName: kind.icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Color(hex: kind.color))
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(hex: kind.color).opacity(0.16)))
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(data.value)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: data.tone == .alert ? "#FF8D97" : "#F5F6F8"))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(kind.title).font(.system(size: 10.5, weight: .semibold)).foregroundColor(Color(hex: "#6B7079")).lineLimit(1)
                }
                Text(data.detail).font(.system(size: 11, weight: .medium)).foregroundColor(detailColor)
                    .lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
    }

    /// Notch: tiny name on top, the value below (the detail too when the tile is wide).
    private var compactContent: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: kind.icon).font(.system(size: 8, weight: .bold)).foregroundColor(Color(hex: kind.color))
                Text(kind.title).font(.system(size: 9, weight: .semibold)).foregroundColor(Color(hex: "#8E939C")).lineLimit(1)
                Spacer(minLength: 0)
                if data.tone != .neutral { Circle().fill(Color(hex: data.tone.hex)).frame(width: 5, height: 5) }
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(notConnected ? "Brancher" : data.value)
                    .font(.system(size: notConnected ? 11 : 13, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: notConnected ? "#FF8A52" : data.tone == .alert ? "#FF8D97" : "#F5F6F8"))
                    .lineLimit(1).minimumScaleFactor(0.75)
                    .layoutPriority(1)
                if wide && !notConnected {
                    Text(data.detail).font(.system(size: 9.5, weight: .medium)).foregroundColor(detailColor)
                        .lineLimit(1).truncationMode(.tail)
                }
            }
        }
    }

    @State private var hover = false

    var body: some View {
        let alert = data.tone == .alert
        Button(action: action) {
            Group {
                if large { largeContent } else { compactContent }
            }
            .padding(.horizontal, large ? 10 : 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: large ? 14 : 10, style: .continuous)
                    .fill(alert ? Color(hex: "#F4505E").opacity(hover ? 0.22 : 0.14)
                                : hover ? Color(hex: kind.color).opacity(0.14) : Color(hex: "#16171A"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: large ? 14 : 10, style: .continuous)
                    .stroke(alert ? Color(hex: "#F4505E").opacity(0.55)
                                  : Color(hex: kind.color).opacity(hover ? 0.5 : 0.10), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: large ? 14 : 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("\(kind.title) : \(data.detail)")
        .scaleEffect(hover ? 1.02 : 1)
        .onHover { h in withAnimation(.spring(response: 0.2, dampingFraction: 0.75)) { hover = h } }
    }
}
