import SwiftUI
import AppKit
#if canImport(SwiftTerm) && !APPSTORE
@preconcurrency import SwiftTerm

// MARK: - Terminal dans l'encoche
// A real login shell (zsh, colors, Ctrl-keys, full-screen programs like Claude Code or vim)
// rendered by SwiftTerm. One shell lives for the whole app session: folding the island only hides
// the view, it never kills the process. TERM_PROGRAM=Oli so Claude Code sessions started here show
// up on the Claude Code pill like any other terminal.

@MainActor
final class OliTerminal: NSObject, ObservableObject, LocalProcessTerminalViewDelegate {
    static let shared = OliTerminal()

    let view: LocalProcessTerminalView
    private(set) var running = false
    @Published private(set) var title: String = "Terminal"
    @Published private(set) var directory: String = ""

    private override init() {
        view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 280))
        super.init()
        view.processDelegate = self
        view.font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
        view.nativeBackgroundColor = NSColor(red: 0.075, green: 0.078, blue: 0.09, alpha: 1)
        view.nativeForegroundColor = NSColor(red: 0.90, green: 0.91, blue: 0.93, alpha: 1)
        view.caretColor = NSColor(red: 1.0, green: 0.42, blue: 0.21, alpha: 1)   // Oli orange
        view.optionAsMetaKey = true
    }

    /// Starts the user's login shell in the home folder (once; again after `exit`).
    func startIfNeeded() {
        guard !running else { return }
        let shell = ProcessInfo.processInfo.environment["SHELL"].flatMap { FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil } ?? "/bin/zsh"
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["TERM_PROGRAM"] = "Oli"
        env["LANG"] = env["LANG"] ?? "fr_FR.UTF-8"
        env["LC_CTYPE"] = env["LC_CTYPE"] ?? "UTF-8"
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        env["HOME"] = home
        let list = env.map { "\($0.key)=\($0.value)" }
        let name = "-" + (shell as NSString).lastPathComponent    // leading dash = login shell
        view.startProcess(executable: shell, args: [], environment: list, execName: name, currentDirectory: home)
        running = true
    }

    /// Gives the keyboard to the terminal (the island panel must already be key).
    func focus() {
        view.window?.makeFirstResponder(view)
    }

    // MARK: LocalProcessTerminalViewDelegate

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        Task { @MainActor in OliTerminal.shared.title = title.isEmpty ? "Terminal" : title }
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        Task { @MainActor in
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let d = directory.flatMap { URL(string: $0)?.path ?? $0 } ?? ""
            OliTerminal.shared.directory = d.hasPrefix(home) ? "~" + d.dropFirst(home.count) : d
        }
    }

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor in
            OliTerminal.shared.running = false
            // `exit` in the shell: start a fresh one next time the terminal is shown.
            let term = OliTerminal.shared.view.getTerminal()
            term.feed(text: "\r\n[session terminée — rouvre le terminal pour un nouveau shell]\r\n")
        }
    }
}

/// Hosts the shared terminal view (re-parented, never recreated).
struct TerminalHostView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attach(to: container)
        return container
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        if OliTerminal.shared.view.superview !== nsView { attach(to: nsView) }
    }
    private func attach(to container: NSView) {
        let tv = OliTerminal.shared.view
        tv.removeFromSuperview()
        tv.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tv)
        NSLayoutConstraint.activate([
            tv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tv.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tv.topAnchor.constraint(equalTo: container.topAnchor),
            tv.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}

struct TerminalPanelView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var term = OliTerminal.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(hex: "#FF6B35"))
                Text(term.directory.isEmpty ? "Terminal" : term.directory)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(hex: "#C5C8CD"))
                    .lineLimit(1).truncationMode(.head)
                Spacer(minLength: 4)
                Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { state.view = .prompt } }) {
                    Label("Chat IA", systemImage: "sparkles")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(hex: "#8E939C"))
                }
                .buttonStyle(.plain)
                .help("Le chat d’Oli (briefing, questions sur Oculot)")
            }
            .padding(.horizontal, 6)

            TerminalHostView()
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.06), lineWidth: 1))
        }
        // The shell starts the first time the terminal is shown, once the view has its real size
        // (starting it hidden makes zsh draw a stray « % » when the window resizes).
        .onChange(of: state.view) { _, v in if v == .terminal { openSoon() } }
        .onAppear { if state.view == .terminal { openSoon() } }
        .padding(.top, 6)
        .padding(.leading, 64)
        .padding(.trailing, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func openSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            OliTerminal.shared.startIfNeeded()
            OliTerminal.shared.focus()
        }
    }
}
#else
struct TerminalPanelView: View {
    @ObservedObject var state: AppState
    var body: some View {
        Text("Terminal indisponible dans cette version.").font(.system(size: 12)).foregroundColor(.secondary)
    }
}
#endif
