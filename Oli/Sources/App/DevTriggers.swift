#if DEBUG
import Foundation

// MARK: - Déclencheurs de développement (build Debug uniquement)
// scripts/oli-dev.sh <commande> : open [section] · fold · panne · briefing [friday] · flash <texte>

@MainActor
enum DevTriggers {
    static func install() {
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("studio.oculot.oli.dev"),
                                                            object: nil, queue: .main) { note in
            let parts = (note.object as? String ?? "").split(separator: " ", maxSplits: 1).map(String.init)
            MainActor.assumeIsolated { run(parts.first ?? "", parts.count > 1 ? parts[1] : "") }
        }
    }

    static func run(_ cmd: String, _ arg: String) {
        switch cmd {
        case "open": NotchController.shared.unfold(on: Section(rawValue: arg) ?? .home)
        case "fold": NotchController.shared.fold()
        case "panne":
            SitesWatcher.shared.raiseAlarm("Site de démo est en panne · HTTP 503")
            DispatchQueue.main.asyncAfter(deadline: .now() + 25) { OliModel.shared.alarm = OliModel.shared.sites.contains { $0.status == .down } }
        case "briefing": BriefingDesk.show(arg == "friday" ? .friday : .morning); NotchController.shared.unfold(on: .home)
        case "allow": if let a = OliModel.shared.approvals.first { ClaudeSessions.shared.answer(a, allow: true) }
        case "deny": if let a = OliModel.shared.approvals.first { ClaudeSessions.shared.answer(a, allow: false) }
        case "flash": OliModel.shared.say(arg.isEmpty ? "Message de test" : arg, tint: Palette.lilas)
        default: break
        }
    }
}
#endif
