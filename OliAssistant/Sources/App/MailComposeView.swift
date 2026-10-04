import SwiftUI
import AppKit

// MARK: - Envoyer un fichier par mail depuis l'encoche
// To / subject / message, the dropped file attached (a folder is zipped), sent from the user's
// own mailbox when they click « Envoyer ». Recent recipients are one click away.

struct MailComposeView: View {
    @ObservedObject var state: AppState
    @State private var to = ""
    @State private var subject = ""
    @State private var message = ""
    @State private var sending = false
    @State private var status: (text: String, ok: Bool)? = nil
    @State private var recents: [String] = UserDefaults.standard.stringArray(forKey: "mailRecents") ?? []

    private var file: DroppedFile? { state.droppedFile }
    private var account: EmailAccount? { EmailSender.account }
    private var recipients: [String] {
        to.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == " " }).map(String.init).filter { $0.contains("@") }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            CardBackground(wash: nil)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: "paperplane.fill").font(.system(size: 11)).foregroundColor(Color(hex: "#FF8A52"))
                    Text("Envoyer par mail").font(.system(size: 13, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8"))
                    if let f = file {
                        Text(f.name).font(.system(size: 11)).foregroundColor(Color(hex: "#9398A1"))
                            .lineLimit(1).truncationMode(.middle)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(Color.white.opacity(0.07)))
                    }
                    Spacer()
                }
                if account == nil {
                    HStack(spacing: 8) {
                        Text("Connecte ton email pour qu’Oli l’envoie directement.")
                            .font(.system(size: 11.5)).foregroundColor(Color(hex: "#FFD65C"))
                        Spacer()
                        Button("Connecter") { NotificationCenter.default.post(name: .openFullSettings, object: "integrations") }
                            .buttonStyle(.plain).font(.system(size: 11.5, weight: .semibold)).foregroundColor(Color(hex: "#FF8A52"))
                        Button("Ouvrir dans Mail") {
                            if let u = file?.url { MailShare.compose(u) }
                            NotificationCenter.default.post(name: .islandCollapse, object: nil)
                        }
                        .buttonStyle(.plain).font(.system(size: 11.5)).foregroundColor(Color(hex: "#9398A1"))
                    }
                }
                field("À", text: $to, prompt: "client@exemple.fr")
                if to.isEmpty, !recents.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(recents.prefix(4), id: \.self) { r in
                            Button(r) { to = r }.buttonStyle(.plain)
                                .font(.system(size: 10.5)).foregroundColor(Color(hex: "#C5C8CD"))
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Capsule().fill(Color.white.opacity(0.07)))
                        }
                    }
                }
                field("Objet", text: $subject, prompt: "")
                TextEditor(text: $message)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(minHeight: 46)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
                HStack(spacing: 10) {
                    PrimaryButton(sending ? "Envoi…" : "Envoyer") { send() }
                        .disabled(sending || account == nil || recipients.isEmpty)
                        .opacity(account == nil || recipients.isEmpty ? 0.5 : 1)
                    SecondaryButton("Annuler") { NotificationCenter.default.post(name: .islandCollapse, object: nil) }
                    if let s = status {
                        Text(s.text).font(.system(size: 11))
                            .foregroundColor(Color(hex: s.ok ? "#22C55E" : "#F4505E")).lineLimit(2)
                    }
                    Spacer()
                }
            }
            .padding(.leading, 98).padding(.trailing, 16).padding(.vertical, 8)
        }
        .onAppear {
            if subject.isEmpty { subject = file?.name ?? "" }
            if message.isEmpty {
                let sign = account?.name.isEmpty == false ? account!.name : "Oculot"
                message = "Bonjour,\n\nVoici le fichier en pièce jointe.\n\nBonne journée,\n\(sign)"
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 11.5, weight: .medium)).foregroundColor(Color(hex: "#8E939C")).frame(width: 38, alignment: .leading)
            TextField(prompt, text: text).textFieldStyle(.plain).font(.system(size: 12)).foregroundColor(Color(hex: "#F5F6F8"))
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
    }

    private func send() {
        guard let account, let file else { return }
        let rcpt = recipients
        sending = true; status = nil
        Task {
            do {
                let attachment = try await MailShare.attachmentFile(for: file.url)
                try await EmailSender.send(account, to: rcpt, subject: subject, body: message, attachment: attachment)
                sending = false
                status = ("Envoyé ✓", true)
                remember(rcpt)
                SoundEngine.shared.play("finish")
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                NotificationCenter.default.post(name: .islandCollapse, object: nil)
            } catch {
                sending = false
                status = (error.localizedDescription, false)
                SoundEngine.shared.play("error")
            }
        }
    }

    private func remember(_ list: [String]) {
        var r = list + recents.filter { !list.contains($0) }
        r = Array(r.prefix(8))
        recents = r
        UserDefaults.standard.set(r, forKey: "mailRecents")
    }
}
