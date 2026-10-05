import SwiftUI

// MARK: - Onglet ⚡ de l'encoche : construire ses automatisations
// En haut, une phrase à compléter : « Quand [déclencheur ▾] alors [action ▾] » + Ajouter.
// Dessous, les règles : interrupteur, Tester, supprimer. Sans règle, des idées en un clic.

struct AutomationsIslandView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var engine = OliRules.shared

    @State private var trigger: OliTrigger = .siteDown
    @State private var triggerParam = ""
    @State private var action: OliRuleAction = .bubble
    @State private var actionParam = ""
    @State private var flash: UUID? = nil

    private var draft: OliRule {
        OliRule(trigger: trigger, triggerParam: triggerParam, action: action, actionParam: actionParam)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            IslandViewTitle(icon: "bolt.fill", color: "#3B9EFF", title: "Automatisations",
                            subtitle: engine.rules.isEmpty ? "quand… alors…"
                                : "\(engine.rules.filter(\.enabled).count) active\(engine.rules.filter(\.enabled).count > 1 ? "s" : "")")

            builder

            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    if engine.rules.isEmpty {
                        Text("Des idées pour commencer :").font(.system(size: 10.5, weight: .semibold)).foregroundColor(Color(hex: "#8E939C"))
                        ForEach(OliRules.suggestions) { s in
                            Button { withAnimation { engine.add(s) } } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus.circle.fill").foregroundColor(Color(hex: "#3B9EFF"))
                                    Text(s.sentence).font(.system(size: 11)).foregroundColor(Color(hex: "#C5C8CD"))
                                    Spacer()
                                }
                                .padding(.horizontal, 8).padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "#16171A")))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    ForEach(engine.rules) { r in ruleRow(r) }
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    // MARK: The sentence to build

    private var builder: some View {
        HStack(spacing: 6) {
            Text("Quand").font(.system(size: 11.5, weight: .bold)).foregroundColor(Color(hex: "#F5F6F8"))
            Menu {
                ForEach(OliTrigger.allCases) { t in
                    Button { trigger = t; triggerParam = "" } label: { Label(t.label, systemImage: t.icon) }
                }
            } label: { chip(trigger.label, icon: trigger.icon, color: "#FFB547") }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            if let p = trigger.param {
                TextField(p.placeholder, text: $triggerParam)
                    .textFieldStyle(.plain).font(.system(size: 11, design: .rounded))
                    .frame(width: trigger == .dailyAt ? 44 : 30)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.07)))
                if !p.unit.isEmpty { Text(p.unit).font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C")) }
            }
            Text("alors").font(.system(size: 11.5, weight: .bold)).foregroundColor(Color(hex: "#F5F6F8"))
            Menu {
                ForEach(OliRuleAction.allCases) { a in
                    Button { action = a; actionParam = "" } label: { Label(a.label, systemImage: a.icon) }
                }
            } label: { chip(action.label, icon: action.icon, color: "#3B9EFF") }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            if let p = action.param {
                TextField(p.placeholder, text: $actionParam)
                    .textFieldStyle(.plain).font(.system(size: 11))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.07)))
                    .frame(minWidth: 70, maxWidth: 130)
            }
            Spacer(minLength: 0)
            Button {
                let r = draft
                withAnimation { engine.add(r) }
                flash = engine.rules.first?.id
                triggerParam = ""; actionParam = ""
                SoundEngine.shared.play("approve")
            } label: {
                Text("Ajouter").font(.system(size: 11, weight: .bold)).foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Color(hex: draft.isValid ? "#FF5B37" : "#3A3C42")))
            }
            .buttonStyle(.plain)
            .disabled(!draft.isValid)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(hex: "#16171A")))
    }

    private func chip(_ text: String, icon: String, color: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold))
            Text(text).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold)).opacity(0.7)
        }
        .foregroundColor(Color(hex: color))
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(Color(hex: color).opacity(0.14)))
    }

    // MARK: One rule

    private func ruleRow(_ r: OliRule) -> some View {
        HStack(spacing: 8) {
            Image(systemName: r.trigger.icon).font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color(hex: r.enabled ? "#FFB547" : "#6B7079")).frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(r.sentence).font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(hex: r.enabled ? "#E4E6EA" : "#6B7079")).lineLimit(1).truncationMode(.tail)
                if let f = r.lastFired {
                    Text("Dernière fois " + f.formatted(.relative(presentation: .named).locale(Locale(identifier: "fr_FR"))))
                        .font(.system(size: 9.5)).foregroundColor(Color(hex: "#6B7079"))
                }
            }
            Spacer(minLength: 4)
            Button("Tester") { engine.test(r) }
                .buttonStyle(.plain).font(.system(size: 10, weight: .semibold)).foregroundColor(Color(hex: "#8E939C"))
                .help("Lancer l’action maintenant")
            Toggle("", isOn: Binding(get: { r.enabled }, set: { _ in engine.toggle(r.id) }))
                .toggleStyle(.switch).controlSize(.mini).labelsHidden()
            Button { withAnimation { engine.remove(r.id) } } label: {
                Image(systemName: "trash").font(.system(size: 10)).foregroundColor(Color(hex: "#6B7079"))
            }
            .buttonStyle(.plain).help("Supprimer cette automatisation")
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: flash == r.id ? "#1E2A3A" : "#16171A")))
        .onAppear {
            if flash == r.id { DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { withAnimation { flash = nil } } }
        }
    }
}

