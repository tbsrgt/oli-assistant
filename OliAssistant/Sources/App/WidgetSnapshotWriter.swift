import Foundation
import Combine
import WidgetKit

// MARK: - Widget d'Oli : l'app publie un instantané
// Observe sites, espace client et agenda dans AppState, écrit l'instantané JSON partagé avec le
// widget (OliWidgetStore) quand le contenu change, puis demande à WidgetKit de redessiner.
// Rien ne tourne en continu : uniquement quand un poller publie de nouvelles données.

@MainActor
final class WidgetSnapshotWriter {
    static let shared = WidgetSnapshotWriter()

    private var subscription: AnyCancellable?
    private var lastWritten: OliWidgetSnapshot?
    /// Même sans changement, on rafraîchit l'horodatage de temps en temps pour que le widget
    /// sache qu'Oli tourne toujours (il affiche « en pause » au-delà d'une heure).
    private let heartbeat: TimeInterval = 15 * 60

    func start() {
        guard subscription == nil else { return }
        lastWritten = OliWidgetStore.read()
        let app = AppState.shared
        subscription = Publishers.CombineLatest4(app.$siteChecks, app.$espaceClients, app.$agendaEvents, app.$sitesLastSync)
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] sites, clients, events, _ in
                MainActor.assumeIsolated {
                    self?.publish(sites: sites, clients: clients, events: events)
                }
            }
    }

    private func publish(sites: [SiteCheck], clients: [EspaceClient], events: [AgendaEvent]) {
        let snap = Self.makeSnapshot(sites: sites, clients: clients, events: events, now: Date())
        if let last = lastWritten, last.sameContent(as: snap),
           snap.generatedAt.timeIntervalSince(last.generatedAt) < heartbeat {
            return
        }
        do {
            try OliWidgetStore.write(snap)
            lastWritten = snap
            // Le contenu a bougé (ou le battement de cœur est dû) : le widget se redessine.
            WidgetCenter.shared.reloadTimelines(ofKind: OliWidgetStore.kind)
        } catch {
            appendAppLog("oli.log", "widget: écriture de l'instantané impossible: \(error.localizedDescription)")
        }
    }

    static func makeSnapshot(sites: [SiteCheck], clients: [EspaceClient], events: [AgendaEvent], now: Date) -> OliWidgetSnapshot {
        let siteRows = sites
            .sorted { ($0.status == .down ? 0 : 1, $0.name) < ($1.status == .down ? 0 : 1, $1.name) }
            .map { OliWidgetSnapshot.Site(name: $0.name.isEmpty ? $0.shortHost : $0.name, status: $0.status.rawValue) }

        // Prochain projet : le chantier en cours dont l'échéance est la plus proche (sans date en dernier).
        let active = clients.filter { !$0.isDone }
        let next = active.min { a, b in
            switch (a.daysLeft, b.daysLeft) {
            case let (x?, y?): return x < y
            case (_?, nil):    return true
            case (nil, _?):    return false
            case (nil, nil):   return (a.lastActivityAt ?? a.createdAt) > (b.lastActivityAt ?? b.createdAt)
            }
        }
        let project = next.map {
            OliWidgetSnapshot.Project(name: $0.name, dueDate: dueDate(from: $0.dueAt), step: $0.stepLabel)
        }

        let upcoming = events
            .filter { $0.end > now }
            .sorted { $0.start < $1.start }
            .prefix(6)
            .map { OliWidgetSnapshot.Event(title: $0.title, start: $0.start, end: $0.end, isAllDay: $0.isAllDay) }

        return OliWidgetSnapshot(generatedAt: now, sites: siteRows, nextProject: project, events: Array(upcoming))
    }

    /// "2026-10-12" → minuit local du 12 octobre.
    private static func dueDate(from s: String?) -> Date? {
        guard let s, s.count == 10 else { return nil }
        let p = s.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }
}
