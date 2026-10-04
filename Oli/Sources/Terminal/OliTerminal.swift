import SwiftUI
import AppKit
@preconcurrency import SwiftTerm

// MARK: - Terminal d'Oli
// Real login shells rendered by SwiftTerm, in tabs. Shells live for the whole app session: folding
// the notch only hides them. TERM_PROGRAM=Oli, so Claude Code started here shows up in « Claude Code ».

@MainActor
final class TerminalTab: NSObject, ObservableObject, Identifiable, LocalProcessTerminalViewDelegate {
    let id = UUID()
    let view: LocalProcessTerminalView
    @Published var title: String
    @Published var directory: String = "~"
    @Published var alive = false
    private let startDir: String
    private let firstCommand: String?

    init(folder: String? = nil, command: String? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        startDir = folder.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil } ?? home
        firstCommand = command
        title = URL(fileURLWithPath: startDir).lastPathComponent
        view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 560, height: 300))
        super.init()
        view.processDelegate = self
        view.font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
        view.nativeBackgroundColor = NSColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)
        view.nativeForegroundColor = NSColor(red: 0.96, green: 0.94, blue: 0.9, alpha: 1)
        view.caretColor = NSColor(red: 1.0, green: 0.36, blue: 0.22, alpha: 1)
        view.optionAsMetaKey = true
        directory = Self.pretty(startDir)
    }

    /// Starts the shell once the view has its real size (avoids zsh's stray « % » on resize).
    func startIfNeeded() {
        guard !alive else { return }
        let env = ProcessInfo.processInfo.environment
        let shell = env["SHELL"].flatMap { FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil } ?? "/bin/zsh"
        var vars = env
        vars["TERM"] = "xterm-256color"
        vars["COLORTERM"] = "truecolor"
        vars["TERM_PROGRAM"] = "Oli"
        vars["LANG"] = env["LANG"] ?? "fr_FR.UTF-8"
        view.startProcess(executable: shell, args: [], environment: vars.map { "\($0.key)=\($0.value)" },
                          execName: "-" + (shell as NSString).lastPathComponent, currentDirectory: startDir)
        alive = true
        if let firstCommand {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.view.send(txt: firstCommand + "\r") }
        }
    }

    static func pretty(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    // LocalProcessTerminalViewDelegate
    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        Task { @MainActor in if !title.isEmpty { self.title = title } }
    }
    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        Task { @MainActor in
            guard let d = directory.flatMap({ URL(string: $0)?.path ?? $0 }) else { return }
            self.directory = Self.pretty(d)
            self.title = URL(fileURLWithPath: d).lastPathComponent
        }
    }
    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor in
            self.alive = false
            OliTerminal.shared.close(self)
        }
    }
}

@MainActor
final class OliTerminal: ObservableObject {
    static let shared = OliTerminal()
    @Published var tabs: [TerminalTab] = []
    @Published var current: UUID? = nil

    var active: TerminalTab? { tabs.first { $0.id == current } ?? tabs.first }
    var directory: String { active?.directory ?? "~" }

    @discardableResult
    func newTab(folder: String? = nil, command: String? = nil) -> TerminalTab {
        let t = TerminalTab(folder: folder, command: command)
        tabs.append(t)
        current = t.id
        return t
    }

    func ensureOne() { if tabs.isEmpty { newTab() } }

    func close(_ tab: TerminalTab) {
        tabs.removeAll { $0.id == tab.id }
        if current == tab.id { current = tabs.last?.id }
    }

    func focus() {
        guard let v = active?.view else { return }
        v.window?.makeFirstResponder(v)
    }
}

/// Opening a client repo from anywhere in Oli.
@MainActor
enum TerminalCommands {
    static func open(folder: String, runClaude: Bool = false) {
        guard !folder.isEmpty else { return }
        OliTerminal.shared.newTab(folder: folder, command: runClaude ? "claude" : nil)
        OliModel.shared.open(.terminal)
    }
}

// MARK: Views

struct TerminalHost: NSViewRepresentable {
    @ObservedObject var tab: TerminalTab

    func makeNSView(context: Context) -> NSView { let v = NSView(); attach(v); return v }
    func updateNSView(_ v: NSView, context: Context) { if tab.view.superview !== v { attach(v) } }

    private func attach(_ container: NSView) {
        let tv = tab.view
        tv.removeFromSuperview()
        tv.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tv)
        NSLayoutConstraint.activate([
            tv.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            tv.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -2),
            tv.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            tv.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
        ])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            tab.startIfNeeded()
            tv.window?.makeFirstResponder(tv)
        }
    }
}

struct TerminalSection: View {
    @ObservedObject private var term = OliTerminal.shared
    @EnvironmentObject var model: OliModel

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(term.tabs) { t in
                    TabChip(tab: t, on: t.id == term.active?.id) { term.current = t.id; term.focus() } close: { t.view.send(txt: "exit\r") }
                }
                Button { term.newTab(); NotchController.shared.makeKey() } label: {
                    Image(systemName: "plus").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.sand)
                        .frame(width: 22, height: 22).background(Circle().fill(Palette.card))
                }
                .buttonStyle(.plain).help("Nouvel onglet")
                Spacer()
            }
            if let tab = term.active {
                TerminalHost(tab: tab)
                    .id(tab.id)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: tab.view.nativeBackgroundColor)))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.hair, lineWidth: 1))
            }
        }
        .onAppear {
            term.ensureOne()
            model.holdOpen = true
            NotchController.shared.makeKey()
        }
        .onDisappear { model.holdOpen = false }
    }
}

private struct TabChip: View {
    @ObservedObject var tab: TerminalTab
    let on: Bool
    let select: () -> Void
    let close: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 5) {
            Text(tab.title).font(Typo.mono(10.5, on ? .bold : .regular)).lineLimit(1)
            if hover {
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }.buttonStyle(.plain)
            }
        }
        .foregroundStyle(on ? Palette.cream : Palette.sand)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Capsule().fill(on ? Palette.raised : Palette.card))
        .onHover { hover = $0 }
        .onTapGesture(perform: select)
    }
}
