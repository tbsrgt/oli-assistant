import AppKit
import SwiftUI
import Combine

// MARK: - L'encoche
// A transparent panel, always at its largest size, glued to the top of the screen. Inside it, the
// black island morphs from the notch (folded: notch + two ears with Oli and the mini Olis) to the
// unfolded island (640 pt wide). Transparent pixels let clicks through; only the island reacts to
// the mouse.

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Notch measurements of the screen Oli lives on.
struct NotchGeometry {
    let screen: NSScreen
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let hasNotch: Bool

    static func current() -> NotchGeometry {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        let top = screen.safeAreaInsets.top
        if top > 0, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            return NotchGeometry(screen: screen, notchWidth: screen.frame.width - l.width - r.width,
                                 notchHeight: top, hasNotch: true)
        }
        let bar = screen.frame.maxY - screen.visibleFrame.maxY
        return NotchGeometry(screen: screen, notchWidth: 190, notchHeight: max(bar, 24), hasNotch: false)
    }
}

enum Island {
    static let width: CGFloat = 640
    static let ear: CGFloat = 14            // concave flare where the island meets the screen edge
    static let foldedEars: CGFloat = 160    // folded: notch + 80 pt on each side
    static let flashEars: CGFloat = 360     // folded with a message
    static let panel = CGSize(width: 760, height: 420)

    @MainActor
    static func size(_ m: OliModel, _ g: NotchGeometry) -> CGSize {
        guard m.expanded else {
            return CGSize(width: g.notchWidth + (m.flash != nil ? flashEars : foldedEars), height: g.notchHeight)
        }
        switch m.tab {
        case .overview: return CGSize(width: width, height: m.section == .claude && !m.approvals.isEmpty ? 206 : 172)
        case .full, .terminal: return CGSize(width: width, height: 392)
        case .chat: return CGSize(width: width, height: 330)
        }
    }
}

@MainActor
final class NotchController: NSObject {
    static let shared = NotchController()

    private var panel: NotchPanel!
    private var host: HoverHostingView!
    private(set) var geo = NotchGeometry.current()
    private var bag: Set<AnyCancellable> = []
    private var hoverWork: DispatchWorkItem?
    private var foldWork: DispatchWorkItem?
    private var foldedAt = Date.distantPast
    /// The mouse has been over the unfolded island since it opened (hover-out folds only then).
    private var mouseVisited = false
    private var model: OliModel { .shared }

