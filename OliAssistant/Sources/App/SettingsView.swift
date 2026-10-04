import SwiftUI
import ServiceManagement
import AppKit

struct SettingsView: View {
    @ObservedObject private var state = AppState.shared
    @State private var apiKey: String = KeychainStore.shared.get("anthropic-api-key") ?? ""

    // Claude model — dynamic list fetched from the API, static fallback if unavailable
    private static let fallbackModels: [(id: String, label: String)] = [
        ("claude-sonnet-4-6",         "Claude Sonnet 4.6"),
        ("claude-sonnet-5-5",         "Claude Sonnet 5.5"),
        ("claude-opus-5-5",           "Claude Opus 5.5"),
        ("claude-haiku-4-5-20251001", "Claude Haiku 4.5"),
    ]
    private static let customModelTag = "__custom__"
    @State private var fetchedModels: [(id: String, label: String)] = []
    @State private var modelChoice: String = {
        let m = AppState.shared.claudeModel
        return SettingsView.fallbackModels.contains { $0.id == m } ? m : SettingsView.customModelTag
    }()
    @State private var customModel: String = {
        let m = AppState.shared.claudeModel
        return SettingsView.fallbackModels.contains { $0.id == m } ? "" : m
    }()
    private var displayModels: [(id: String, label: String)] {
        fetchedModels.isEmpty ? Self.fallbackModels : fetchedModels
    }
    @State private var launchAtStartup: Bool = (SMAppService.mainApp.status == .enabled)
    @State private var statusMessage: String = ""
    @State private var showDiff: Bool = false
    @State private var pendingHookJSON: String = ""
    @State private var hookNeedsUpdate: Bool = HookServer.hooksNeedUpdate()

    #if !APPSTORE
    @State private var showStatusLineDiff: Bool = false
    @State private var pendingStatusLineJSON: String = ""
    @State private var statusLinePendingInstall: Bool = true
    @State private var planTogglePending: Bool = false

    @State private var geminiHooksInstalled: Bool = HookServer.geminiHooksInstalled()
    @State private var showGeminiDiff: Bool = false
    @State private var pendingGeminiJSON: String = ""
    @State private var geminiPendingInstall: Bool = true

    @State private var agyHooksInstalled: Bool = HookServer.agyHooksInstalled()
    @State private var showAgyDiff: Bool = false
    @State private var pendingAgyJSON: String = ""
    @State private var agyPendingInstall: Bool = true

    @State private var codexHooksInstalled: Bool = HookServer.codexHooksInstalled()
    @State private var showCodexDiff: Bool = false
    @State private var pendingCodexJSON: String = ""
    @State private var codexPendingInstall: Bool = true
    #endif

    // Multi-provider chat keys
    @State private var googleKey: String  = KeychainStore.shared.get("google-api-key") ?? ""
    @State private var openAIKey: String  = KeychainStore.shared.get("openai-api-key") ?? ""
    @State private var ollamaURL:    String = AppState.shared.ollamaServerURL
    @State private var lmstudioURL:  String = AppState.shared.lmstudioServerURL
    @State private var connectingOllama:    Bool = false
    @State private var connectingLMStudio:  Bool = false

    // Integration keys
    @State private var espaceToken: String  = KeychainStore.shared.get("espace-token")    ?? ""
    @State private var espaceUrl: String    = KeychainStore.shared.get("espace-url")      ?? ""
    @State private var sitesManual: String  = AppState.shared.sitesManual
    @State private var claudeConnected: Bool = HookServer.claudeHooksInstalled()
    @State private var agendaIcsUrl: String = KeychainStore.shared.get("agenda-ics-url")  ?? ""
    @State private var pagespeedKey: String = KeychainStore.shared.get("pagespeed-api-key") ?? ""
    @State private var instagramToken: String = KeychainStore.shared.get("instagram-token") ?? ""
    @State private var instagramUserId: String = KeychainStore.shared.get("instagram-user-id") ?? ""
    @State private var vercelToken: String  = KeychainStore.shared.get("vercel-token")    ?? ""
    @State private var githubToken: String  = KeychainStore.shared.get("github-token")    ?? ""

    // Hotkey
    @State private var hotkeyFlags: UInt    = AppState.shared.hotkeyFlags
    @State private var hotkeyCode: UInt16   = AppState.shared.hotkeyCode

    // Vercel project filter
    @State private var vercelProjects: [String] = []
    @State private var loadingVercel: Bool = false


    // Bindings in minutes for the absence field
    private var absenceMinutes: Binding<Double> {
        Binding(
            get: { state.absenceInterval / 60 },
            set: { state.absenceInterval = max(1, $0) * 60 }
        )
    }

