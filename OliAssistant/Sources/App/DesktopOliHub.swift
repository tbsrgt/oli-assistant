import AppKit
import SwiftUI

// MARK: - Oli sur le bureau : mouvement, bulles et panneau central
// Oli posé sur le bureau peut rester fixe, suivre la souris ou se promener. Un clic sur lui
// ouvre son panneau : du nouveau, l'accueil bento, les actions en un clic, les routines et les
// services encore à brancher. Quand une routine a quelque chose à dire, une bulle sort d'Oli.

enum DesktopOliMotion: String, CaseIterable, Identifiable {
    case still, follow, wander
    var id: String { rawValue }

    var label: String {
        switch self {
        case .still:  return "Fixe"
        case .follow: return "Me suit"
        case .wander: return "Se promène"
        }
    }

    var icon: String {
        switch self {
        case .still:  return "pin.fill"
        case .follow: return "cursorarrow.motionlines"
        case .wander: return "figure.walk"
        }
    }

    static let key = "desktopOliMotion"
    static var current: DesktopOliMotion {
        get { DesktopOliMotion(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .still }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}

// MARK: - Speech bubble + hub windows

struct OliSaid: Identifiable {
    let id = UUID()
    let text: String
    let tone: PillTone
    let at: Date
}

@MainActor
final class OliBubbleCenter: ObservableObject {
    static let shared = OliBubbleCenter()
    private init() {}

    /// What Oli said recently (shown in « Du nouveau »).
    @Published private(set) var history: [OliSaid] = []
    @Published var current: OliSaid? = nil
    var currentButton: (String, @MainActor () -> Void)? = nil

    private var bubblePanel: NSPanel?
    private var hubPanel: NSPanel?
    private var hideWork: DispatchWorkItem?
    private var outsideMonitor: Any?
    private var localOutsideMonitor: Any?
    private var escMonitor: Any?

    var hubOpen: Bool { hubPanel != nil }
    var bubbleOpen: Bool { bubblePanel != nil }

    static let hubSize = CGSize(width: 380, height: 540)
    static let bubbleWidth: CGFloat = 270

    // MARK: Bubble

    func show(_ text: String, tone: PillTone, button: (String, @MainActor () -> Void)?, oliFrame: NSRect) {
        let said = OliSaid(text: text, tone: tone, at: Date())
        history.insert(said, at: 0)
        if history.count > 12 { history.removeLast(history.count - 12) }
        current = said
        currentButton = button
        guard !hubOpen else { return }   // the hub already shows « Du nouveau »

        let p = bubblePanel ?? makePanel()
        let host = NSHostingView(rootView: OliSpeechView(center: self))
        let size = host.fittingSize
        p.contentView = host
        p.setFrame(NSRect(origin: bubbleOrigin(size: size, oli: oliFrame), size: size), display: true)
        if bubblePanel == nil {
            p.alphaValue = 0
            p.orderFront(nil)
            NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.18; p.animator().alphaValue = 1 }
        }
        bubblePanel = p

        hideWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.hideBubble() }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + (button == nil ? 7 : 14), execute: w)
    }

    func hideBubble() {
        hideWork?.cancel()
        guard let p = bubblePanel else { return }
        bubblePanel = nil
        NSAnimationContext.runAnimationGroup({ ctx in ctx.duration = 0.18; p.animator().alphaValue = 0 },
                                             completionHandler: { p.close() })
    }

    // MARK: Hub

    func toggleHub(oliFrame: NSRect) {
        if hubOpen { closeHub() } else { openHub(oliFrame: oliFrame) }
    }

    func openHub(oliFrame: NSRect) {
        hideBubble()
        guard hubPanel == nil else { return }
        let p = makePanel()
        let host = NSHostingView(rootView: OliHubView(state: AppState.shared, center: self))
        p.contentView = host
        p.setFrame(NSRect(origin: hubOrigin(oli: oliFrame), size: Self.hubSize), display: true)
        p.alphaValue = 0
        p.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.2; p.animator().alphaValue = 1 }
        hubPanel = p
        SoundEngine.shared.play("peek")

        // A click anywhere else closes the hub.
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            Task { @MainActor in OliBubbleCenter.shared.closeHub() }
        }
        localOutsideMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
            MainActor.assumeIsolated {
                let c = OliBubbleCenter.shared
                // Oli's own panel toggles the hub itself (DesktopOliController.handleClick).
                if event.window !== c.hubPanel && !DesktopOliController.shared.owns(event.window) { c.closeHub() }
            }
            return event
        }
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { MainActor.assumeIsolated { OliBubbleCenter.shared.closeHub() }; return nil }
            return event
        }
    }

    func closeHub() {
        [outsideMonitor, localOutsideMonitor, escMonitor].compactMap { $0 }.forEach(NSEvent.removeMonitor)
        outsideMonitor = nil; localOutsideMonitor = nil; escMonitor = nil
        guard let p = hubPanel else { return }
        hubPanel = nil
        NSAnimationContext.runAnimationGroup({ ctx in ctx.duration = 0.15; p.animator().alphaValue = 0 },
                                             completionHandler: { p.close() })
    }

    func closeAll() {
        closeHub()
        hideBubble()
    }

    /// Keep the bubble glued to Oli while he moves.
    func follow(oliFrame: NSRect) {
        if let p = bubblePanel {
            p.setFrameOrigin(bubbleOrigin(size: p.frame.size, oli: oliFrame))
        }
    }

    // MARK: Geometry

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        p.becomesKeyOnlyIfNeeded = true
        return p
    }

    private func screen(for frame: NSRect) -> NSRect {
        (NSScreen.screens.first { $0.frame.contains(NSPoint(x: frame.midX, y: frame.midY)) } ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private func bubbleOrigin(size: CGSize, oli: NSRect) -> NSPoint {
        let vf = screen(for: oli)
        var x = oli.midX - size.width / 2
        // Above Oli's head (the body sits in the middle of its 120 pt panel), else below.
        var y = oli.midY + 30
        if y + size.height > vf.maxY - 8 { y = oli.midY - 30 - size.height }
        x = min(max(x, vf.minX + 8), vf.maxX - size.width - 8)
        y = min(max(y, vf.minY + 8), vf.maxY - size.height - 8)
        return NSPoint(x: x, y: y)
    }

    private func hubOrigin(oli: NSRect) -> NSPoint {
        let vf = screen(for: oli)
        let s = Self.hubSize
        let onRight = oli.midX > vf.midX
        var x = onRight ? oli.midX - 40 - s.width : oli.midX + 40
        var y = oli.midY - s.height / 2
        x = min(max(x, vf.minX + 8), vf.maxX - s.width - 8)
        y = min(max(y, vf.minY + 8), vf.maxY - s.height - 8)
        return NSPoint(x: x, y: y)
    }
}

// MARK: - Bubble view

struct OliSpeechView: View {
    @ObservedObject var center: OliBubbleCenter

    var body: some View {
        if let said = center.current {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 7) {
                    Circle().fill(Color(hex: said.tone == .neutral ? "#FF5B37" : said.tone.hex)).frame(width: 7, height: 7).padding(.top, 5)
                    Text(said.text)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(Color(hex: "#F5F6F8"))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let b = center.currentButton {
                    Button {
                        b.1()
                        center.hideBubble()
                    } label: {
                        Text(b.0).font(.system(size: 11.5, weight: .semibold))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(Color(hex: "#FF5B37")))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .frame(width: OliBubbleCenter.bubbleWidth, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: "#0E0F11")))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.08)))
            .contentShape(Rectangle())
            .onTapGesture { DesktopOliController.shared.openHub() }
            .environment(\.colorScheme, .dark)
        }
    }
}

