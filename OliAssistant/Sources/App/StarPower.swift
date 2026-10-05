import SwiftUI
import Combine

// MARK: - Mode étoile (comme l'étoile de Mario)
// Un nouveau rendez-vous arrive dans l'agenda, ou un nouveau mail d'Oculot dans une boîte : Oli est
// content, se dandine et ses couleurs défilent en arc-en-ciel pendant quelques secondes, dans
// l'encoche comme sur le bureau. Le premier chargement (au lancement, au changement de boîte) ne
// compte pas : seulement ce qui arrive ensuite. En dehors de ces secondes, rien ne tourne (0 % CPU).

@MainActor
final class StarPower: ObservableObject {
    static let shared = StarPower()
    private init() {}

    @Published private(set) var until: Date = .distantPast
    var isActive: Bool { until > Date() }

    private var knownEvents: Set<String>? = nil
    private var cancellables: Set<AnyCancellable> = []

    static let duration: TimeInterval = 7

    func start() {
        AppState.shared.$agendaEvents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] events in self?.agendaChanged(events) }
            .store(in: &cancellables)
    }

    /// Oli goes star for a few seconds; `reason` is said in a bubble when he is on the desktop.
    func fire(_ reason: String, speak: Bool = true) {
        let wasActive = isActive
        until = Date().addingTimeInterval(Self.duration)
        objectWillChange.send()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration + 0.1) { [weak self] in self?.objectWillChange.send() }
        guard !wasActive else { return }
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
        NotificationCenter.default.post(name: .hookReveal, object: nil)   // the notch peeks out so you see it
        SoundEngine.shared.play("approve")
        if speak { DesktopOliController.shared.say(reason, tone: .ok) }
        appendAppLog("oli.log", "Mode étoile : \(reason)")
    }

    // MARK: Triggers

    /// New appointment in the iCal feed (any agenda), still to come.
    private func agendaChanged(_ events: [AgendaEvent]) {
        let ids = Set(events.map(\.uid))
        guard let known = knownEvents else {
            if !events.isEmpty || AppState.shared.agendaLastSync != nil { knownEvents = ids }
            return
        }
        let fresh = events.filter { !known.contains($0.uid) && $0.end > Date() }
        knownEvents = known.union(ids)
        if let e = fresh.first { fire("Nouveau rendez-vous : \(e.title) ✨") }
    }

    /// Called by MailCenter after a refresh of the same mailbox: mails not seen before.
    func newMails(_ mails: [OliMail]) {
        if let m = mails.first(where: Self.isFromOculot) { fire("Nouveau mail d’Oculot : \(m.subject) ✨") }
    }

    /// Called by OculotAgenda: appointments that appeared since the last read.
    func newAppointments(_ rdvs: [OculotRdv], me: String?) {
        if let r = rdvs.first(where: { $0.creePar != (me ?? "") }) { fire("Nouveau rendez-vous : \(r.titre) ✨") }
    }

    nonisolated static func isFromOculot(_ m: OliMail) -> Bool {
        m.fromAddress.lowercased().contains("oculot") || m.fromName.lowercased().contains("oculot")
    }
}

// MARK: - L'effet

/// Rainbow colours, a little dance and a coloured glow while the star lasts.
struct StarPowerEffect: ViewModifier {
    @ObservedObject private var star = StarPower.shared

    func body(content: Content) -> some View {
        let active = star.isActive
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !active)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let left = star.until.timeIntervalSince(tl.date)
            // Fade in and out over half a second, so it starts and ends softly.
            let k = active ? min(1, max(0, left / 0.5), 1) : 0
            let hue = Angle.degrees((t * 720).truncatingRemainder(dividingBy: 360) * k)
            content
                .hueRotation(hue)
                .saturation(1 + 0.4 * k)
                .shadow(color: Color(hue: (t * 2).truncatingRemainder(dividingBy: 1), saturation: 1, brightness: 1).opacity(0.85 * k),
                        radius: 10 * k)
                .rotationEffect(.degrees(sin(t * 18) * 9 * k))
                .scaleEffect(1 + 0.07 * k * abs(sin(t * 9)))
                .offset(y: -3 * k * abs(sin(t * 9)))
        }
    }
}

extension View {
    func starPower() -> some View { modifier(StarPowerEffect()) }
}
