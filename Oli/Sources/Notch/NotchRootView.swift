import SwiftUI

// MARK: - L'îlot (replié / déplié)

struct NotchRootView: View {
    let geo: NotchGeometry
    @EnvironmentObject var model: OliModel

    var body: some View {
        let size = Island.size(model, geo)
        ZStack(alignment: .top) {
            IslandShape(ear: Island.ear, radius: model.expanded ? 30 : 12)
                .fill(Color.black)
                .frame(width: size.width + Island.ear * 2, height: size.height)

            if model.expanded {
                ExpandedIsland(notchWidth: geo.notchWidth, notchHeight: geo.notchHeight)
                    .frame(width: size.width, height: size.height, alignment: .top)
                    .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.22).delay(0.12)),
                                            removal: .opacity.animation(.easeIn(duration: 0.12))))
            } else {
                FoldedIsland(notchWidth: geo.notchWidth, notchHeight: geo.notchHeight, width: size.width)
                    .transition(.opacity.animation(.easeOut(duration: 0.18)))
            }
        }
        .frame(width: Island.panel.width, height: Island.panel.height, alignment: .top)
        .animation(.spring(response: 0.42, dampingFraction: 0.8), value: model.tab)
        .animation(.spring(response: 0.42, dampingFraction: 0.8), value: model.flash?.text)
        .animation(.spring(response: 0.42, dampingFraction: 0.8), value: model.approvals.count)
        .preferredColorScheme(.dark)
    }
}

/// Black island: flat top glued to the screen edge with two concave « ears », rounded bottom corners.
struct IslandShape: Shape {
    var ear: CGFloat
    var radius: CGFloat
    var animatableData: CGFloat { get { radius } set { radius = newValue } }

    func path(in r: CGRect) -> Path {
        let e = ear, rad = min(radius, r.height / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + e, y: r.minY + e), control: CGPoint(x: r.minX + e, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + e, y: r.maxY - rad))
        p.addQuadCurve(to: CGPoint(x: r.minX + e + rad, y: r.maxY), control: CGPoint(x: r.minX + e, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - e - rad, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - e, y: r.maxY - rad), control: CGPoint(x: r.maxX - e, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - e, y: r.minY + e))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - e, y: r.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Replié

struct FoldedIsland: View {
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let width: CGFloat
    @EnvironmentObject var model: OliModel

    var body: some View {
        let ear = (width - notchWidth) / 2
        HStack(spacing: 0) {
            HStack {
                OliMascot(mood: model.mood, panic: model.panic, size: notchHeight + 6)
                    .padding(.leading, 8)
                Spacer(minLength: 0)
            }
            .frame(width: ear)
            Color.clear.frame(width: notchWidth)
            HStack {
                Spacer(minLength: 0)
                if let flash = model.flash {
                    Text(flash.text)
                        .font(Typo.text(11.5, .semibold)).foregroundStyle(flash.tint)
                        .lineLimit(1).truncationMode(.tail)
                        .padding(.trailing, 14)
                } else {
                    MiniOliCluster(size: notchHeight).padding(.trailing, 10)
                }
            }
            .frame(width: ear)
        }
        .frame(width: width, height: notchHeight)
    }
}

/// The connected sections as tiny Olis, two rows (folded island, right ear).
struct MiniOliCluster: View {
    let size: CGFloat
    @EnvironmentObject var model: OliModel

    var body: some View {
        let items = Array(model.focusable.filter { $0 != .home }.prefix(6))
        let d = max(11, (size - 4) / 2)
        let rows = items.count > 3 ? [Array(items.prefix((items.count + 1) / 2)), Array(items.dropFirst((items.count + 1) / 2))] : [items]
        VStack(spacing: 1) {
            ForEach(rows.indices, id: \.self) { i in
                HStack(spacing: 2) {
                    ForEach(rows[i]) { s in
                        OliMascot(mood: model.miniMood(s), size: d, tint: s.tint)
                    }
                }
            }
        }
    }
}

// MARK: - Déplié

struct ExpandedIsland: View {
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    @EnvironmentObject var model: OliModel

