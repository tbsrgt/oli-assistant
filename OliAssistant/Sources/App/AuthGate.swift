import AppKit
import LocalAuthentication

// MARK: - Déverrouillage d'Oli (Touch ID / mot de passe du Mac)
// The first time Oli unfolds in a session, macOS asks for Touch ID (or the Mac password when
// there is no sensor). Unlocked until the screen locks or the Mac sleeps.

@MainActor
final class AuthGate {
    static let shared = AuthGate()
    private(set) var unlocked = false
    private var asking = false
    private var waiting: [() -> Void] = []

    private init() {
        let relock: (Notification) -> Void = { _ in MainActor.assumeIsolated { AuthGate.shared.unlocked = false } }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main, using: relock)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main, using: relock)
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main, using: relock)
    }

    /// Runs `action` right away when unlocked; otherwise asks once and runs it on success.
    func whenUnlocked(_ action: @escaping () -> Void) {
        // « authGateOff » (Réglages) turns the lock off.
        if unlocked || UserDefaults.standard.bool(forKey: "authGateOff") { action(); return }
        waiting.append(action)
        guard !asking else { return }
        asking = true
        let ctx = LAContext()
        ctx.localizedCancelTitle = "Plus tard"
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            // No password / sensor available at all: let Oli open.
            finish(true); return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "déverrouiller Oli") { ok, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { AuthGate.shared.finish(ok) } }
        }
    }

    private func finish(_ ok: Bool) {
        asking = false
        unlocked = ok
        let actions = waiting
        waiting = []
        if ok {
            actions.forEach { $0() }
            SoundEngine.shared.play("approve")
        } else {
            SoundEngine.shared.play("annoyed")
        }
    }
}
