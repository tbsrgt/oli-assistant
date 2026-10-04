import SwiftUI

// MARK: - Claude Code

struct ClaudeSection: View {
    @EnvironmentObject var model: OliModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.approvals) { a in ApprovalCard(approval: a) }

                if model.sessions.isEmpty {
                    if model.hooksInstalled {
                        EmptyNote(icon: "sparkles", text: "Aucune session en cours. Lance « claude » dans un terminal : je la suis d’ici.")
                    } else {
                        Card {
                            Text("Relie Claude Code à Oli").font(Typo.display(14)).foregroundStyle(Palette.cream)
                            Text("Oli suit tes sessions et te laisse accepter les autorisations depuis l’encoche. Il faut d’abord ajouter ses hooks à Claude Code (tu verras chaque changement avant de valider).")
                                .font(Typo.text(12)).foregroundStyle(Palette.sand).fixedSize(horizontal: false, vertical: true)
                            ActionButton(title: "Ouvrir les réglages Claude Code", icon: "slider.horizontal.3", tint: Palette.lilas) {
                                SettingsWindow.shared.show(tab: .claude)
                            }
                        }
                    }
                } else {
                    VStack(spacing: 2) {
                        ForEach(model.sessions) { s in
                            Row(color: color(s.phase), title: s.project, detail: s.activity,
                                action: { TerminalCommands.open(folder: s.cwd) }) {
                                Tag(text: s.terminal, tint: Palette.dust)
                                Text(s.updatedAt.formatted(.relative(presentation: .numeric, unitsStyle: .narrow).locale(Locale(identifier: "fr_FR"))))
                                    .font(Typo.text(10.5)).foregroundStyle(Palette.dust)
                            }
                        }
                    }
                }
            }
        }
    }

    private func color(_ p: ClaudeSession.Phase) -> Color {
        switch p {
        case .working: return Palette.lilas
        case .waiting: return Palette.beurre
        case .done: return Palette.menthe
        case .idle: return Palette.dust
        }
    }
}

struct ApprovalCard: View {
    let approval: Approval
    @State private var showDetail = false

    var body: some View {
        Card(tint: Palette.beurre) {
            HStack(spacing: 8) {
                Image(systemName: "hand.raised.fill").foregroundStyle(Palette.beurre)
                Text("\(approval.project) demande à utiliser \(approval.tool)")
                    .font(Typo.text(12.5, .bold)).foregroundStyle(Palette.cream).lineLimit(1)
                Spacer()
                Text(approval.createdAt.formatted(date: .omitted, time: .shortened)).font(Typo.text(10.5)).foregroundStyle(Palette.sand)
            }
            Text(approval.detail)
                .font(Typo.mono(11)).foregroundStyle(Palette.cream)
                .lineLimit(showDetail ? 14 : 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.35)))
                .textSelection(.enabled)
                .onTapGesture { showDetail.toggle() }
            HStack(spacing: 8) {
                ActionButton(title: "Autoriser", icon: "checkmark", tint: Palette.menthe, filled: true) {
                    ClaudeSessions.shared.answer(approval, allow: true)
                }
                ActionButton(title: "Refuser", icon: "xmark", tint: Palette.alerte) {
                    ClaudeSessions.shared.answer(approval, allow: false)
                }
                ActionButton(title: "Répondre dans le terminal", tint: Palette.sand) {
                    ClaudeSessions.shared.answer(approval, allow: nil)
                }
            }
        }
    }
}