    // Sidebar selection persisted across sessions
    @AppStorage("settingsSection") private var selectedSection: String = "general"

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar — 200 pt, sidebar visual effect background
            ZStack(alignment: .topLeading) {
                SidebarBackground()
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    HStack(alignment: .center, spacing: 10) {
                        Image(nsImage: NSApplication.shared.applicationIconImage)
                            .resizable()
                            .frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Oli")
                                .font(.system(size: 13, weight: .semibold))
                            Text(appVersion)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 10)
                    Divider()
                    List(selection: Binding(
                        get: { Optional(selectedSection) },
                        set: { if let v = $0 { selectedSection = v; statusMessage = "" } }
                    )) {
                        SettingsSidebarRow(title: "General",      icon: "gearshape.fill",                    color: "#8E939C").tag("general")
                        SettingsSidebarRow(title: "Active pills", icon: "square.grid.2x2.fill",              color: "#F5A524").tag("activepills")
                        SettingsSidebarRow(title: "Agents",       icon: "terminal.fill",                     color: "#3B9EFF").tag("agents")
                        SettingsSidebarRow(title: "Chat",         icon: "bubble.left.and.bubble.right.fill", color: "#E07950").tag("chat")
                        SettingsSidebarRow(title: "Integrations", icon: "puzzlepiece.extension.fill",        color: "#7C5CFF").tag("integrations")
                        SettingsSidebarRow(title: "Shortcuts",    icon: "keyboard.fill",                     color: "#6366F1").tag("shortcuts")
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(width: 200)

            Divider()

            // Detail panel
            VStack(alignment: .leading, spacing: 0) {
                Text(sectionTitle)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 12)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        sectionContent
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
                if !statusMessage.isEmpty {
                    Divider()
                    Text(statusMessage)
                        .font(.system(size: 12))
                        .foregroundColor(statusMessage.hasPrefix("❌") ? .red : .secondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                }
            }
        }
        .onAppear {
            #if !APPSTORE
            state.refreshPlanRelayState()
            #endif
            guard fetchedModels.isEmpty,
                  let key = KeychainStore.shared.get("anthropic-api-key"), !key.isEmpty else { return }
            Task {
                let models = await ClaudeService.fetchModels(apiKey: key)
                guard !models.isEmpty else { return }
                await MainActor.run {
                    fetchedModels = models
                    let m = state.claudeModel
                    if models.contains(where: { $0.id == m }) {
                        modelChoice = m
                        customModel = ""
                    } else if modelChoice != Self.customModelTag {
                        modelChoice = Self.customModelTag
                        customModel = m
                    }
                }
            }
        }
    }

    // MARK: - Section routing

    private var sectionTitle: String {
        switch selectedSection {
        case "general":      return "General"
        case "activepills":  return "Active pills"
        case "agents":       return "Agents"
        case "chat":         return "Chat"
        case "integrations": return "Integrations"
        case "shortcuts":    return "Shortcuts"
        default:             return "General"
        }
    }

    @ViewBuilder private var sectionContent: some View {
        switch selectedSection {
        case "activepills":  activePillsSection
        case "agents":       agentsSection
        case "chat":         chatSection
        case "integrations": integrationsSection
        case "shortcuts":    ShortcutsSettingsView()
        default:             generalSection
        }
    }

    // MARK: - General section

