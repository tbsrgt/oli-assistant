import SwiftUI

// MARK: - Réglages → Accueil
// Personnaliser l'accueil bento (tuiles, ordre, taille), Oli sur le bureau (mouvement) et les
// automatisations. L'aperçu en haut montre l'encoche telle qu'elle sera.

struct HomeSettingsView: View {
    @ObservedObject private var layout = HomeLayoutStore.shared
    @ObservedObject private var state = AppState.shared
    @State private var motion = DesktopOliMotion.current
    @State private var routinesVersion = 0
    @State private var onDesktop = DesktopOliController.shared.isOnDesktop
    @AppStorage(DesktopOliController.staysHomeKey) private var staysHome = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Affichage")
                        Spacer()
                        Picker("", selection: $layout.style) {
                            ForEach(HomeStyle.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 180)
                    }
                    preview
                    Text(layout.style == .bento
                         ? "Dans l’encoche, les deux premières rangées. Le panneau d’Oli sur le bureau les montre toutes."
                         : "Une ligne par service, les urgences en premier.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                .padding(6)
            }

            GroupBox("Tuiles") {
                VStack(spacing: 4) {
                    ForEach(Array(layout.tiles.enumerated()), id: \.element.id) { i, tile in
                        tileRow(tile, index: i)
                    }
                    HStack {
                        Spacer()
                        Button("Réinitialiser") { withAnimation { layout.reset() } }
                    }
                    .padding(.top, 4)
                }
                .padding(6)
            }

            GroupBox("Oli sur le bureau") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(onDesktop ? "Oli est sur ton bureau. Clique dessus pour ouvrir son panneau."
                                       : "Pose Oli sur le bureau : un clic sur lui ouvre ton tableau de bord, tes actions et tes routines.")
                            .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Toggle("Oli reste chez lui", isOn: Binding(get: { staysHome },
                                                                   set: { DesktopOliController.staysHome = $0; staysHome = $0
                                                                          if $0 { onDesktop = false } }))
                            .toggleStyle(.checkbox)
                        Button(onDesktop ? "Ramener dans l’encoche" : "Poser sur le bureau") {
                            DesktopOliController.shared.flyOutOrHome()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { onDesktop = DesktopOliController.shared.isOnDesktop }
                        }
                        .disabled(staysHome && !onDesktop)
                    }
                    HStack {
                        Text("Mouvement")
                        Spacer()
                        Picker("", selection: $motion) {
                            ForEach(DesktopOliMotion.allCases) { Label($0.label, systemImage: $0.icon).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 290)
                        .onChange(of: motion) { _, m in DesktopOliMotion.current = m }
                    }
                    Text("Me suit : Oli reste près de ta souris et s’arrête quand tu viens le chercher. Se promène : il se balade tout seul et s’endort quand rien ne se passe. Double-clic : retour à l’encoche.")
                        .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(6)
            }

            GroupBox("Automatisations") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(OliRoutine.allCases) { r in
                        HStack(spacing: 10) {
                            Image(systemName: r.icon).foregroundColor(Color(hex: "#3B9EFF")).frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r.title).font(.system(size: 12.5, weight: .semibold))
                                Text(r.detail).font(.system(size: 11)).foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(get: { r.isOn }, set: { r.isOn = $0; routinesVersion += 1 }))
                                .toggleStyle(.switch).labelsHidden()
                        }
                    }
                    .id(routinesVersion)
                    Divider().padding(.vertical, 2)
                    Text("En un clic").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                        ForEach(OliAction.allCases) { a in
                            Button { a.run() } label: {
                                Label(a.title, systemImage: a.icon).font(.system(size: 11))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(6)
            }
        }
    }

    // MARK: Preview (the notch card, at scale)

    private var preview: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black)
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: "#0E0F11"))
                .padding(8)
            // Oli's spot in the notch (the real one is animated there).
            Circle().fill(Color(hex: "#FF5B37")).frame(width: 46, height: 46)
                .overlay(HStack(spacing: 8) { Capsule().fill(.white).frame(width: 5, height: 9); Capsule().fill(.white).frame(width: 5, height: 9) })
                .offset(x: 34, y: 40)
            OculotHomeView(state: state)
                .padding(8)
                .allowsHitTesting(false)
        }
        .frame(width: 420, height: 128)
        .environment(\.colorScheme, .dark)
    }

    // MARK: One tile

    private func tileRow(_ tile: HomeTile, index i: Int) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { tile.visible }, set: { v in withAnimation { layout.tiles[i].visible = v } }))
                .toggleStyle(.checkbox).labelsHidden()
            Image(systemName: tile.kind.icon)
                .font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: tile.kind.color)))
            VStack(alignment: .leading, spacing: 1) {
                Text(tile.kind.title).font(.system(size: 12.5, weight: .semibold))
                Text(tile.kind.why).font(.system(size: 10.5)).foregroundColor(.secondary).lineLimit(1)
            }
            .opacity(tile.visible ? 1 : 0.5)
            Spacer()
            if let c = tile.kind.connection, !c.isConnected {
                OneClickConnectButton(kind: c, compact: true)
            }
            Picker("", selection: Binding(get: { tile.size }, set: { v in withAnimation { layout.tiles[i].size = v } })) {
                ForEach(HomeTileSize.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 120)
            .disabled(!tile.visible)
            VStack(spacing: 0) {
                Button { withAnimation { layout.move(tile.kind, by: -1) } } label: { Image(systemName: "chevron.up") }
                    .disabled(i == 0)
                Button { withAnimation { layout.move(tile.kind, by: 1) } } label: { Image(systemName: "chevron.down") }
                    .disabled(i == layout.tiles.count - 1)
            }
            .buttonStyle(.borderless).font(.system(size: 9, weight: .bold))
        }
        .padding(.vertical, 4).padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(tile.visible ? 0.05 : 0.02)))
    }
}