// MARK: - Hub view

struct OliHubView: View {
    @ObservedObject var state: AppState
    @ObservedObject var center: OliBubbleCenter
    @ObservedObject private var layout = HomeLayoutStore.shared
    @ObservedObject private var oneClick = OneClickConnect.shared
    @State private var motion = DesktopOliMotion.current
    @State private var routinesVersion = 0
    @State private var connVersion = 0

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        let name = resolveUserFirstName().map { " \($0)" } ?? ""
        return (h < 5 || h >= 18 ? "Bonsoir" : "Bonjour") + name
    }

    /// Alerts on the tiles right now, then what Oli said recently.
    private var news: [(id: String, text: String, tone: PillTone, when: String?)] {
        var out: [(String, String, PillTone, String?)] = []
        for t in layout.tiles {
            if let c = t.kind.connection, !c.isConnected { continue }
            let d = t.kind.data(state)
            if d.tone == .alert || d.tone == .warn { out.append((t.id, "\(t.kind.title) : \(d.detail)", d.tone, nil)) }
        }
        let recent = center.history.filter { Date().timeIntervalSince($0.at) < 86400 }.prefix(4)
        for s in recent where !out.contains(where: { $0.1 == s.text }) {
            out.append((s.id.uuidString, s.text, s.tone, s.at.formatted(.dateTime.hour().minute().locale(Locale(identifier: "fr_FR")))))
        }
        return Array(out.prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.06))
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section("Du nouveau") {
                        let items = news
                        if items.isEmpty {
                            Text("Rien de neuf, tout roule.").font(.system(size: 11.5)).foregroundColor(Color(hex: "#8E939C"))
                        }
                        ForEach(items, id: \.id) { n in
                            HStack(alignment: .top, spacing: 7) {
                                Circle().fill(Color(hex: n.tone == .neutral ? "#6B7079" : n.tone.hex)).frame(width: 6, height: 6).padding(.top, 5)
                                Text(n.text).font(.system(size: 11.5)).foregroundColor(Color(hex: "#D5D8DD"))
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                if let w = n.when { Text(w).font(.system(size: 10)).foregroundColor(Color(hex: "#6B7079")) }
                            }
                        }
                    }

                    if !layout.visibleTiles.isEmpty {
                        section("Accueil") {
                            HomeBentoView(state: state, columns: 2, tileHeight: 54, spacing: 6, large: true)
                        }
                    }

                    section("En un clic") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                            ForEach(OliAction.allCases) { a in
                                Button { a.run(); if a != .refreshAll && a != .checkSites { center.closeHub() } } label: {
                                    VStack(spacing: 5) {
                                        Image(systemName: a.icon).font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(Color(hex: a.color))
                                            .frame(width: 32, height: 32)
                                            .background(Circle().fill(Color(hex: a.color).opacity(0.15)))
                                        Text(a.title).font(.system(size: 9.5, weight: .medium))
                                            .foregroundColor(Color(hex: "#C5C8CD"))
                                            .lineLimit(2).multilineTextAlignment(.center)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 62)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    section("Routines") {
                        ForEach(OliRoutine.allCases) { r in
                            HStack(spacing: 8) {
                                Image(systemName: r.icon).font(.system(size: 11)).foregroundColor(Color(hex: "#3B9EFF")).frame(width: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(r.title).font(.system(size: 11.5, weight: .semibold)).foregroundColor(Color(hex: "#E4E6EA"))
                                    Text(r.detail).font(.system(size: 10)).foregroundColor(Color(hex: "#8E939C")).lineLimit(2)
                                }
                                Spacer(minLength: 4)
                                Toggle("", isOn: Binding(get: { r.isOn }, set: { r.isOn = $0; routinesVersion += 1 }))
                                    .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                            }
                        }
                        .id(routinesVersion)
                    }

                    let missing = ConnectionKind.allCases.filter { !$0.isConnected && $0 != .phone }
                    if !missing.isEmpty {
                        section("À brancher") {
                            ForEach(missing) { k in
                                HStack(spacing: 8) {
                                    Image(systemName: k.icon).font(.system(size: 10, weight: .semibold)).foregroundColor(.white)
                                        .frame(width: 22, height: 22)
                                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: k.color)))
                                    Text(k.title).font(.system(size: 11.5, weight: .semibold)).foregroundColor(Color(hex: "#E4E6EA"))
                                    Spacer()
                                    OneClickConnectButton(kind: k, compact: true)
                                }
                            }
                        }
                        .id(connVersion)
                    }
                }
                .padding(14)
            }
            Divider().overlay(Color.white.opacity(0.06))
            footer
        }
        .frame(width: OliBubbleCenter.hubSize.width, height: OliBubbleCenter.hubSize.height)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(hex: "#0E0F11")))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.08)))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .environment(\.colorScheme, .dark)
        .onReceive(NotificationCenter.default.publisher(for: .oliConnectionsChanged)) { _ in connVersion += 1 }
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(greeting).font(.system(size: 14, weight: .bold)).foregroundColor(Color(hex: "#F5F6F8"))
                Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_FR"))))
                    .font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C"))
            }
            Spacer()
            iconButton(OliAction.tidyDesktop.icon, help: "Oli range ton bureau (rien n’est supprimé)") {
                center.closeHub()
                OliAction.tidyDesktop.run()
            }
            iconButton("slider.horizontal.3", help: "Personnaliser l’accueil") {
                center.closeHub()
                NotificationCenter.default.post(name: .openFullSettings, object: "home")
            }
            iconButton("xmark", help: "Fermer") { center.closeHub() }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            ForEach(DesktopOliMotion.allCases) { m in
                Button {
                    motion = m
                    DesktopOliMotion.current = m
                } label: {
                    Label(m.label, systemImage: m.icon)
                        .font(.system(size: 10.5, weight: .semibold))
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Capsule().fill(motion == m ? Color(hex: "#FF5B37") : Color.white.opacity(0.06)))
                        .foregroundColor(motion == m ? .white : Color(hex: "#C5C8CD"))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button {
                center.closeHub()
                DesktopOliController.shared.flyHome()
            } label: {
                Image(systemName: "arrow.up.to.line").font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#C5C8CD"))
            }
            .buttonStyle(.plain)
            .help("Ramener Oli dans l’encoche")
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
    }

    @ViewBuilder
    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased()).font(.system(size: 9.5, weight: .bold)).kerning(0.6)
                .foregroundColor(Color(hex: "#6B7079"))
            content()
        }
    }

    private func iconButton(_ name: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(hex: "#C5C8CD"))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