// MARK: - Onglet ✨ de l'encoche : « Oli range »
// Où (Bureau, Téléchargements), quoi (types, ancienneté), comment (par type, par mois, les deux).
// Le compte se met à jour en direct ; rien ne bouge avant « Ranger », rien n'est jamais supprimé.

struct TidyIslandView: View {
    @ObservedObject var state: AppState
    @State private var options = DesktopTidy.Options.load()
    @State private var counts: [String: Int] = [:]
    @State private var total = 0
    @State private var planError: String? = nil
    @State private var busy = false
    @State private var result: String? = nil
    @State private var canUndo = DesktopTidy.canUndo

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            IslandViewTitle(icon: "sparkles", color: "#A78BFA", title: "Oli range",
                            subtitle: "rien n’est supprimé, tout va dans « Rangé par Oli »")

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    label("Où")
                    HStack(spacing: 5) {
                        ForEach(DesktopTidy.Source.allCases, id: \.self) { src in
                            pill(src.label, icon: src.icon, on: options.sources.contains(src)) {
                                if options.sources.contains(src) { if options.sources.count > 1 { options.sources.removeAll { $0 == src } } }
                                else { options.sources.append(src) }
                            }
                        }
                    }
                    label("Depuis")
                    segmented([(0, "Tout"), (7, "+ 7 jours"), (30, "+ 30 jours")], selection: options.minAgeDays) { options.minAgeDays = $0 }
                    label("Comment")
                    segmented(DesktopTidy.Grouping.allCases.map { ($0, $0.label) }, selection: options.grouping) { options.grouping = $0 }
                }
                .fixedSize()

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        label("Quoi")
                        Spacer()
                        Button(options.categories.count == DesktopTidy.allCategories.count ? "Aucun" : "Tout") {
                            options.categories = options.categories.count == DesktopTidy.allCategories.count ? [] : DesktopTidy.allCategories
                        }
                        .buttonStyle(.plain).font(.system(size: 10, weight: .semibold)).foregroundColor(Color(hex: "#8E939C"))
                    }
                    FlowChips(items: DesktopTidy.allCategories) { cat in
                        let n = counts[cat] ?? 0
                        pill(n > 0 ? "\(cat) \(n)" : cat, icon: nil, on: options.categories.contains(cat), dim: n == 0) {
                            if options.categories.contains(cat) { options.categories.removeAll { $0 == cat } }
                            else { options.categories.append(cat) }
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                if let planError {
                    Text(planError).font(.system(size: 10.5)).foregroundColor(Color(hex: "#FF8D97")).lineLimit(2)
                } else if let result {
                    Text(result).font(.system(size: 11, weight: .semibold)).foregroundColor(Color(hex: "#4ADE80")).lineLimit(2)
                } else {
                    Text(total == 0 ? "Rien à ranger avec ces choix" : "\(total) fichier\(total > 1 ? "s" : "") à ranger")
                        .font(.system(size: 11.5, weight: .semibold)).foregroundColor(Color(hex: total == 0 ? "#8E939C" : "#F5F6F8"))
                }
                Spacer()
                if canUndo {
                    Button("Annuler le dernier rangement") {
                        OliAutomations.undoTidy { n in
                            canUndo = false
                            result = "\(n) fichier\(n > 1 ? "s" : "") remis à leur place"
                            refresh()
                        }
                    }
                    .buttonStyle(.plain).font(.system(size: 10.5, weight: .semibold)).foregroundColor(Color(hex: "#FF8A52"))
                }
                Button {
                    busy = true
                    options.save()
                    OliAutomations.tidyDesktop { report in
                        busy = false
                        result = report.summary
                        canUndo = !report.moves.isEmpty || DesktopTidy.canUndo
                        refresh()
                    }
                } label: {
                    HStack(spacing: 5) {
                        if busy { ProgressView().controlSize(.mini) } else { Image(systemName: "sparkles") }
                        Text("Ranger").font(.system(size: 11.5, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Capsule().fill(Color(hex: total > 0 ? "#FF5B37" : "#3A3C42")))
                }
                .buttonStyle(.plain)
                .disabled(total == 0 || busy)
            }
        }
        .padding(.horizontal, 4)
        .onAppear { refresh() }
        .onChange(of: options) { _, o in o.save(); result = nil; refresh() }
    }

    /// Preview off the main thread: the folders are only listed, nothing moves.
    private func refresh() {
        let o = options
        Task.detached {
            let p = DesktopTidy.plan(o)
            await MainActor.run {
                // Counts per type whatever is ticked, so a chip says what it would add.
                var all = o; all.categories = DesktopTidy.allCategories
                counts = DesktopTidy.plan(all).countByCategory
                total = p.moves.count
                planError = p.errors.first
            }
        }
    }

    private func label(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 9, weight: .bold)).kerning(0.5).foregroundColor(Color(hex: "#6B7079"))
    }

    private func pill(_ text: String, icon: String?, on: Bool, dim: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).font(.system(size: 9, weight: .bold)) }
                Text(text).font(.system(size: 10.5, weight: .semibold)).lineLimit(1)
            }
            .foregroundColor(on ? .white : Color(hex: dim ? "#5A5E66" : "#9398A1"))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(on ? Color(hex: "#A78BFA").opacity(dim ? 0.35 : 0.85) : Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    private func segmented<T: Equatable>(_ items: [(T, String)], selection: T, set: @escaping (T) -> Void) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Button { set(item.0) } label: {
                    Text(item.1).font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(item.0 == selection ? .white : Color(hex: "#9398A1"))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(item.0 == selection ? Color(hex: "#2A2C31") : Color.clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.05)))
    }
}

/// Title row of the tall island views; leaves room for Oli in the top-left corner.
struct IslandViewTitle: View {
    let icon: String
    let color: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold)).foregroundColor(Color(hex: color))
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8"))
            Text(subtitle).font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C")).lineLimit(1)
            Spacer()
        }
        .padding(.leading, 60)
        .frame(height: 30)          // Oli (34 pt, centred 58 pt from the top) ends above the next row
    }
}

/// Chips that wrap onto several lines.
struct FlowChips<Content: View>: View {
    let items: [String]
    @ViewBuilder let content: (String) -> Content

    var body: some View {
        FlowLayout(spacing: 5) {
            ForEach(items, id: \.self) { content($0) }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 5

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let h = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        let w = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? w, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for i in row.indices {
                let s = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
                x += s.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for i in subviews.indices {
            let s = subviews[i].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty && rows[rows.count - 1].width + spacing + s.width > width {
                rows.append(Row())
            }
            var r = rows[rows.count - 1]
            r.width += (r.indices.isEmpty ? 0 : spacing) + s.width
            r.height = max(r.height, s.height)
            r.indices.append(i)
            rows[rows.count - 1] = r
        }
        return rows
    }
}
