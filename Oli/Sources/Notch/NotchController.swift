import AppKit
import SwiftUI
import Combine

// MARK: - L'encoche
// One borderless panel glued to the top of the screen. Folded, it is the size of the notch
// (plus two « ears » when Oli has something to say); unfolded, a 700 × 420 panel hanging from it.
// Hover unfolds, leaving folds (unless typing in the terminal / chat or an approval is waiting).

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
        return NotchGeometry(screen: screen, notchWidth: 180, notchHeight: max(bar, 24), hasNotch: false)
    }
}

enum NotchLayout {
    static let size = CGSize(width: 700, height: 420)
    static let ear: CGFloat = 220
}

@MainActor
final class NotchController: NSObject {
    static let shared = NotchController()

    private var panel: NotchPanel!
    private var geo = NotchGeometry.current()
    private var bag: Set<AnyCancellable> = []
    private var hoverWork: DispatchWorkItem?
    private var foldWork: DispatchWorkItem?
    private var keyMonitor: Any?
    private var foldedAt = Date.distantPast
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

        let root = NotchRootView(geo: geo).environmentObject(model)
        let host = HoverHostingView(rootView: AnyView(root))
        host.onHover = { [weak self] inside in self?.hover(inside) }
        panel.contentView = host
        layout(animated: false)
        panel.orderFrontRegardless()

        model.$openRequest.compactMap { $0 }.sink { [weak self] s in self?.unfold(on: s) }.store(in: &bag)
        model.$flash.sink { [weak self] _ in self?.layout(animated: false) }.store(in: &bag)
        model.$expanded.sink { [weak self] _ in DispatchQueue.main.async { self?.layout(animated: false) } }.store(in: &bag)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { NotchController.shared.screenChanged() }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, self.model.expanded, e.keyCode == 53, self.model.section != .terminal else { return e }
            self.fold(); return nil
        }
    }

    private func screenChanged() {
        geo = NotchGeometry.current()
        (panel.contentView as? HoverHostingView)?.rootView = AnyView(NotchRootView(geo: geo).environmentObject(model))
        layout(animated: false)
    }

    // MARK: Frames

    /// Folded: notch (+ ears when Oli talks). Unfolded: the big panel. Always top-centred.
    private func layout(animated: Bool) {
        let sf = geo.screen.frame
        let size: CGSize
        if model.expanded {
            size = NotchLayout.size
        } else {
            let ears: CGFloat = model.flash != nil ? NotchLayout.ear * 2 : 24
            size = CGSize(width: geo.notchWidth + ears, height: geo.notchHeight + 6)
        }
        let frame = CGRect(x: sf.midX - size.width / 2, y: sf.maxY - size.height, width: size.width, height: size.height)
        panel.setFrame(frame, display: true, animate: animated)
    }

    // MARK: Fold / unfold

    func toggle(_ section: Section? = nil) {
        if model.expanded && (section == nil || section == model.section) { fold() } else { unfold(on: section) }
    }

    func unfold(on section: Section? = nil) {
        foldWork?.cancel()
        if let section { model.section = model.sections.contains(section) ? section : .home }
        model.openRequest = nil
        guard !model.expanded else { focusIfNeeded(); return }
        BriefingDesk.checkDue()
        model.expanded = true
        layout(animated: false)
        Chimes.shared.play(.unfold)
        focusIfNeeded()
    }

    func fold() {
        guard model.expanded else { return }
        model.holdOpen = false
        model.expanded = false
        foldedAt = Date()
        panel.resignKey()
        Chimes.shared.play(.fold)
    }

    private func focusIfNeeded() {
        if model.section == .terminal || model.section == .chat {
            panel.makeKey()
            if model.section == .terminal { DispatchQueue.main.async { OliTerminal.shared.focus() } }
        }
    }

    /// Keyboard for the terminal / chat (called by those views).
    func makeKey() { panel.makeKey() }

    private func hover(_ inside: Bool) {
        if inside {
            foldWork?.cancel()
            guard !model.expanded, Date().timeIntervalSince(foldedAt) > 0.8 else { return }
            hoverWork?.cancel()
            let w = DispatchWorkItem { [weak self] in self?.unfold() }
            hoverWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: w)
        } else {
            hoverWork?.cancel()
            guard model.expanded, !model.holdOpen, model.approvals.isEmpty else { return }
            let w = DispatchWorkItem { [weak self] in
                guard let self, !self.model.holdOpen, self.model.approvals.isEmpty else { return }
                self.fold()
            }
            foldWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: w)
        }
    }
}

/// Hosting view that reports the mouse entering / leaving the whole panel.
final class HoverHostingView: NSHostingView<AnyView> {
    var onHover: ((Bool) -> Void)?
    private var area: NSTrackingArea?

    required init(rootView: AnyView) { super.init(rootView: rootView) }
    @MainActor required dynamic init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let a = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(a)
        area = a
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