    func start() {
        panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = true

        host = HoverHostingView(rootView: AnyView(NotchRootView(geo: geo).environmentObject(model)))
        host.onHover = { [weak self] inside in self?.hover(inside) }
        panel.contentView = host
        placePanel()
        panel.orderFrontRegardless()

        model.$openRequest.compactMap { $0 }.sink { [weak self] s in self?.unfold(on: s) }.store(in: &bag)
        Publishers.MergeMany(model.$expanded.map { _ in () }.eraseToAnyPublisher(),
                             model.$tab.map { _ in () }.eraseToAnyPublisher(),
                             model.$section.map { _ in () }.eraseToAnyPublisher(),
                             model.$approvals.map { _ in () }.eraseToAnyPublisher(),
                             model.$flash.map { _ in () }.eraseToAnyPublisher())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.updateHotRect() }
            .store(in: &bag)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { NotchController.shared.screenChanged() }
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, self.model.expanded, e.keyCode == 53, self.model.tab != .terminal else { return e }
            if self.model.tab == .full || self.model.tab == .chat { self.model.tab = .overview } else { self.fold() }
            return nil
        }
    }

    private func screenChanged() {
        geo = NotchGeometry.current()
        host.rootView = AnyView(NotchRootView(geo: geo).environmentObject(model))
        placePanel()
    }

    private func placePanel() {
        let sf = geo.screen.frame
        let s = Island.panel
        panel.setFrame(CGRect(x: sf.midX - s.width / 2, y: sf.maxY - s.height, width: s.width, height: s.height), display: true)
        updateHotRect()
    }

    /// The part of the panel that is island right now (view coordinates, origin bottom-left).
    private func updateHotRect() {
        let s = Island.size(model, geo)
        let w = s.width + Island.ear * 2
        let y = host.isFlipped ? 0 : Island.panel.height - s.height
        host.hotRect = CGRect(x: (Island.panel.width - w) / 2, y: y, width: w, height: s.height)
    }

    // MARK: Fold / unfold

    func toggle(_ section: Section? = nil) {
        let showing = model.expanded && (section == nil || target(section!) == (model.tab, model.section))
        if showing { fold() } else { unfold(on: section) }
    }

    private func target(_ s: Section) -> (IslandTab, Section) {
        switch s {
        case .terminal: return (.terminal, model.section)
        case .chat: return (.chat, model.section)
        default: return (.overview, s)
        }
    }

    func unfold(on section: Section? = nil, byHover: Bool = false) {
        foldWork?.cancel()
        if !model.expanded { mouseVisited = byHover }
        if !byHover && !mouseVisited { scheduleIdleFold() }
        model.openRequest = nil
        if let section {
            let (tab, focus) = target(section)
            model.tab = tab
            model.section = model.focusable.contains(focus) ? focus : .home
        }
        if !model.expanded {
            BriefingDesk.checkDue()
            withAnimation(Self.unfoldAnimation) { model.expanded = true }
            Chimes.shared.play(.unfold)
        }
        focusIfNeeded()
    }

    func fold() {
        guard model.expanded else { return }
        model.holdOpen = false
        foldedAt = Date()
        withAnimation(Self.foldAnimation) { model.expanded = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, !self.model.expanded else { return }
            self.model.tab = .overview
        }
        panel.resignKey()
        Chimes.shared.play(.fold)
    }

    /// Opened by Oli (alert, shortcut) and never visited: fold back after a while, except during an
    /// alarm, an approval or while typing.
    private func scheduleIdleFold() {
        let w = DispatchWorkItem { [weak self] in
            guard let self, !self.mouseVisited, !self.model.holdOpen, self.model.approvals.isEmpty, !self.model.panic else { return }
            self.fold()
        }
        foldWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: w)
    }

    static let unfoldAnimation = Animation.spring(response: 0.5, dampingFraction: 0.74)
    static let foldAnimation = Animation.timingCurve(0.45, 0, 0.2, 1, duration: 0.34)

    private func focusIfNeeded() {
        guard model.tab == .terminal || model.tab == .chat else { return }
        panel.makeKey()
        if model.tab == .terminal { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { OliTerminal.shared.focus() } }
    }

    /// Keyboard for the terminal / chat (called by those views).
    func makeKey() { panel.makeKey() }

    private func hover(_ inside: Bool) {
        if inside {
            foldWork?.cancel()
            if model.expanded { mouseVisited = true }
            guard !model.expanded, Date().timeIntervalSince(foldedAt) > 0.8 else { return }
            hoverWork?.cancel()
            let w = DispatchWorkItem { [weak self] in self?.unfold(byHover: true) }
            hoverWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: w)
        } else {
            hoverWork?.cancel()
            guard model.expanded, mouseVisited, !model.holdOpen, model.approvals.isEmpty else { return }
            let w = DispatchWorkItem { [weak self] in
                guard let self, !self.model.holdOpen, self.model.approvals.isEmpty else { return }
                self.fold()
            }
            foldWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: w)
        }
    }
}

/// Hosting view that tracks the mouse over the island only, and lets clicks elsewhere through.
final class HoverHostingView: NSHostingView<AnyView> {
    var onHover: ((Bool) -> Void)?
    var hotRect: CGRect = .zero { didSet { if hotRect != oldValue { updateTrackingAreas(); recheck() } } }
    private var area: NSTrackingArea?
    private var inside = false

    required init(rootView: AnyView) { super.init(rootView: rootView) }
    @MainActor required dynamic init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let a = NSTrackingArea(rect: hotRect, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(a)
        area = a
    }

    /// After a resize, the mouse may now be inside or outside without an enter / exit event.
    private func recheck() {
        guard let w = window else { return }
        let p = convert(w.mouseLocationOutsideOfEventStream, from: nil)
        let now = hotRect.contains(p)
        if now != inside { inside = now; onHover?(now) }
    }

    override func mouseEntered(with event: NSEvent) { inside = true; onHover?(true) }
    override func mouseExited(with event: NSEvent) { inside = false; onHover?(false) }
    override func hitTest(_ point: NSPoint) -> NSView? {
        hotRect.contains(convert(point, from: superview)) ? super.hitTest(point) : nil
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