    @ViewBuilder private var generalSection: some View {
        GroupBox("Sound") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Enable sounds", isOn: $state.soundEnabled)
                HStack(spacing: 8) {
                    Text("Volume")
                        .frame(width: 56, alignment: .leading)
                    Slider(value: $state.soundVolume, in: 0...0.2)
                        .disabled(!state.soundEnabled)
                    Text("\(Int(state.soundVolume / 0.2 * 100)) %")
                        .frame(width: 36, alignment: .trailing)
                        .monospacedDigit()
                }
            }
            .padding(6)
        }

        GroupBox("Behavior") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Close after")
                    TextField("60", value: $state.autoCloseInterval, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 64)
                    Text("s inactive")
                }
                HStack(spacing: 8) {
                    Text("Hide after")
                    TextField("3", value: absenceMinutes, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 48)
                    Text("min without movement")
                }
            }
            .padding(6)
        }

        GroupBox("Hotkey") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Show island with shortcut", isOn: $state.hotkeyEnabled)
                    .onChange(of: state.hotkeyEnabled) { _, _ in
                        HotKeyCenter.shared.reregister(.toggleIsland)
                    }
                if state.hotkeyEnabled {
                    HStack(spacing: 8) {
                        Text("Shortcut")
                            .frame(width: 70, alignment: .leading)
                        ShortcutRecorderButton(flags: $hotkeyFlags, code: $hotkeyCode)
                            .onChange(of: hotkeyFlags) { _, v in
                                state.hotkeyFlags = v
                                HotKeyCenter.shared.reregister(.toggleIsland)
                            }
                            .onChange(of: hotkeyCode) { _, v in
                                state.hotkeyCode = v
                                HotKeyCenter.shared.reregister(.toggleIsland)
                            }
                        Text("presses this → island opens")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(6)
        }

        GroupBox("Startup") {
            Toggle("Launch at Mac startup", isOn: $launchAtStartup)
                .onChange(of: launchAtStartup) { _, on in toggleStartup(on) }
                .padding(6)
        }

        GroupBox("App icon") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    ForEach(AppIconVariant.allCases, id: \.self) { v in
                        Button(action: { AppIconManager.apply(v) }) {
                            VStack(spacing: 6) {
                                Image(v.assetName)
                                    .resizable()
                                    .interpolation(.high)
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(AppIconManager.current == v ? Color.accentColor : Color.clear, lineWidth: 3)
                                    )
                                Text(v.title)
                                    .font(.system(size: 11))
                                    .foregroundColor(AppIconManager.current == v ? .primary : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Changes the icon in the Finder, the Dock when the settings are open, and in dialogs.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(6)
        }
    }

    // MARK: - Active pills section

    @ViewBuilder private var activePillsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Choose the tools you use. Oli only shows what you declare here.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Text("\(state.activeIntegrations.count)/4 slots used")
                    .font(.system(size: 11))
                    .foregroundColor(state.activeIntegrations.count >= 4 ? .orange : .secondary)

                Picker("Main", selection: $state.mainPillId) {
                    ForEach(PillCatalog.available.filter { $0.category == .workspace && !$0.comingSoon }, id: \.id) { def in
                        Text(def.name).tag(def.id)
                    }
                }
                .onChange(of: state.mainPillId) { _, newId in
                    state.activeIntegrations.remove(newId)
                    state.loadIntegrationTasks()
                    state.setFocus(newId)
                }

                ForEach(PillCategory.allCases, id: \.self) { cat in
                    let catPills = PillCatalog.available.filter { $0.category == cat }
                    if !catPills.isEmpty {
                        Divider()
                        Text(cat.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        ForEach(catPills, id: \.id) { def in
                            pillRow(def)
                        }
                    }
                }
            }
            .padding(6)
        }
    }

    // MARK: - Agents section

    @ViewBuilder private var agentsSection: some View {
        // Oculot: one button to connect Claude (session tracking + chat on the user's own Claude Code)
        GroupBox {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Color(hex: "#E07950"))
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Claude").font(.system(size: 13, weight: .semibold))
                        Text(claudeConnected ? "connecté" : "non connecté")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(claudeConnected ? .green : .secondary)
                    }
                    Text(claudeConnected
                         ? "Oli suit tes sessions Claude Code, tu réponds aux autorisations depuis l’encoche, et le chat utilise ton Claude."
                         : ClaudeService.claudeCodePath == nil
                            ? "Installe d’abord Claude Code sur ce Mac, puis reviens ici."
                            : "Un clic : Oli suit tes sessions et le chat utilise ton Claude, sans clé API ni réglage.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if claudeConnected {
                    Button("Déconnecter") { disconnectClaude() }.buttonStyle(.bordered)
                } else {
                    Button("Connecter Claude") { connectClaude() }
                        .buttonStyle(.borderedProminent)
                        .disabled(ClaudeService.claudeCodePath == nil)
                }
            }
            .padding(4)
        }

        DisclosureGroup("Options avancées") {
        GroupBox("Claude Code Hooks") {
            VStack(alignment: .leading, spacing: 10) {
                if hookNeedsUpdate {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Hooks outdated — update them to answer Claude's questions from the notch")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                    }
                    #if APPSTORE
                    Button("Update hooks") { installHooksAppStore() }
                    #else
                    Button("Update hooks") { installHooks() }
                    #endif
                }
                #if APPSTORE
                Text("~/.claude/oli/oli-hook")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                HStack(spacing: 10) {
                    Button("Install hooks") { installHooksAppStore() }
                        .buttonStyle(.borderedProminent)
                    Button("Uninstall") { uninstallHooksAppStore() }
                        .buttonStyle(.bordered)
                }
                #else
                Text("oli-hook : \(HookServer.hookScriptPath)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                HStack(spacing: 10) {
                    Button("Install hooks") { installHooks() }
                        .buttonStyle(.borderedProminent)
                    Button("Uninstall") { uninstallHooks() }
                        .buttonStyle(.bordered)
                }
                #endif

                #if !APPSTORE
                if showDiff {
                    ScrollView {
                        Text(pendingHookJSON)
                            .font(.system(size: 10, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 140)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)

                    HStack {
                        Button("Confirm & write") { confirmInstall() }
                            .buttonStyle(.borderedProminent)
                        Button("Cancel") { showDiff = false; pendingHookJSON = "" }
                            .buttonStyle(.bordered)
                    }
                }
                #endif
            }
            .padding(6)
        }
        }

        #if !APPSTORE
        GroupBox("Gemini CLI Hooks") {
            VStack(alignment: .leading, spacing: 10) {
                Text(geminiHooksInstalled
                     ? "Hooks installed — restart Gemini CLI to activate"
                     : "~/.gemini/settings.json")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                HStack(spacing: 10) {
                    Button("Install hooks") { triggerGeminiPreview(install: true) }
                        .buttonStyle(.borderedProminent)
                    Button("Uninstall") { triggerGeminiPreview(install: false) }
                        .buttonStyle(.bordered)
                }
                if showGeminiDiff {
                    ScrollView {
                        Text(pendingGeminiJSON)
                            .font(.system(size: 10, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 140)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                    HStack {
                        Button("Confirm & write") { confirmGeminiOp() }
                            .buttonStyle(.borderedProminent)
                        Button("Cancel") { showGeminiDiff = false; pendingGeminiJSON = "" }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .padding(6)
        }

        GroupBox("Antigravity Hooks") {
            VStack(alignment: .leading, spacing: 10) {
                Text(agyHooksInstalled
                     ? "Hooks installed — restart Antigravity to activate"
                     : "~/.gemini/config/hooks.json")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                HStack(spacing: 10) {
                    Button("Install hooks") { triggerAgyPreview(install: true) }
                        .buttonStyle(.borderedProminent)
                    Button("Uninstall") { triggerAgyPreview(install: false) }
                        .buttonStyle(.bordered)
                }
                if showAgyDiff {
                    ScrollView {
                        Text(pendingAgyJSON)
                            .font(.system(size: 10, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 140)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                    HStack {
                        Button("Confirm & write") { confirmAgyOp() }
                            .buttonStyle(.borderedProminent)
                        Button("Cancel") { showAgyDiff = false; pendingAgyJSON = "" }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .padding(6)
        }

        GroupBox("Codex Hooks") {
            VStack(alignment: .leading, spacing: 10) {
                Text(codexHooksInstalled
                     ? "Hooks installed — open Codex and run /hooks or open Hooks in the app's settings to trust them"
                     : "~/.codex/hooks.json")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                HStack(spacing: 10) {
                    Button("Install hooks") { triggerCodexPreview(install: true) }
                        .buttonStyle(.borderedProminent)
                    Button("Uninstall") { triggerCodexPreview(install: false) }
                        .buttonStyle(.bordered)
                }
                if showCodexDiff {
                    ScrollView {
                        Text(pendingCodexJSON)
                            .font(.system(size: 10, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 140)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                    HStack {
                        Button("Confirm & write") { confirmCodexOp() }
                            .buttonStyle(.borderedProminent)
                        Button("Cancel") { showCodexDiff = false; pendingCodexJSON = "" }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .padding(6)
        }

        GroupBox("Plan usage") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Shows your Claude plan usage (5-hour and weekly limits) in the notch header. Oli adds a status line relay to ~/.claude/settings.json. If you already have a status line, it keeps working as before. Pro and Max plans only.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Show in the notch", isOn: Binding(
                    get: { state.showPlanInNotch || planTogglePending },
                    set: { on in
                        if on {
                            if state.planRelayInstalled {
                                state.showPlanInNotch = true
                            } else {
                                planTogglePending = true
                                installStatusLine()
                            }
                        } else {
                            state.showPlanInNotch = false
                            planTogglePending = false
                        }
                    }
                ))
                HStack(spacing: 10) {
                    if state.planRelayInstalled {
                        Text("Relay: installed")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Button("Uninstall relay") { uninstallStatusLine() }
                            .buttonStyle(.bordered)
                    } else {
                        Text("Relay: not installed")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Button("Install relay") { installStatusLine() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                if showStatusLineDiff {
                    ScrollView {
                        Text(pendingStatusLineJSON)
                            .font(.system(size: 10, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 100)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                    HStack {
                        Button("Confirm & write") { confirmStatusLine() }
                            .buttonStyle(.borderedProminent)
                        Button("Cancel") {
                            showStatusLineDiff = false
                            pendingStatusLineJSON = ""
                            planTogglePending = false
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(6)
        }
        #endif
    }

    // MARK: - Chat section

    @ViewBuilder private var chatSection: some View {
        GroupBox("Anthropic API") {
            VStack(alignment: .leading, spacing: 8) {
                SecureField("API key (sk-ant-…)", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                Button("Save") {
                    KeychainStore.shared.set("anthropic-api-key", value: apiKey)
                    statusMessage = "✓ Key saved."
                }
                .buttonStyle(.borderedProminent)

                Divider().padding(.vertical, 2)

                Picker("Model", selection: $modelChoice) {
                    ForEach(displayModels, id: \.id) { preset in
                        Text(preset.label).tag(preset.id)
                    }
                    Text("Custom…").tag(Self.customModelTag)
                }
                .onChange(of: modelChoice) { _, choice in
                    if choice != Self.customModelTag {
                        state.claudeModel = choice
                    } else {
                        applyCustomModel(customModel)
                    }
                }

                if modelChoice == Self.customModelTag {
                    TextField("Model ID (e.g. claude-sonnet-4-6)", text: $customModel)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: customModel) { _, value in applyCustomModel(value) }
                }

                Text("Used by the chat. The list comes from your Anthropic account.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(6)
        }

        GroupBox("Chat — other providers") {
            VStack(alignment: .leading, spacing: 12) {
                Text("To use Google Gemini or OpenAI from the chat. Keys are stored in the Keychain.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    Circle().fill(Color(hex: "#4285F4")).frame(width: 8, height: 8)
                    Text("Google AI").font(.system(size: 12, weight: .semibold))
                }
                SecureField("API key (AI Studio)", text: $googleKey)
                    .textFieldStyle(.roundedBorder)
                Button("Save") {
                    KeychainStore.shared.set("google-api-key", value: googleKey)
                    statusMessage = "✓ Google key saved."
                }
                .buttonStyle(.borderedProminent)

                Divider()

                HStack(spacing: 8) {
                    Circle().fill(Color(hex: "#10A37F")).frame(width: 8, height: 8)
                    Text("OpenAI").font(.system(size: 12, weight: .semibold))
                }
                SecureField("API key (sk-…)", text: $openAIKey)
                    .textFieldStyle(.roundedBorder)
                Button("Save") {
                    KeychainStore.shared.set("openai-api-key", value: openAIKey)
                    statusMessage = "✓ OpenAI key saved."
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, 4)
        }

        GroupBox("Local models") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Connect to a local model server. No API key needed.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                // ── Ollama ──────────────────────────────────────────────────────
                HStack(spacing: 8) {
                    Circle().fill(Color(hex: "#FACC15")).frame(width: 8, height: 8)
                    Text("Ollama").font(.system(size: 12, weight: .semibold))
                    if !state.ollamaServerURL.isEmpty {
                        Text("Connected")
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#22C55E"))
                    }
                }
                if state.ollamaServerURL.isEmpty {
                    TextField("http://127.0.0.1:11434", text: $ollamaURL)
                        .textFieldStyle(.roundedBorder)
                    Button(connectingOllama ? "Connecting…" : "Connect") {
                        Task { await connectLocal(provider: .ollama) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(connectingOllama)
                } else {
                    Text(state.ollamaServerURL)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                    Button("Disconnect") {
                        state.ollamaServerURL = ""
                        ollamaURL = ""
                        state.fetchedProviderModels[.ollama] = nil
                        state.providerModelFetchError[.ollama] = nil
                        if state.chatProvider == .ollama { state.chatProvider = .anthropic }
                        statusMessage = "Ollama disconnected."
                    }
                    .buttonStyle(.bordered)
                }

                Divider()

                // ── LM Studio ───────────────────────────────────────────────────
                HStack(spacing: 8) {
                    Circle().fill(Color(hex: "#A3E635")).frame(width: 8, height: 8)
                    Text("LM Studio").font(.system(size: 12, weight: .semibold))
                    if !state.lmstudioServerURL.isEmpty {
                        Text("Connected")
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#22C55E"))
                    }
                }
                if state.lmstudioServerURL.isEmpty {
                    TextField("http://127.0.0.1:1234", text: $lmstudioURL)
                        .textFieldStyle(.roundedBorder)
                    Button(connectingLMStudio ? "Connecting…" : "Connect") {
                        Task { await connectLocal(provider: .lmstudio) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(connectingLMStudio)
                } else {
                    Text(state.lmstudioServerURL)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                    Button("Disconnect") {
                        state.lmstudioServerURL = ""
                        lmstudioURL = ""
                        state.fetchedProviderModels[.lmstudio] = nil
                        state.providerModelFetchError[.lmstudio] = nil
                        if state.chatProvider == .lmstudio { state.chatProvider = .anthropic }
                        statusMessage = "LM Studio disconnected."
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Integrations section

    @ViewBuilder private var integrationsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {

                // Espace client Oculot
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Circle().fill(Color(hex: "#FF5B37")).frame(width: 8, height: 8)
                        Text("Espace client").font(.system(size: 12, weight: .semibold))
                        Text("Oculot").font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    SecureField("Team token  (ESPACE_TEAM_TOKEN)", text: $espaceToken)
                        .textFieldStyle(.roundedBorder)
                    TextField("URL  (défaut : \(EspacePoller.defaultBaseURL))", text: $espaceUrl)
                        .textFieldStyle(.roundedBorder)
                    if !state.espaceClients.isEmpty, let sync = state.espaceLastSync {
                        Text("\(state.espaceClients.count) projets · synchro \(sync.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    } else if state.espaceLastStatus == 401 {
                        Text("Jeton refusé par l’espace client.").font(.system(size: 11)).foregroundColor(.red)
                    } else if state.espaceLastStatus > 0 && state.espaceLastStatus != 200 {
                        Text("Réponse \(state.espaceLastStatus) de l’espace client.").font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }

                // Agenda Oculot (lien iCal personnel, lecture seule)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Circle().fill(Color(hex: "#FFD65C")).frame(width: 8, height: 8)
                        Text("Agenda").font(.system(size: 12, weight: .semibold))
                        Text("Oculot").font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    SecureField("Lien du calendrier  (https://… ou webcal://…)", text: $agendaIcsUrl)
                        .textFieldStyle(.roundedBorder)
                    Text("Sur agenda.oculot.studio : le lien personnel « S’abonner au calendrier » (Copier le lien). Une adresse iCal Google Agenda marche aussi.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                    if let sync = state.agendaLastSync, state.agendaLastStatus == 200 {
                        let n = state.agendaEvents.count
                        Text("\(n == 0 ? "aucun" : "\(n)") rendez-vous sur 14 jours · synchro \(sync.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    } else if state.agendaLastStatus == -1 {
                        Text("Lien invalide : il doit commencer par https:// (ou webcal://).").font(.system(size: 11)).foregroundColor(.red)
                    } else if state.agendaLastStatus == 401 || state.agendaLastStatus == 403 || state.agendaLastStatus == 404 {
                        Text("Lien refusé : redemande un lien de calendrier sur l’agenda.").font(.system(size: 11)).foregroundColor(.red)
                    } else if state.agendaLastStatus > 0 && state.agendaLastStatus != 200 {
                        Text("Réponse \(state.agendaLastStatus) de l’agenda.").font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }

                // Sites clients Oculot
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Circle().fill(Color(hex: "#F7C3D4")).frame(width: 8, height: 8)
                        Text("Sites clients").font(.system(size: 12, weight: .semibold))
                        Text("Oculot").font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    Text("Les sites livrés de l’espace client sont surveillés automatiquement.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                    Text("Autres sites à surveiller (une URL par ligne)")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                    TextEditor(text: $sitesManual)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(height: 58)
                        .padding(2)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.35), lineWidth: 1))
                    SecureField("Clé API PageSpeed Insights  (gratuite, Google Cloud)", text: $pagespeedKey)
                        .textFieldStyle(.roundedBorder)
                    Text("Chaque jour : score PageSpeed mobile, expiration du domaine, www et domaine nu. Chaque semaine : robots.txt, sitemap, liens de l’accueil.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                    if let sync = state.sitesLastSync {
                        let up = state.siteChecks.filter { $0.status == .ok }.count
                        let down = state.siteChecks.filter { $0.status == .down }.count
                        Text("\(state.siteChecks.count) sites · \(up) en ligne · \(down) en panne · dernière passe \(sync.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 11)).foregroundColor(down > 0 ? .red : .secondary)
                    } else if !SitesPoller.targets.isEmpty {
                        Text("\(SitesPoller.targets.count) sites · première vérification en cours…")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }

                // Instagram Oculot (lecture seule)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Circle().fill(Color(hex: "#E1306C")).frame(width: 8, height: 8)
                        Text("Instagram").font(.system(size: 12, weight: .semibold))
                        Text("Oculot").font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    SecureField("Jeton d’accès  (IGAA… ou EAA…)", text: $instagramToken)
                        .textFieldStyle(.roundedBorder)
                    TextField("Identifiant du compte  (facultatif, trouvé tout seul)", text: $instagramUserId)
                        .textFieldStyle(.roundedBorder)
                    Text("Lecture seule : abonnés, derniers posts, commentaires sans réponse, rappel après \(SocialSnapshot.quietDays) jours sans post. Oli ne publie jamais rien.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                    if let snap = state.social, snap.fetchedAt != nil {
                        if let e = snap.error {
                            Text(e).font(.system(size: 11)).foregroundColor(.red)
                        } else {
                            Text("@\(snap.username) · \(snap.followersLabel) · \(snap.lastPostLabel())")
                                .font(.system(size: 11)).foregroundColor(.secondary)
                        }
                    }
                }

                // Vercel
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Circle().fill(Color(hex: "#7C5CFF")).frame(width: 8, height: 8)
                        Text("Vercel").font(.system(size: 12, weight: .semibold))
                    }
                    SecureField("Token", text: $vercelToken)
                        .textFieldStyle(.roundedBorder)
                    IntegrationFilterRow(
                        label: "Projects",
                        items: vercelProjects,
                        filter: $state.vercelProjectFilter,
                        loading: loadingVercel,
                        onLoad: loadVercelProjects
                    )
                }

                // GitHub
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Circle().fill(Color(hex: "#F4505E")).frame(width: 8, height: 8)
                        Text("GitHub").font(.system(size: 12, weight: .semibold))
                    }
                    SecureField("Personal Access Token", text: $githubToken)
                        .textFieldStyle(.roundedBorder)
                    Text("Classic token with repo scope, or fine-grained with read access to Pull requests, Commit statuses and Actions.")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#8E939C"))
                }

                Button("Save integrations") { saveIntegrations() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(6)
        }
    }

    // MARK: - Actions

    private func applyCustomModel(_ value: String) {
        let id = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !id.isEmpty { state.claudeModel = id }
    }

    private func toggleStartup(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else  { try SMAppService.mainApp.unregister() }
        } catch {
            statusMessage = "❌ Startup: \(error.localizedDescription)"
            launchAtStartup = !on
        }
    }

    // MARK: - App Store: hooks via NSOpenPanel + security-scoped bookmark

    #if APPSTORE
    private func pickClaudeFolder(prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.message = "Select your .claude folder (press ⇧⌘. to show hidden files)"
        panel.prompt = prompt
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        let realHomePath = getpwuid(getuid()).flatMap { String(cString: $0.pointee.pw_dir, encoding: .utf8) }
            ?? "/Users/\(NSUserName())"
        panel.directoryURL = URL(fileURLWithPath: realHomePath)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard url.lastPathComponent == ".claude" else {
            statusMessage = "❌ Select the .claude folder (hidden, in your Home directory)."
            return nil
        }
        return url
    }

    private func installHooksAppStore() {
        guard let claudeURL = pickClaudeFolder(prompt: "Select") else { return }
        let alert = NSAlert()
        alert.messageText = "Install Oli hooks in ~/.claude?"
        alert.informativeText = "Will write:\n• ~/.claude/oli/oli-hook\n• ~/.claude/settings.json (backup created first)"
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .informational
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try HookServer.shared.installAndWriteClaudeHooksAppStore(claudeURL: claudeURL)
            hookNeedsUpdate = false
            statusMessage = "✓ Hooks installed — restart VS Code to activate."
        } catch {
            statusMessage = "❌ \(error.localizedDescription)"
        }
    }

    private func uninstallHooksAppStore() {
        guard let claudeURL = pickClaudeFolder(prompt: "Select") else { return }
        do {
            try HookServer.shared.uninstallClaudeHooksAppStore(claudeURL: claudeURL)
            statusMessage = "✓ Hooks removed."
        } catch {
            statusMessage = "❌ \(error.localizedDescription)"
        }
    }
    #endif

    private func connectLocal(provider: ChatProvider) async {
        let rawURL = provider == .ollama ? ollamaURL : lmstudioURL
        let candidate = rawURL.isEmpty
            ? (provider == .ollama ? "http://127.0.0.1:11434" : "http://127.0.0.1:1234")
            : rawURL
        let normalised = LocalChat.normaliseURL(candidate)
        guard normalised.hasPrefix("http://") || normalised.hasPrefix("https://") else {
            statusMessage = "Only http:// and https:// URLs are supported."
            return
        }
        if provider == .ollama { connectingOllama = true } else { connectingLMStudio = true }
        statusMessage = ""
        let result = await LocalChat.fetchModelsResult(baseURL: normalised)
        if provider == .ollama { connectingOllama = false } else { connectingLMStudio = false }
        let name = provider == .ollama ? "Ollama" : "LM Studio"
        switch result {
        case .success(let models) where models.isEmpty:
            statusMessage = "No models yet — download one in \(name) first."
        case .success(let models):
            if provider == .ollama {
                state.ollamaServerURL = normalised
                ollamaURL = normalised
                state.fetchedProviderModels[.ollama] = nil
                state.providerModelFetchError[.ollama] = nil
            } else {
                state.lmstudioServerURL = normalised
                lmstudioURL = normalised
                state.fetchedProviderModels[.lmstudio] = nil
                state.providerModelFetchError[.lmstudio] = nil
            }
            statusMessage = "✓ Connected · \(models.count) model\(models.count == 1 ? "" : "s")"
        case .failure:
            statusMessage = "Couldn't reach \(name) at \(normalised). Is it running?"
        }
    }

    /// One click, one confirmation: hooks in ~/.claude/settings.json (dated backup kept) and the chat on Claude Code.
    private func connectClaude() {
        let alert = NSAlert()
        alert.messageText = "Connecter Claude à Oli ?"
        alert.informativeText = """
        Oli va ajouter son relais aux réglages de Claude Code (~/.claude/settings.json) pour suivre tes sessions \
        et te laisser accepter ou refuser les autorisations depuis l’encoche. Une copie de l’ancien fichier est gardée à côté.

        Le chat d’Oli utilisera ton Claude Code, avec ton abonnement : aucune clé API à saisir.
        """
        alert.addButton(withTitle: "Connecter")
        alert.addButton(withTitle: "Annuler")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            _ = try HookServer.shared.previewClaudeHooks()
            try HookServer.shared.writeClaudeHooks()
            hookNeedsUpdate = false
            claudeConnected = HookServer.claudeHooksInstalled()
            statusMessage = claudeConnected ? "✓ Claude est connecté." : "Les hooks n’ont pas pu être vérifiés."
        } catch {
            statusMessage = "❌ \(error.localizedDescription)"
        }
    }

    private func disconnectClaude() {
        let alert = NSAlert()
        alert.messageText = "Déconnecter Claude ?"
        alert.informativeText = "Oli retire son relais des réglages de Claude Code. Tes autres hooks ne sont pas touchés."
        alert.addButton(withTitle: "Déconnecter")
        alert.addButton(withTitle: "Annuler")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try HookServer.shared.uninstallClaudeHooks()
            claudeConnected = HookServer.claudeHooksInstalled()
            statusMessage = "✓ Claude est déconnecté."
        } catch {
            statusMessage = "❌ \(error.localizedDescription)"
        }
    }

    private func installHooks() {
        do {
            pendingHookJSON = try HookServer.shared.previewClaudeHooks()
            showDiff = true
            statusMessage = "Review the JSON below before confirming."
        } catch {
            statusMessage = "❌ \(error.localizedDescription)"
        }
    }

    private func confirmInstall() {
        do {
            try HookServer.shared.writeClaudeHooks()
            showDiff = false
            statusMessage = "✓ Hooks installed in ~/.claude/settings.json"
            pendingHookJSON = ""
            hookNeedsUpdate = false
        } catch {
            statusMessage = "❌ Write error: \(error.localizedDescription)"
        }
    }

    private func uninstallHooks() {
        do {
            try HookServer.shared.uninstallClaudeHooks()
            statusMessage = "✓ Hooks removed."
        } catch {
            statusMessage = "❌ \(error.localizedDescription)"
        }
    }

    #if !APPSTORE
    private func triggerGeminiPreview(install: Bool) {
        do {
            geminiPendingInstall = install
            pendingGeminiJSON = try HookServer.shared.previewGeminiHooks(install: install)
            showGeminiDiff = true
            statusMessage = "Review the JSON below before confirming."
        } catch let e as NSError where e.domain == "OliNoop" {
            statusMessage = e.localizedDescription
        } catch {
            statusMessage = "❌ \(error.localizedDescription)"
        }
    }

    private func confirmGeminiOp() {
        do {
            try HookServer.shared.writeGeminiHooks()
            showGeminiDiff = false
            pendingGeminiJSON = ""
            geminiHooksInstalled = geminiPendingInstall
            statusMessage = geminiPendingInstall
                ? "✓ Gemini CLI hooks installed in ~/.gemini/settings.json"
                : "✓ Gemini CLI hooks removed."
        } catch {
            statusMessage = "❌ \(error.localizedDescription)"
        }
    }

    private func triggerAgyPreview(install: Bool) {
        do {
            agyPendingInstall = install
            pendingAgyJSON = try HookServer.shared.previewAgyHooks(install: install)
            showAgyDiff = true
            statusMessage = "Review the JSON below before confirming."
        } catch let e as NSError where e.domain == "OliNoop" {
            statusMessage = e.localizedDescription
        } catch {
            statusMessage = "❌ \(error.localizedDescription)"
        }
    }

    private func confirmAgyOp() {
        do {
            try HookServer.shared.writeAgyHooks()
            showAgyDiff = false
            pendingAgyJSON = ""
            agyHooksInstalled = agyPendingInstall
            statusMessage = agyPendingInstall
                ? "✓ Antigravity hooks installed in ~/.gemini/config/hooks.json"
                : "✓ Antigravity hooks removed."
        } catch {
            statusMessage = "❌ \(error.localizedDescription)"
        }
    }

    private func triggerCodexPreview(install: Bool) {
        do {
            codexPendingInstall = install
            pendingCodexJSON = try HookServer.shared.previewCodexHooks(install: install)
            showCodexDiff = true
            statusMessage = "Review the JSON below before confirming."
        } catch let e as NSError where e.domain == "OliNoop" {
            statusMessage = e.localizedDescription
        } catch {
            statusMessage = "❌ \(error.localizedDescription)"
        }
    }

    private func confirmCodexOp() {
        do {
            try HookServer.shared.writeCodexHooks()
            showCodexDiff = false
            pendingCodexJSON = ""
            codexHooksInstalled = codexPendingInstall
            statusMessage = codexPendingInstall
                ? "✓ Codex hooks installed — run /hooks in Codex or open Hooks in the app's settings to trust them."
                : "✓ Codex hooks removed."
        } catch {
            statusMessage = "❌ \(error.localizedDescription)"
        }
    }

    private func installStatusLine() {
        do {
            pendingStatusLineJSON = try HookServer.shared.previewStatusLine(install: true)
            showStatusLineDiff = true
            statusLinePendingInstall = true
            statusMessage = "Review the JSON below before confirming."
        } catch {
            statusMessage = "❌ \(error.localizedDescription)"
        }
    }

    private func uninstallStatusLine() {
        do {
            pendingStatusLineJSON = try HookServer.shared.previewStatusLine(install: false)
            showStatusLineDiff = true
            statusLinePendingInstall = false
            statusMessage = "Review the JSON below before confirming."
        } catch {
            statusMessage = "❌ \(error.localizedDescription)"
        }
    }

    private func confirmStatusLine() {
        do {
            try HookServer.shared.writeStatusLine()
            showStatusLineDiff = false
            pendingStatusLineJSON = ""
            state.refreshPlanRelayState()
            if planTogglePending {
                state.showPlanInNotch = true
                planTogglePending = false
            }
            if !statusLinePendingInstall {
                state.showPlanInNotch = false
            }
            statusMessage = statusLinePendingInstall
                ? "✓ Status line installed."
                : "✓ Status line removed."
        } catch {
            planTogglePending = false
            statusMessage = "❌ \(error.localizedDescription)"
        }
    }
    #endif

    private func saveIntegrations() {
        saveKey("vercel-token",    value: vercelToken)
        saveKey("espace-token",    value: espaceToken)
        saveKey("espace-url",      value: espaceUrl)
        EspacePoller.shared.pollNow()
        let prevAgenda = KeychainStore.shared.get("agenda-ics-url")
        saveKey("agenda-ics-url",  value: agendaIcsUrl.trimmingCharacters(in: .whitespacesAndNewlines))
        if KeychainStore.shared.get("agenda-ics-url") != prevAgenda {
            AppState.shared.agendaEvents = []
            AppState.shared.agendaLastSync = nil
            AppState.shared.agendaLastStatus = 0
        }
        AgendaPoller.shared.pollNow()
        saveKey("pagespeed-api-key", value: pagespeedKey)
        saveKey("instagram-token", value: instagramToken.trimmingCharacters(in: .whitespacesAndNewlines))
        saveKey("instagram-user-id", value: instagramUserId.trimmingCharacters(in: .whitespacesAndNewlines))
        SocialPoller.shared.refreshNow()
        state.sitesManual = sitesManual
        SitesPoller.shared.checkNow()

        // Detect GitHub token changes before writing
        let prevGithubToken = KeychainStore.shared.get("github-token")
        saveKey("github-token", value: githubToken)
        let nextGithubToken = KeychainStore.shared.get("github-token")
        if nextGithubToken != prevGithubToken {
            AppState.shared.githubPulse = nil
            AppState.shared.githubActivity = nil
            if nextGithubToken == nil { AppState.shared.githubStats = nil }
            if nextGithubToken != nil {
                GithubPoller.shared.triggerPulseNow()
                GithubPoller.shared.refreshActivityIfStale()
            }
        }

        statusMessage = "✓ Integration keys saved."
    }

    private func saveKey(_ key: String, value: String) {
        if value.isEmpty {
            KeychainStore.shared.remove(key)
        } else {
            KeychainStore.shared.set(key, value: value)
        }
    }

    // MARK: - Vercel project list

    private func loadVercelProjects() {
        guard let token = KeychainStore.shared.get("vercel-token") else {
            statusMessage = "❌ Save Vercel token first."
            return
        }
        loadingVercel = true
        guard let url = URL(string: "https://api.vercel.com/v9/projects?limit=100") else { return }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: req) { data, response, _ in
            let names: [String]
            if let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let projects = json["projects"] as? [[String: Any]] {
                names = projects.compactMap { $0["name"] as? String }.sorted()
            } else {
                names = []
            }
            DispatchQueue.main.async {
                self.vercelProjects = names
                self.loadingVercel = false
                if names.isEmpty { self.statusMessage = "❌ No Vercel projects found." }
            }
        }.resume()
    }


    @ViewBuilder
    private func pillRow(_ def: PillDefinition) -> some View {
        let isMain = def.id == state.mainPillId
        let isOn   = state.activeIntegrations.contains(def.id)
        let atMax  = state.activeIntegrations.count >= 4 && !isOn && !isMain
        let hint: String? = {
            if isMain { return nil }
            if def.comingSoon { return "Coming soon" }
            #if !APPSTORE
            if def.id == "agent_gemini"        && !HookServer.geminiHooksInstalled()  { return "Hooks not installed" }
            if def.id == "agent_antigravity"   && !HookServer.agyHooksInstalled()    { return "Hooks not installed" }
            if def.id == "agent_codex"         && !HookServer.codexHooksInstalled()  { return "Hooks not installed" }
            #endif
            if def.category == .ai {
                if let provider = ChatProvider(pillID: def.id), provider.isLocal {
                    let url = provider == .ollama ? state.ollamaServerURL : state.lmstudioServerURL
                    if url.isEmpty { return "Not connected" }
                } else {
                    let keyId = def.id == "ai_anthropic" ? "anthropic-api-key"
                               : def.id == "ai_google"    ? "google-api-key" : "openai-api-key"
                    if KeychainStore.shared.get(keyId) == nil { return "Key not configured" }
                }
            }
            return nil
        }()
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: def.color))
                .frame(width: 10, height: 10)
            Text(def.name)
                .font(.system(size: 12))
                .foregroundColor(atMax ? .secondary : .primary)
            Spacer()
            if isMain {
                Text("Main")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                if let h = hint {
                    Text(h)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Toggle("", isOn: Binding(
                    get: { isOn },
                    set: { _ in state.toggleIntegration(def.id) }
                ))
                .labelsHidden()
                .disabled(atMax)
            }
        }
    }
}

// MARK: - Sidebar background (NSVisualEffectView .sidebar)

struct SidebarBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .sidebar
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Sidebar row (System Settings style icon)

struct SettingsSidebarRow: View {
    let title: String
    let icon: String
    let color: String

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color(hex: color)))
        }
    }
}

// MARK: - Integration filter row (Vercel)

struct IntegrationFilterRow: View {
    let label: String
    let items: [String]
    @Binding var filter: Set<String>
    let loading: Bool
    let onLoad: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                if loading {
                    ProgressView().scaleEffect(0.6)
                } else {
                    Button(items.isEmpty ? "Load list" : "Refresh") { onLoad() }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                }
                if !filter.isEmpty {
                    Button("Clear") { filter = [] }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .foregroundColor(.secondary)
                }
            }
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(items, id: \.self) { item in
                        Toggle(item, isOn: Binding(
                            get: { filter.isEmpty || filter.contains(item) },
                            set: { on in
                                if on { filter.insert(item) }
                                else  {
                                    if filter.isEmpty { filter = Set(items).subtracting([item]) }
                                    else { filter.remove(item) }
                                    if filter.count == items.count { filter = [] }
                                }
                            }
                        ))
                        .font(.system(size: 11))
                        .toggleStyle(.checkbox)
                    }
                }
                .padding(.leading, 4)
                if !filter.isEmpty {
                    Text("Watching \(filter.count) of \(items.count)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Shortcut recorder button

struct ShortcutRecorderButton: View {
    @Binding var flags: UInt
    @Binding var code: UInt16
    @State private var isRecording = false

    var body: some View {
        Button {
            guard !isRecording else { return }
            isRecording = true
            var token: Any?
            token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
                guard !mods.isEmpty else { return event }
                DispatchQueue.main.async {
                    self.flags = mods.rawValue
                    self.code = event.keyCode
                    self.isRecording = false
                    if let t = token { NSEvent.removeMonitor(t) }
                }
                return nil
            }
        } label: {
            Text(isRecording ? "Press keys…" : shortcutLabel)
                .font(.system(size: 11, design: .monospaced))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(isRecording ? Color.accentColor.opacity(0.12) : Color(NSColor.controlBackgroundColor))
                .cornerRadius(5)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.gray.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var shortcutLabel: String {
        let f = NSEvent.ModifierFlags(rawValue: flags)
        var s = ""
        if f.contains(.control) { s += "⌃" }
        if f.contains(.option)  { s += "⌥" }
        if f.contains(.shift)   { s += "⇧" }
        if f.contains(.command) { s += "⌘" }
        s += keyChar(code)
        return s.isEmpty ? "None" : s
    }

    private func keyChar(_ c: UInt16) -> String {
        let map: [UInt16: String] = [
            0:"A", 1:"S", 2:"D", 3:"F", 4:"H", 5:"G", 6:"Z", 7:"X", 8:"C", 9:"V",
            11:"B", 12:"Q", 13:"W", 14:"E", 15:"R", 16:"Y", 17:"T", 31:"O", 32:"U",
            34:"I", 37:"L", 38:"J", 40:"K", 45:"N", 46:"M", 49:"Space", 50:"`", 27:"-"
        ]
        return map[c] ?? "·"
    }
}
