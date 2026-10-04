import SwiftUI

// MARK: - Interface de l'encoche

struct NotchRootView: View {
    let geo: NotchGeometry
    @EnvironmentObject var model: OliModel

    var body: some View {
        ZStack(alignment: .top) {
            if model.expanded {
                ExpandedNotch(notchHeight: geo.notchHeight, notchWidth: geo.notchWidth)
                    .transition(.asymmetric(insertion: .scale(scale: 0.92, anchor: .top).combined(with: .opacity),
                                            removal: .opacity))
            } else {
                FoldedNotch(notchWidth: geo.notchWidth, notchHeight: geo.notchHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: model.expanded)
        .preferredColorScheme(.dark)
    }
}

/// The notch outline: square top (glued to the screen edge), rounded bottom.
struct NotchShape: Shape {
    var radius: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        p.addQuadCurve(to: CGPoint(x: r.maxX - radius, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + radius, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - radius), control: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: Folded

struct FoldedNotch: View {
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    @EnvironmentObject var model: OliModel

    var body: some View {
        HStack(spacing: 0) {
            if let flash = model.flash {
                HStack(spacing: 6) {
                    OliMascot(mood: model.mood, panic: model.panic, size: notchHeight + 2)
                    Spacer(minLength: 0)
                }
                .frame(width: NotchLayout.ear)
                Color.clear.frame(width: notchWidth)
                Text(flash.text)
                    .font(Typo.text(11.5, .semibold))
                    .foregroundStyle(flash.tint)
                    .lineLimit(1).truncationMode(.tail)
                    .frame(width: NotchLayout.ear - 12, alignment: .leading)
                    .padding(.trailing, 12)
            }
        }
        .frame(height: notchHeight)
        .frame(width: model.flash == nil ? notchWidth : nil)
        .frame(maxWidth: model.flash == nil ? nil : .infinity)
        .background(NotchShape(radius: 10).fill(Color.black))
        .overlay(alignment: .bottom) {
            // A thin coloured line under the notch when Oli is not calm (alarm, waiting, working)
            Capsule().fill(model.mood == .alarm ? Palette.alerte : model.mood == .waiting ? Palette.beurre
                           : model.mood == .busy ? Palette.lilas : .clear)
                .frame(width: notchWidth * 0.5, height: 2)
                .opacity(model.mood == .calm || model.mood == .happy ? 0 : 1)
        }
    }
}

// MARK: Expanded

struct ExpandedNotch: View {
    let notchHeight: CGFloat
    let notchWidth: CGFloat
    @EnvironmentObject var model: OliModel

    var body: some View {
        VStack(spacing: 0) {
            // Top strip beside the notch
            HStack(spacing: 0) {
                Text("Oli")
                    .font(Typo.display(15, .heavy))
                    .foregroundStyle(Palette.tomate)
                    .padding(.leading, 22)
                Spacer()
                Color.clear.frame(width: notchWidth)
                Spacer()
                HStack(spacing: 14) {
                    Button { model.soundOn.toggle() } label: {
                        Image(systemName: model.soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    }
                    Button { NotchController.shared.fold() } label: { Image(systemName: "chevron.up") }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.sand)
                .padding(.trailing, 20)
            }
            .frame(height: notchHeight)

            HStack(spacing: 0) {
                Rail()
                Rectangle().fill(Palette.hair).frame(width: 1).padding(.vertical, 10)
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader()
                    SectionBody()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .padding(.leading, 18).padding(.trailing, 20).padding(.top, 10).padding(.bottom, 16)
            }
        }
        .frame(width: NotchLayout.size.width, height: NotchLayout.size.height)
        .background(NotchShape(radius: 26).fill(Palette.night))
        .overlay(NotchShape(radius: 26).stroke(Palette.hair, lineWidth: 1))
    }
}

struct Rail: View {
    @EnvironmentObject var model: OliModel

    var body: some View {
        VStack(spacing: 6) {
            OliMascot(mood: model.mood, panic: model.panic, size: 50)
                .padding(.top, 2).padding(.bottom, 6)
                .onTapGesture { model.section = .home }
            ForEach(model.sections.filter { $0 != .home }) { s in
                RailButton(section: s)
            }
            Spacer(minLength: 4)
            Button { SettingsWindow.shared.show() } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.dust)
                    .frame(width: 38, height: 32)
            }
            .buttonStyle(.plain)
            .help("Réglages")
        }
        .frame(width: 72)
        .padding(.vertical, 8)
    }
}

struct RailButton: View {
    let section: Section
    @EnvironmentObject var model: OliModel
    @State private var hover = false

    private var badge: Int {
        switch section {
        case .claude: return model.approvals.count
        case .sites: return model.sites.filter { $0.status == .down }.count
        case .instagram: return model.instagram?.unanswered.count ?? 0
        default: return 0
        }
    }

    var body: some View {
        let on = model.section == section
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { model.section = section }
            if section == .terminal || section == .chat { NotchController.shared.makeKey() }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: section.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(on ? section.tint : hover ? Palette.cream : Palette.sand)
                    .frame(width: 40, height: 32)
                    .background(RoundedRectangle(cornerRadius: 10).fill(on ? section.tint.opacity(0.14) : hover ? Palette.raised : .clear))
                if badge > 0 {
                    Text("\(badge)")
                        .font(Typo.text(9, .bold))
                        .foregroundStyle(Palette.night)
                        .padding(.horizontal, 4).frame(minWidth: 14, minHeight: 14)
                        .background(Capsule().fill(section == .sites ? Palette.alerte : Palette.beurre))
                        .offset(x: 3, y: -3)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(section.title)
    }
}

struct SectionHeader: View {
    @EnvironmentObject var model: OliModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(model.section.title)
                .font(Typo.display(22, .bold))
                .foregroundStyle(Palette.cream)
            Text(subtitle)
                .font(Typo.text(12))
                .foregroundStyle(Palette.dust)
                .lineLimit(1)
            Spacer()
        }
    }

    private var subtitle: String {
        switch model.section {
        case .home:
            return Date().formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_FR")))
        case .claude:
            let n = model.sessions.count
            return n == 0 ? "aucune session" : n == 1 ? "1 session" : "\(n) sessions"
        case .terminal: return OliTerminal.shared.directory
        case .projects: return model.projects.isEmpty ? "" : "\(model.projects.filter { !$0.isDone }.count) en cours"
        case .sites:
            guard let d = model.sitesSynced else { return "première vérification…" }
            return "vérifiés à " + d.formatted(date: .omitted, time: .shortened)
        case .agenda: return "14 prochains jours"
        case .instagram: return model.instagram?.username.isEmpty == false ? "@" + (model.instagram?.username ?? "") : ""
        case .chat: return "avec l’état du studio en direct"
        }
    }
}

struct SectionBody: View {
    @EnvironmentObject var model: OliModel

    var body: some View {
        Group {
            switch model.section {
            case .home: HomeSection()
            case .claude: ClaudeSection()
            case .terminal: TerminalSection()
            case .projects: ProjectsSection()
            case .sites: SitesSection()
            case .agenda: AgendaSection()
            case .instagram: InstagramSection()
            case .chat: ChatSection()
            }
        }
        .transition(.opacity)
    }
}