    var body: some View {
        VStack(spacing: 0) {
            IslandHeader(notchWidth: notchWidth)
                .frame(height: max(34, notchHeight))
            Group {
                switch model.tab {
                case .overview:
                    HStack(spacing: 10) {
                        FocusCard().frame(width: 344)
                        MiniOliGrid()
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                case .full:
                    FullSection()
                case .terminal:
                    TerminalSection()
                case .chat:
                    ChatSection().padding(.horizontal, 6)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

struct IslandHeader: View {
    let notchWidth: CGFloat
    @EnvironmentObject var model: OliModel

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                HeaderTab(icon: "house.fill", on: model.tab == .overview || model.tab == .full) {
                    model.tab = .overview
                }
                HeaderTab(icon: "terminal.fill", on: model.tab == .terminal) {
                    model.tab = .terminal; NotchController.shared.makeKey()
                }
                if model.sections.contains(.chat) {
                    HeaderTab(icon: "bubble.left.fill", on: model.tab == .chat) {
                        model.tab = .chat; NotchController.shared.makeKey()
                    }
                }
            }
            .padding(.leading, 14)
            Spacer(minLength: notchWidth / 2)
            HStack(spacing: 14) {
                Button { SettingsWindow.shared.show() } label: { Image(systemName: "gearshape") }
                Button { model.soundOn.toggle() } label: {
                    Image(systemName: model.soundOn ? "speaker.wave.2" : "speaker.slash")
                }
                Button { NotchController.shared.fold() } label: {
                    Image(systemName: "chevron.up").font(.system(size: 12, weight: .bold))
                        .frame(width: 26, height: 26).background(Circle().fill(Palette.raised))
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 14))
            .foregroundStyle(Palette.sand)
            .padding(.trailing, 16)
        }
    }
}

private struct HeaderTab: View {
    let icon: String
    let on: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(on ? Palette.cream : Palette.sand)
                .frame(width: 34, height: 26)
                .background(Capsule().fill(on ? Palette.raised : hover ? Palette.card : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: Focus card (left)

struct FocusCard: View {
    @EnvironmentObject var model: OliModel

    var body: some View {
        let s = model.section
        HStack(alignment: .top, spacing: 12) {
            Group {
                if s == .home {
                    OliMascot(mood: model.mood, panic: model.panic, size: 62)
                } else {
                    OliMascot(mood: model.miniMood(s), size: 52, tint: s.tint)
                }
            }
            .frame(width: 66, height: 66)
            .padding(.top, 8)
            .onTapGesture { model.section = .home }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Dot(color: s.tint)
                    Text(s.title).font(Typo.text(12.5, .bold)).foregroundStyle(Palette.cream).lineLimit(1)
                    Text(CardContent.subtitle(s, model)).font(Typo.text(11)).foregroundStyle(Palette.dust).lineLimit(1)
                    Spacer(minLength: 2)
                    Button { model.tab = .full } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.sand)
                            .frame(width: 22, height: 22).background(Circle().fill(Palette.raised))
                    }
                    .buttonStyle(.plain).help("Tout voir")
                }
                if s == .claude, let a = model.approvals.first {
                    CompactApproval(approval: a)
                } else {
                    let lines = CardContent.lines(s, model)
                    if lines.isEmpty {
                        Text(CardContent.empty(s)).font(Typo.text(11.5)).foregroundStyle(Palette.sand)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(lines.prefix(3)) { l in
                        HStack(spacing: 6) {
                            Circle().fill(l.color).frame(width: 5, height: 5)
                            Text(l.title).font(Typo.text(11.5, l.urgent ? .bold : .semibold))
                                .foregroundStyle(l.urgent ? l.color : Palette.cream).lineLimit(1).layoutPriority(1)
                            Text(l.detail).font(Typo.text(10.5)).foregroundStyle(Palette.sand).lineLimit(1).truncationMode(.tail)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { l.action() }
                    }
                }
            }
            .padding(.top, 12).padding(.trailing, 12)
        }
        .padding(.leading, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 22).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(s == .home ? Palette.hair : s.tint.opacity(0.25), lineWidth: 1))
    }
}

private struct CompactApproval: View {
    let approval: Approval
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(approval.project) demande \(approval.tool)").font(Typo.text(11.5, .bold)).foregroundStyle(Palette.beurre).lineLimit(1)
            Text(approval.detail).font(Typo.mono(10.5)).foregroundStyle(Palette.cream).lineLimit(2)
                .padding(6).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.black.opacity(0.4)))
            HStack(spacing: 6) {
                ActionButton(title: "Autoriser", icon: "checkmark", tint: Palette.menthe, filled: true) { ClaudeSessions.shared.answer(approval, allow: true) }
                ActionButton(title: "Refuser", icon: "xmark", tint: Palette.alerte) { ClaudeSessions.shared.answer(approval, allow: false) }
                ActionButton(title: "Terminal", tint: Palette.sand) { ClaudeSessions.shared.answer(approval, allow: nil) }
            }
        }
    }
}

// MARK: Mini Oli grid (right)

struct MiniOliGrid: View {
    @EnvironmentObject var model: OliModel

    var body: some View {
        let items = model.focusable.filter { $0 != model.section }
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(items) { s in MiniOliPill(section: s) }
            }
            .padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 22).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Palette.hair, lineWidth: 1))
    }
}

struct MiniOliPill: View {
    let section: Section
    @EnvironmentObject var model: OliModel
    @State private var hover = false

    var body: some View {
        let badge = model.badge(section)
        Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { model.section = section } } label: {
            HStack(spacing: 6) {
                OliMascot(mood: model.miniMood(section), size: 24, tint: section == .home ? nil : section.tint)
                Text(section == .home ? "Accueil" : section.title)
                    .font(Typo.text(12, .semibold)).foregroundStyle(hover ? Palette.cream : Palette.sand).lineLimit(1)
                Spacer(minLength: 0)
                if badge > 0 {
                    Text("\(badge)").font(Typo.text(9.5, .bold)).foregroundStyle(Palette.night)
                        .padding(.horizontal, 5).frame(minHeight: 15)
                        .background(Capsule().fill(section == .sites ? Palette.alerte : Palette.beurre))
                }
            }
            .padding(.leading, 4).padding(.trailing, 8).frame(height: 34)
            .background(Capsule().fill(hover ? Palette.raised : Color.black.opacity(0.25)))
            .overlay(Capsule().stroke(section.tint.opacity(hover ? 0.5 : 0.22), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: Full section

struct FullSection: View {
    @EnvironmentObject var model: OliModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button { model.tab = .overview } label: {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.sand)
                        .frame(width: 26, height: 26).background(Circle().fill(Palette.raised))
                }
                .buttonStyle(.plain)
                Text(model.section.title).font(Typo.display(19, .bold)).foregroundStyle(Palette.cream)
                Text(CardContent.subtitle(model.section, model)).font(Typo.text(11.5)).foregroundStyle(Palette.dust).lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 6)
            SectionBody().padding(.horizontal, 6)
        }
    }
}

struct SectionBody: View {
    @EnvironmentObject var model: OliModel
    var body: some View {
        switch model.section {
        case .home: HomeSection()
        case .claude: ClaudeSection()
        case .projects: ProjectsSection()
        case .sites: SitesSection()
        case .agenda: AgendaSection()
        case .instagram: InstagramSection()
        case .terminal: TerminalSection()
        case .chat: ChatSection()
        }
    }
}
