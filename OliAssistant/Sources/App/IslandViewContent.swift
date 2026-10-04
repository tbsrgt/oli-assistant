import SwiftUI

// MARK: - Dispatch view content by IslandView

struct IslandViewContent: View {
    let view: IslandView
    @ObservedObject var state: AppState

    var body: some View {
        switch view {
        case .overview:  OverviewView(state: state)
        case .empty:     EmptyStateView(state: state)
        case .approval:  ApprovalView(state: state)
        case .question:  QuestionView(state: state)
        case .error:     ErrorView(state: state)
        case .finished:  FinishedView(state: state)
        case .confused:  ConfusedView()
        case .upload:    UploadView(state: state)
        case .uploading: UploadingView(state: state)
        case .choose:    ChooseView(state: state)
        case .mail:      MailComposeView(state: state)
        case .prompt:    PromptView(state: state)
        case .terminal:  TerminalPanelView(state: state)
        case .searching: SearchingView(state: state)
        case .result:    ResultView(state: state)
        case .note:      NoteView(state: state)
        case .settings:  SettingsIslandView(state: state)
        case .greeting:  EmptyView()  // GreetingCanvasView overlaid in IslandRootView
        case .wardrobe:  WardrobeView(state: state)
        }
    }
}

// MARK: - Overview

struct OverviewView: View {
    @ObservedObject var state: AppState
    @State private var showingN8nDetail = false
    @State private var activeDiffId: Int? = nil

    var agent: AgentTask? { state.focusTask }

    var body: some View {
        HStack(spacing: 10) {
            // Left card: title row + ticker below + ↗ button overlay
            ZStack(alignment: .topLeading) {
                CardBackground(wash: nil)

                // Title row + ticker stacked (or integration card)
                if let agent = agent {
                    if agent.isIntegration {
                        IntegrationCardView(task: agent, showingDetail: $showingN8nDetail, onDiffTap: { diffIdx in
                            withAnimation(.easeIn(duration: 0.16)) { activeDiffId = diffIdx }
                        })
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(hex: agent.color))
                                    .frame(width: 7, height: 7)
                                Text(agent.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(Color(hex: "#F5F6F8"))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .layoutPriority(1)
                                Text({ () -> String in
                                    switch agent.source {
                                    case .claudeCode: return "Claude Code"
                                    case .agent:      return "Agent"
                                    case .n8n:        return "n8n"
                                    }
                                }())
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(hex: "#8E939C"))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer(minLength: 2)
                                if agent.steps.count > 1 {
                                    Text("\(min(agent.stepIndex + 1, agent.steps.count))/\(agent.steps.count)")
                                        .font(.system(size: 11))
                                        .foregroundColor(Color(hex: "#6B7079"))
                                        .fixedSize()
                                }
                            }
                            .padding(.top, 6)
                            .padding(.leading, 108)
                            .padding(.trailing, 36)

                            TickerView(task: agent, onDiffTap: { diffIdx in
                                withAnimation(.easeIn(duration: 0.16)) { activeDiffId = diffIdx }
                            })
                                .frame(height: 44)
                                .padding(.top, 6)
                                .padding(.leading, 108)
                                .padding(.trailing, 12)
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.top, 4)
                    }
                }

                // Plan detail overlays on top of normal content (GitHub build, home view only)
                #if !APPSTORE
                if state.showingPlanDetail {
                    CardBackground(wash: nil)
                    ClaudePlanCardView(usage: state.claudePlanUsage)
                        .transition(.opacity)
                }
                #endif

                // Diff overlay — replaces ticker when a diff step is tapped
                if let diffId = activeDiffId,
                   let task = agent,
                   let diff = state.sessionDiffs[task.id]?.first(where: { $0.id == diffId }) {
                    CardBackground(wash: nil)
                    DiffCardView(diff: diff, onDismiss: { activeDiffId = nil })
                        .transition(.opacity)
                }

                // ↗ jump button — last in ZStack so it renders on top; hidden while any detail is open
                #if !APPSTORE
                let hideJumpButton = showingN8nDetail || state.showingPlanDetail || activeDiffId != nil
                #else
                let hideJumpButton = showingN8nDetail || activeDiffId != nil
                #endif
                if !hideJumpButton {
                    Button(action: { openAgentTarget(agent) }) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(Color(hex: "#5F646D"))
                            .frame(width: 16, height: 16)
                            .background(Color.white.opacity(0.07))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    .padding(.trailing, 10)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .frame(width: 322)

            // Right card: agent pills
            CardBackground(wash: nil) {
                AgentPillsView(state: state)
            }
        }
        .onChange(of: state.focusId) { _, new in
            showingN8nDetail = false
            activeDiffId = nil
            #if !APPSTORE
            withAnimation(.easeIn(duration: 0.16)) { state.showingPlanDetail = false }
            #endif
            if new == "integration_github" { GithubPoller.shared.refreshIfStale() }
        }
        #if !APPSTORE
        .onChange(of: state.view) { _, v in
            if v != .overview { state.showingPlanDetail = false; activeDiffId = nil }
        }
        #endif
        .onChange(of: state.mode) { _, m in
            #if !APPSTORE
            if m != .expanded { state.showingPlanDetail = false; activeDiffId = nil }
            #endif
            if m == .expanded && state.focusId == "integration_github" {
                GithubPoller.shared.refreshIfStale()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .islandToggleDiff)) { _ in
            if let id = activeDiffId {
                withAnimation(.easeIn(duration: 0.16)) { activeDiffId = nil }
                _ = id
            } else if let task = state.focusTask,
                      let last = state.sessionDiffs[task.id]?.last {
                withAnimation(.easeIn(duration: 0.16)) { activeDiffId = last.id }
            }
        }
    }

    private func openAgentTarget(_ task: AgentTask?) {
        guard let task else { return }
        switch task.id {
        case "integration_claude":
            let vscodeBundleId = "com.microsoft.VSCode"
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == vscodeBundleId }) {
                app.activate(options: .activateIgnoringOtherApps)
            } else {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Visual Studio Code.app"))
            }
        case "integration_resend":
            NSWorkspace.shared.open(URL(string: "https://resend.com/emails")!)
        case "integration_vercel":
            NSWorkspace.shared.open(URL(string: "https://vercel.com/dashboard")!)
        case "integration_espace":
            NSWorkspace.shared.open(EspacePoller.adminURL)
        case "integration_agenda":
            NSWorkspace.shared.open(AgendaPoller.calendarURL)
        case "integration_instagram":
            let name = state.social?.username ?? ""
            if let u = URL(string: name.isEmpty ? "https://www.instagram.com" : "https://www.instagram.com/\(name)/") {
                NSWorkspace.shared.open(u)
            }
        case "integration_sites":
            // The site in trouble first, else the first watched site.
            let checks = state.siteChecks.sorted { $0.status.order < $1.status.order }
            if let s = checks.first.flatMap({ URL(string: $0.url) }) ?? SitesPoller.targets.first.flatMap({ URL(string: $0.url) }) {
                NSWorkspace.shared.open(s)
            }
        case "integration_github":
            NSWorkspace.shared.open(URL(string: "https://github.com/pulls")!)
        case "integration_n8n":
            if let urlStr = KeychainStore.shared.get("n8n-url"), let url = URL(string: urlStr) {
                NSWorkspace.shared.open(url)
            }
        case "integration_stripe":
            NSWorkspace.shared.open(URL(string: "https://dashboard.stripe.com/payments")!)
        case "integration_notion":
            NSWorkspace.shared.open(URL(string: "https://notion.so")!)
        case "integration_calcom":
            NSWorkspace.shared.open(URL(string: "https://app.cal.com/bookings")!)
        case "agent_cursor":
            #if !APPSTORE
            if let url = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.todesktop.230313mzl4w4u92") {
                NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
            }
            #endif
        case "agent_codex":
            #if !APPSTORE
            if let url = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.openai.codex") {
                NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
            }
            #endif
        case "agent_gemini", "agent_antigravity":
            #if !APPSTORE
            let terminalBundleIds = ["com.apple.Terminal", "com.googlecode.iterm2",
                                     "net.kovidgoyal.kitty", "com.mitchellh.ghostty"]
            if let hit = terminalBundleIds.compactMap({ id in
                NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == id }
            }).first {
                hit.activate(options: .activateIgnoringOtherApps)
            }
            #endif
        case "ai_anthropic":
            switchChatProvider(.anthropic)
        case "ai_google":
            switchChatProvider(.google)
        case "ai_openai":
            switchChatProvider(.openai)
        case "ai_ollama":
            switchChatProvider(.ollama)
        case "ai_lmstudio":
            switchChatProvider(.lmstudio)
        case "integration_music":
            #if !APPSTORE
            MusicController.shared.openMusic()
            #endif
        default:
            // Non-integration real tasks
            if task.source == .n8n {
                if let urlStr = KeychainStore.shared.get("n8n-url"), let url = URL(string: urlStr) {
                    NSWorkspace.shared.open(url)
                }
            } else {
                #if !APPSTORE
                let terminalBundleIds = ["com.apple.Terminal", "com.googlecode.iterm2",
                                         "net.kovidgoyal.kitty", "com.mitchellh.ghostty"]
                if let hit = terminalBundleIds.compactMap({ id in
                    NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == id }
                }).first {
                    hit.activate(options: .activateIgnoringOtherApps)
                }
                #endif
            }
        }
    }
}

// MARK: - Empty

struct EmptyStateView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ZStack {
            CardBackground(wash: nil)
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Nothing running right now.")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Drop a file or window, or ask me anything.")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "#9398A1"))
                }
                Spacer()
                PrimaryButton("Ask Claude") {
                    state.view = .prompt
                }
            }
            .padding(.leading, 118)
            .padding(.trailing, 18)
        }
    }
}

// MARK: - Approval

struct ApprovalView: View {
    @ObservedObject var state: AppState

    var approval: ApprovalInfo? { state.pendingApproval }

    var body: some View {
        ZStack {
            CardBackground(wash: .amber)
            VStack(alignment: .leading, spacing: 5) {
                AgentWho(task: state.focusTask, label: "needs permission")
                CodeBlock(text: approval?.command ?? approval?.tool ?? "…")
                HStack(spacing: 8) {
                    SecondaryButton("Deny") {
                        HookServer.shared.sendApprovalDecision("deny")
                    }
                    PrimaryButton("Allow") {
                        HookServer.shared.sendApprovalDecision("allow")
                    }
                    // Codex rejects updatedPermissions, so "Always" is not offered
                    if approval?.pillId != "agent_codex" {
                        SecondaryButton("Always") {
                            HookServer.shared.sendApprovalDecision("always")
                        }
                    }
                }
            }
            .padding(.leading, 116)
            .padding(.trailing, 16)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Question

struct QuestionView: View {
    @ObservedObject var state: AppState
    @State private var questionIndex = 0
    // Per-question selected labels (empty = none chosen yet)
    @State private var selections: [[String]] = []
    // Per-question custom "Other…" text
    @State private var otherTexts: [String] = []
    // Per-question "Other…" mode active
    @State private var showOther: [Bool] = []
    @FocusState private var otherFieldFocused: Bool

    var question: AskQuestion? { state.pendingQuestion }

    var body: some View {
        ZStack {
            CardBackground(wash: .cyan)
            if let q = question, !q.questions.isEmpty {
                let qi = min(questionIndex, q.questions.count - 1)
                let item = q.questions[qi]
                let isLast = qi == q.questions.count - 1
                let isMulti = item.multiSelect
                let curSel = qi < selections.count ? selections[qi] : []
                let curOther = qi < showOther.count ? showOther[qi] : false
                let curOtherText = qi < otherTexts.count ? otherTexts[qi] : ""
                let canProceed = !curSel.isEmpty || (curOther && !curOtherText.isEmpty)

                VStack(alignment: .leading, spacing: 4) {
                    // Header row: agent name + question counter + "Reply in terminal" link
                    HStack(spacing: 4) {
                        AgentWho(task: nil, label: "Claude Code is asking")
                        Spacer(minLength: 4)
                        if q.questions.count > 1 {
                            Text("\(qi + 1)/\(q.questions.count)")
                                .font(.system(size: 10))
                                .foregroundColor(Color(hex: "#6B7079"))
                        }
                        Button("Reply in terminal") { HookServer.shared.sendQuestionAsk() }
                            .buttonStyle(.plain)
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#6B7079"))
                            .underline()
                    }
                    // Optional short header label above question text
                    if !item.header.isEmpty {
                        Text(item.header)
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#6B7079"))
                    }
                    Text(item.question)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: "#F5F6F8"))
                        .lineLimit(2)
                    // Options (wrapping) or "Other…" compact inline row
                    if curOther {
                        HStack(spacing: 6) {
                            TextField("Your answer…", text: Binding(
                                get: { qi < otherTexts.count ? otherTexts[qi] : "" },
                                set: { v in if qi < otherTexts.count { otherTexts[qi] = v } }
                            ))
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "#F5F6F8"))
                            .focused($otherFieldFocused)
                            .onAppear { otherFieldFocused = true }
                            .onSubmit { commitOtherAndProceed(q: q, qi: qi, isLast: isLast) }
                            .onExitCommand { if qi < showOther.count { showOther[qi] = false } }
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(Color.white.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            Button(isLast ? "Send" : "Next") {
                                commitOtherAndProceed(q: q, qi: qi, isLast: isLast)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(curOtherText.isEmpty ? Color(hex: "#6B7079") : Color(hex: "#F5F6F8"))
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(Color.white.opacity(curOtherText.isEmpty ? 0.05 : 0.15))
                            .clipShape(Capsule())
                            .disabled(curOtherText.isEmpty)
                            Button { if qi < showOther.count { showOther[qi] = false } } label: {
                                Text("✕").font(.system(size: 9))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(Color(hex: "#6B7079"))
                        }
                    } else {
                        ChipFlowLayout(spacing: 6) {
                            ForEach(Array(item.options.enumerated()), id: \.offset) { idx, opt in
                                let isSelected = curSel.contains(opt.label)
                                if isMulti {
                                    Button {
                                        toggleSelection(qi: qi, label: opt.label)
                                    } label: {
                                        Text(opt.label)
                                            .font(.system(size: 12, weight: .medium))
                                            .padding(.horizontal, 8).padding(.vertical, 4)
                                            .background(isSelected ? Color(hex: "#22D3EE").opacity(0.22) : Color.white.opacity(0.07))
                                            .foregroundColor(isSelected ? Color(hex: "#67E8F9") : Color(hex: "#C5C8CD"))
                                            .clipShape(RoundedRectangle(cornerRadius: 7))
                                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(isSelected ? Color(hex: "#22D3EE").opacity(0.55) : Color.white.opacity(0.1), lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                    .keyboardShortcut(KeyEquivalent(Character(String(idx + 1))), modifiers: [])
                                } else {
                                    SecondaryButton(opt.label) {
                                        selectAndProceed(q: q, qi: qi, label: opt.label, isLast: isLast)
                                    }
                                    .keyboardShortcut(KeyEquivalent(Character(String(idx + 1))), modifiers: [])
                                }
                            }
                            // "Other…" implicit free-text option
                            SecondaryButton("Other…") {
                                if qi < showOther.count { showOther[qi] = true }
                            }
                        }
                    }
                    // Send/Next — only for multi-select (and not while "Other…" field is open)
                    if isMulti && !curOther {
                        PrimaryButton(isLast ? "Send" : "Next") {
                            proceedFromQuestion(q: q, qi: qi, isLast: isLast)
                        }
                        .disabled(!canProceed)
                        .opacity(canProceed ? 1 : 0.4)
                    }
                }
                .padding(.leading, 116)
                .padding(.trailing, 16)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear { resetQuestionState() }
        .onChange(of: state.pendingQuestion) { _, _ in resetQuestionState() }
        .onDisappear { HookServer.shared.releaseQuestionFD() }
    }

    private func resetQuestionState() {
        questionIndex = 0
        let count = state.pendingQuestion?.questions.count ?? 0
        selections = Array(repeating: [], count: count)
        otherTexts = Array(repeating: "", count: count)
        showOther  = Array(repeating: false, count: count)
    }

    private func toggleSelection(qi: Int, label: String) {
        guard qi < selections.count else { return }
        if let i = selections[qi].firstIndex(of: label) {
            selections[qi].remove(at: i)
        } else {
            selections[qi].append(label)
        }
    }

    // Single-select: pick a label and immediately advance/send
    private func selectAndProceed(q: AskQuestion, qi: Int, label: String, isLast: Bool) {
        guard qi < selections.count else { return }
        selections[qi] = [label]
        if isLast { sendAnswers(q: q) } else { withAnimation { questionIndex = qi + 1 } }
    }

    // Multi-select Send/Next button
    private func proceedFromQuestion(q: AskQuestion, qi: Int, isLast: Bool) {
        if isLast { sendAnswers(q: q) } else { withAnimation { questionIndex = qi + 1 } }
    }

    // "Other…" confirm
    private func commitOtherAndProceed(q: AskQuestion, qi: Int, isLast: Bool) {
        let text = qi < otherTexts.count ? otherTexts[qi] : ""
        guard !text.isEmpty else { return }
        if qi < selections.count { selections[qi] = [text] }
        if isLast {
            sendAnswers(q: q)
        } else {
            if qi < showOther.count { showOther[qi] = false }
            withAnimation { questionIndex = qi + 1 }
        }
    }

    private func sendAnswers(q: AskQuestion) {
        let answers = AskQuestion.buildAnswers(questions: q.questions, selections: selections)
        HookServer.shared.sendQuestionAnswers(answers)
    }
}

// MARK: - Error

struct ErrorView: View {
    @ObservedObject var state: AppState

    var body: some View {
        let (title, hint) = ErrorView.explain(state.focusTask?.finalLine)
        ZStack {
            CardBackground(wash: .red)
            VStack(alignment: .leading, spacing: 5) {
                AgentWho(task: state.focusTask, label: "Claude Code s’est arrêté")
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text(hint)
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#FF8D97"))
                    .lineLimit(2)
                HStack(spacing: 8) {
                    PrimaryButton("Ouvrir le terminal") { state.view = .terminal }
                    SecondaryButton("OK") {
                        NotificationCenter.default.post(name: .islandCollapse, object: nil)
                    }
                }
            }
            .padding(.leading, 116)
            .padding(.trailing, 16)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Turns the StopFailure reason (stored in finalLine) into a short French title and a next step.
    static func explain(_ reason: String?) -> (String, String) {
        let r = (reason ?? "").lowercased()
        if r.contains("rate") || r.contains("limit") || r.contains("429") {
            return ("Limite d’utilisation atteinte.", "Attends un peu, puis relance la session dans le terminal.")
        }
        if r.contains("auth") || r.contains("401") || r.contains("login") {
            return ("Claude n’est plus connecté.", "Tape /login dans le terminal pour te reconnecter.")
        }
        if r.contains("billing") || r.contains("credit") || r.contains("quota") {
            return ("Problème d’abonnement ou de crédits.", "Vérifie ton compte Claude, puis relance.")
        }
        if r.contains("overload") || r.contains("server") || r.contains("500") || r.contains("529") {
            return ("Les serveurs de Claude sont surchargés.", "Ce n’est pas toi : réessaie dans une minute.")
        }
        if r.contains("context") || r.contains("too long") || r.contains("prompt") {
            return ("La conversation est trop longue.", "Tape /compact dans le terminal, puis continue.")
        }
        let detail = (reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return ("La session a échoué.", detail.isEmpty ? "Regarde le terminal pour le détail." : String(detail.prefix(140)))
    }
}

// MARK: - Finished

struct FinishedView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ZStack {
            CardBackground(wash: .green)
            VStack(alignment: .leading, spacing: 5) {
                AgentWho(task: state.focusTask, label: "Claude Code finished")
                Text({
                    if let fl = state.focusTask?.finalLine { return fl }
                    if let s = state.focusTask?.steps.last(where: { !$0.isDiffStep }) { return s }
                    return "Session finished"
                }())
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 8) {
                    #if !APPSTORE
                    PrimaryButton("Open terminal") {
                        let terminalBundleIds = ["com.apple.Terminal", "com.googlecode.iterm2", "net.kovidgoyal.kitty", "com.mitchellh.ghostty"]
                        let activated = terminalBundleIds.compactMap { id in
                            NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == id }
                        }.first.map { $0.activate(options: .activateIgnoringOtherApps) }
                        if activated == nil {
                            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
                        }
                        NotificationCenter.default.post(name: .islandCollapse, object: nil)
                    }
                    #endif
                    SecondaryButton("OK") {
                        NotificationCenter.default.post(name: .islandCollapse, object: nil)
                    }
                }
            }
            .padding(.leading, 116)
            .padding(.trailing, 16)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Diff Card

struct DiffCardView: View {
    let diff: FileDiff
    let onDismiss: () -> Void

    private var allLines: [DiffLine] { diff.hunks.flatMap { $0.lines } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Button(action: onDismiss) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 8, weight: .medium))
                        Text(diff.name)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundColor(Color(hex: "#F5F6F8"))
                }
                .buttonStyle(.plain)
                Spacer(minLength: 2)
                if diff.added > 0 {
                    Text("+\(diff.added)")
                        .font(.system(size: 10, weight: .medium).monospaced())
                        .foregroundColor(Color(hex: "#22C55E"))
                }
                if diff.removed > 0 {
                    Text("−\(diff.removed)")
                        .font(.system(size: 10, weight: .medium).monospaced())
                        .foregroundColor(Color(hex: "#F4505E"))
                }
                Button(action: { openInEditor(diff) }) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(Color(hex: "#5F646D"))
                        .frame(width: 14, height: 14)
                        .background(Color.white.opacity(0.07))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 6)
            .padding(.bottom, 3)

            // Content
            if diff.tooLarge {
                Text("Diff too large")
                    .font(.system(size: 10.5))
                    .foregroundColor(Color(hex: "#6B7079"))
            } else if allLines.isEmpty {
                Text("No changes")
                    .font(.system(size: 10.5))
                    .foregroundColor(Color(hex: "#6B7079"))
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(allLines.enumerated()), id: \.offset) { _, line in
                            DiffLineRowView(line: line)
                        }
                    }
                }
            }
        }
        .padding(.leading, 108)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onExitCommand { onDismiss() }
    }

    private func openInEditor(_ diff: FileDiff) {
        let path = diff.path
        #if !APPSTORE
        let codePaths = ["/opt/homebrew/bin/code", "/usr/local/bin/code", "/usr/bin/code",
                         "\(NSHomeDirectory())/.nvm/current/bin/code"]
        if let codePath = codePaths.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: codePath)
            // Write: open at line 1; Edit/MultiEdit: open file without line number
            p.arguments = diff.isNewFile ? ["-g", "\(path):1"] : [path]
            try? p.run()
            return
        }
        #endif
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}

struct DiffLineRowView: View {
    let line: DiffLine

    private var bgColor: Color {
        switch line.kind {
        case .added:   return Color(hex: "#22C55E").opacity(0.12)
        case .removed: return Color(hex: "#F4505E").opacity(0.12)
        case .context: return Color.clear
        }
    }
    private var fgColor: Color {
        switch line.kind {
        case .added:   return Color(hex: "#86EFAC")
        case .removed: return Color(hex: "#FCA5A5")
        case .context: return Color(hex: "#6B7079")
        }
    }
    private var symbol: String {
        switch line.kind {
        case .added:   return "+"
        case .removed: return "−"
        case .context: return " "
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(symbol)
                .font(.system(size: 10.5).monospaced())
                .foregroundColor(line.kind == .added ? Color(hex: "#22C55E") :
                                 line.kind == .removed ? Color(hex: "#F4505E") :
                                 Color(hex: "#454850"))
                .frame(width: 12, alignment: .leading)
            Text(line.text)
                .font(.system(size: 10.5).monospaced())
                .foregroundColor(fgColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(bgColor)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Confused

struct ConfusedView: View {
    var body: some View {
        ZStack {
            CardBackground(wash: .pink)
            VStack(alignment: .leading, spacing: 5) {
                Text("Too many hits at once.").font(.system(size: 15, weight: .semibold))
                Text("Give me a sec — back to work in three seconds.")
                    .font(.system(size: 13)).foregroundColor(Color(hex: "#9398A1"))
            }
            .padding(.leading, 128)
            .padding(.trailing, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Upload (drop zone)

struct UploadView: View {
    @ObservedObject var state: AppState
    @State private var dashPhase: CGFloat = 0
    @State private var breathAngle: Double = 0
    // Timer only runs while this is the active tab — killed on deactivation
    @State private var animTimer: Timer? = nil

    private var borderOpacity: Double {
        let breathe = 0.11 + 0.04 * (sin(breathAngle) * 0.5 + 0.5)
        return state.fileDragOver ? 0.65 : breathe
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(hex: "#0E0F11"))
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    state.fileDragOver
                        ? Color(hex: "#22C55E").opacity(borderOpacity)
                        : Color.white.opacity(borderOpacity),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 5], dashPhase: dashPhase)
                )
            RoundedRectangle(cornerRadius: 20)
                .fill(RadialGradient(
                    colors: [Color(hex: "#22C55E").opacity(state.fileDragOver ? 0.13 : 0), Color.clear],
                    center: .bottom, startRadius: 0, endRadius: 200
                ))
            VStack(alignment: .leading, spacing: 8) {
                Text("Drop your files here")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(state.fileDragOver ? Color(hex: "#34D399") : Color(hex: "#D5D7DB"))
                HStack(spacing: 6) {
                    ForEach(["PDF", "Images", "Code", "Docs"], id: \.self) { label in
                        Text(label)
                            .font(.system(size: 11))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.white.opacity(0.07))
                            .foregroundColor(Color(hex: "#B9BDC4"))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.leading, 196)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: state.view) { _, newView in
            newView == .upload ? startTimer() : stopTimer()
        }
        .onAppear {
            if state.view == .upload { startTimer() }
        }
        .onDisappear { stopTimer() }
    }

    private func startTimer() {
        guard animTimer == nil else { return }
        // 20 fps — smooth enough for slow dash, 3× lighter than 60fps
        animTimer = Timer.scheduledTimer(withTimeInterval: 1.0/20.0, repeats: true) { _ in
            dashPhase  += 1.0          // 20 pt/s march
            breathAngle += 0.9 / 20.0  // advance sin phase at 0.9 rad/s
        }
    }

    private func stopTimer() {
        animTimer?.invalidate()
        animTimer = nil
    }
}

// MARK: - Uploading

struct UploadingView: View {
    @ObservedObject var state: AppState

    // Bar geometry in content coords (content has 10pt H padding each side).
    // Island bar: left=36, right=562 (640-78), width=526.
    // Content bar: left=26, width=526.
    // barTop=58 → island y = content_start(42)+58 = 100; bot cy=103 (center = barTop+3).
    private let barLeft: CGFloat  = 26
    private let barWidth: CGFloat = 526
    private let barTop: CGFloat   = 58

    var body: some View {
        // TimelineView fires at display refresh rate — progress derived from elapsed wall time,
        // not from @Published uploadProgress (which only flips to 1.0 at completion).
        TimelineView(.animation) { tl in
            let elapsed: Double = {
                guard let start = state.uploadStartTime else { return 0 }
                return tl.date.timeIntervalSince(start)
            }()
            let t        = min(1.0, max(0, elapsed / state.uploadDuration))
            let progress = CGFloat(t * (2 - t))          // ease-out quad
            let fillWidth = max(0, barWidth * progress)
            let isDone   = state.uploadProgress >= 0.999  // only true after handle() sets it

            ZStack(alignment: .topLeading) {
                // Background: dark base
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(hex: "#141518"))

                // Permanent green radial wash — brighter at completion
                RoundedRectangle(cornerRadius: 20)
                    .fill(RadialGradient(
                        colors: [Color(hex: "#34D399").opacity(isDone ? 0.28 : 0.14), Color.clear],
                        center: UnitPoint(x: 0.5, y: 1.4),
                        startRadius: 0,
                        endRadius: 260
                    ))

                // Bar track
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.09))
                    .frame(width: barWidth, height: 6)
                    .offset(x: barLeft, y: barTop)

                // Bar fill
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(
                        colors: [Color(hex: "#1FA87A"), Color(hex: "#34D399")],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(width: fillWidth, height: 6)
                    .offset(x: barLeft, y: barTop)

                // Glow trail behind dot leading edge
                if progress > 0.01 {
                    Ellipse()
                        .fill(Color(hex: "#6EE7B7").opacity(0.45))
                        .frame(width: 28, height: 12)
                        .blur(radius: 5)
                        .offset(x: barLeft + fillWidth - 14, y: barTop - 3)
                }

                // Text row — filename + % (above bar)
                HStack(spacing: 0) {
                    if isDone {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "#34D399"))
                        Text("  \(state.droppedFile?.name ?? "File")")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(Color(hex: "#34D399"))
                            .lineLimit(1).truncationMode(.middle)
                    } else {
                        Text("Uploading \(state.droppedFile?.name ?? "file")")
                            .font(.system(size: 12.5))
                            .foregroundColor(Color(hex: "#A9ADB5"))
                            .lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text("\(Int(progress * 100)) %")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(Color(hex: "#A9ADB5"))
                            .monospacedDigit()
                    }
                }
                .frame(width: barWidth)
                .offset(x: barLeft, y: barTop - 22)

                // Subtle top border (same as CardBackground)
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.035), lineWidth: 1)
            }
        }
    }
}

// MARK: - Choose

struct ChooseView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ZStack(alignment: .leading) {
            CardBackground(wash: nil)
            VStack(alignment: .leading, spacing: 8) {
                let fileName = state.droppedFile?.name ?? "file"
                (Text(fileName).font(.system(size: 14, weight: .semibold)) + Text(" is ready.").font(.system(size: 14, weight: .semibold)))
                Text("Qu’est-ce que j’en fais ?").font(.system(size: 12.5)).foregroundColor(Color(hex: "#9398A1"))
                HStack(spacing: 8) {
                    PrimaryButton("Poser une question") { state.view = .prompt }
                    SecondaryButton("Envoyer par mail") { state.view = .mail }
                }
            }
            .padding(.leading, 98)
            .padding(.trailing, 18)
        }
    }
}


// MARK: - Prompt (chat)

struct PromptView: View {
    @ObservedObject var state: AppState
    @State private var text: String = ""
    @FocusState private var focused: Bool
    @State private var showModelPicker = false

    var body: some View {
        ZStack(alignment: .leading) {
            CardBackground(wash: .indigo)

            VStack(alignment: .leading, spacing: 6) {
                if let ctx = state.promptContext {
                    ContextChip(context: ctx).padding(.top, 4)
                }

                if !state.chatHistory.isEmpty {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(state.chatHistory) { msg in
                                    ChatBubble(message: msg).id(msg.id)
                                }
                                if state.stateOverride != nil {
                                    HStack { TypingDotsView(); Spacer(minLength: 32) }
                                        .id("typing")
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .onChange(of: state.chatHistory) { _, _ in
                            if let last = state.chatHistory.last(where: { !$0.content.isEmpty }) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                        .onChange(of: state.stateOverride) { _, v in
                            if v != nil {
                                withAnimation { proxy.scrollTo("typing", anchor: .bottom) }
                            } else if let last = state.chatHistory.last(where: { !$0.content.isEmpty }) {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                        .onAppear {
                            if let last = state.chatHistory.last {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    Spacer()
                }

                HStack(spacing: 0) {
                    Spacer()
                    if state.chatProvider == .anthropic && ClaudeService.shared.usesClaudeCode {
                        // Oculot: the chat runs on the user's own Claude — nothing to pick.
                        HStack(spacing: 5) {
                            Image(systemName: "sparkles").font(.system(size: 9, weight: .semibold))
                                .foregroundColor(Color(hex: "#E07950"))
                            Text("Ton Claude · \(ClaudeService.claudeCodeModel.label)").font(.system(size: 10.5, weight: .medium))
                                .foregroundColor(Color(hex: "#9398A1"))
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                        .help("Le chat utilise ton Claude Code (ton abonnement).")
                    } else {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            showModelPicker.toggle()
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color(hex: state.chatProvider.accentHex))
                                .frame(width: 6, height: 6)
                            Text(state.activeChatModel)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundColor(Color(hex: "#7B8089"))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 8))
                                .foregroundColor(Color(hex: "#5C6370"))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showModelPicker, arrowEdge: .bottom) {
                        ModelPickerView(state: state, isPresented: $showModelPicker)
                            .frame(width: 300)
                    }
                    }
                }
                .padding(.horizontal, 10)

                HStack(spacing: 8) {
                    TextField(state.chatHistory.isEmpty ? "Ask me anything…" : "Continue…", text: $text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($focused)
                        .onSubmit { sendMessage() }

                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(hex: "#0B0C0E"))
                    }
                    .buttonStyle(SendButtonStyle())
                    .disabled(text.isEmpty)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.white.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .simultaneousGesture(TapGesture().onEnded { focused = true })
            }
            .padding(.leading, 84)
            .padding(.trailing, 16)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
        .padding(.bottom, 10)
        .onAppear { focused = true }
        .onChange(of: state.view) { _, view in
            if view == .prompt {
                state.fetchModelsIfNeeded(for: state.chatProvider)
            }
        }
        .onChange(of: state.chatProvider) { _, provider in
            if state.view == .prompt {
                state.fetchModelsIfNeeded(for: provider)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .islandSendMessage)) { _ in
            guard state.view == .prompt else { return }
            sendMessage()
        }
        .onReceive(NotificationCenter.default.publisher(for: .islandNewConversation)) { _ in
            guard state.view == .prompt else { return }
            text = ""
            state.chatHistory = []
            ClaudeService.shared.clearConversation()
            focused = true
        }
    }

    private func sendMessage() {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        text = ""
        focused = false
        state.chatHistory.append(ChatMessage(role: .user, content: query))
        state.stateOverride = .thinking
        Task {
            await ClaudeService.shared.chat(query: query, context: state.promptContext, state: state)
            await MainActor.run { focused = true }
        }
    }
}


// MARK: - Model / provider picker

/// Wrapping horizontal flow layout — used by ModelPickerView and QuestionView.
struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let r = rows(maxW: proposal.replacingUnspecifiedDimensions().width, subviews: subviews)
        return r.size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let r = rows(maxW: bounds.width, subviews: subviews)
        for (idx, pt) in r.placements.enumerated() {
            subviews[idx].place(at: CGPoint(x: bounds.minX + pt.x, y: bounds.minY + pt.y), proposal: .unspecified)
        }
    }
    private func rows(maxW: CGFloat, subviews: Subviews) -> (size: CGSize, placements: [(x: CGFloat, y: CGFloat)]) {
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, maxX: CGFloat = 0
        var pts: [(x: CGFloat, y: CGFloat)] = []
        for sv in subviews {
            let sz = sv.sizeThatFits(.unspecified)
            if x + sz.width > maxW, x > 0 { x = 0; y += lineH + spacing; lineH = 0 }
            pts.append((x: x, y: y))
            x += sz.width + spacing
            lineH = max(lineH, sz.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: max(maxX, 0), height: y + lineH), pts)
    }
}

struct ModelPickerView: View {
    @ObservedObject var state: AppState
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Provider chips — wrap; hide local providers when not connected and not already active
            let visibleProviders = ChatProvider.allCases.filter { p in
                if p == .ollama   { return !AppState.shared.ollamaServerURL.isEmpty   || state.chatProvider == .ollama }
                if p == .lmstudio { return !AppState.shared.lmstudioServerURL.isEmpty || state.chatProvider == .lmstudio }
                return true
            }
            ChipFlowLayout(spacing: 6) {
                ForEach(visibleProviders, id: \.self) { provider in
                    Button {
                        guard provider != state.chatProvider else { return }
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                            state.chatProvider = provider
                        }
                        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.surprised)
                        SoundEngine.shared.play("pop")
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color(hex: provider.accentHex))
                                .frame(width: 7, height: 7)
                            Text(provider.displayName)
                                .font(.system(size: 12, weight: state.chatProvider == provider ? .semibold : .regular))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(state.chatProvider == provider
                                    ? Color(hex: provider.accentHex).opacity(0.18)
                                    : Color.white.opacity(0.06))
                        .overlay(Capsule().stroke(
                            state.chatProvider == provider
                                ? Color(hex: provider.accentHex).opacity(0.5)
                                : Color.white.opacity(0.1),
                            lineWidth: 1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().opacity(0.2)

            // Model list for current provider — fetched dynamically
            modelListView
                .frame(height: 260, alignment: .top)
        }
        .padding(14)
        .background(Color(hex: "#16171B"))
        .onAppear {
            // Force-refresh local providers every time the picker opens
            if state.chatProvider.isLocal {
                state.fetchedProviderModels[state.chatProvider] = nil
                state.providerModelFetchError[state.chatProvider] = nil
            }
            state.fetchModelsIfNeeded(for: state.chatProvider)
        }
        .onChange(of: state.chatProvider) { _, provider in
            if provider.isLocal {
                state.fetchedProviderModels[provider] = nil
                state.providerModelFetchError[provider] = nil
            }
            state.fetchModelsIfNeeded(for: provider)
        }
    }

    @ViewBuilder
    private var modelListView: some View {
        if state.loadingProviderModels.contains(state.chatProvider) {
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.7)
                Text("Loading models…")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#8A8F98"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        } else if let error = state.providerModelFetchError[state.chatProvider] {
            Text(error)
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#8A8F98"))
                .padding(.vertical, 4)
        } else if let models = state.fetchedProviderModels[state.chatProvider] {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(models, id: \.id) { model in
                        Button {
                            switch state.chatProvider {
                            case .anthropic: state.claudeModel = model.id
                            case .google:    state.googleChatModel = model.id
                            case .openai:    state.openAIChatModel = model.id
                            case .ollama:    state.ollamaChatModel = model.id
                            case .lmstudio:  state.lmstudioChatModel = model.id
                            }
                            isPresented = false
                            SoundEngine.shared.play("blip")
                        } label: {
                            HStack {
                                Text(model.label)
                                    .font(.system(size: 12))
                                    .foregroundColor(state.activeChatModel == model.id
                                                     ? Color(hex: state.chatProvider.accentHex)
                                                     : Color(hex: "#C8CDD4"))
                                Spacer()
                                if state.activeChatModel == model.id {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(Color(hex: state.chatProvider.accentHex))
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(state.activeChatModel == model.id
                                        ? Color(hex: state.chatProvider.accentHex).opacity(0.1)
                                        : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        if !message.content.isEmpty {
            HStack(alignment: .top) {
                if message.role == .user {
                    Spacer(minLength: 32)
                    Text(message.content)
                        .font(.system(size: 12.5))
                        .foregroundColor(Color(hex: "#F1F2F4"))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.white.opacity(0.13))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    ChatMarkdownView(markdown: message.content)
                    Spacer(minLength: 8)
                }
            }
        }
    }
}

struct TypingDotsView: View {
    @State private var phase = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color(hex: "#6B7079"))
                    .frame(width: 5, height: 5)
                    .scaleEffect(phase ? 1.2 : 0.6)
                    .animation(
                        .easeInOut(duration: 0.45).repeatForever().delay(Double(i) * 0.14),
                        value: phase
                    )
            }
        }
        .padding(.horizontal, 2).padding(.vertical, 4)
        .onAppear { phase = true }
    }
}

// MARK: - Searching

struct SearchingView: View {
    @ObservedObject var state: AppState

    var label: String {
        switch state.promptContext {
        case .window(_, let title, _): return "Claude is reading \(title)…"
        case .file(let name, _): return "Claude is reading \(name)…"
        case nil: return "Claude is searching…"
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            CardBackground(wash: .indigo)

            VStack(alignment: .leading, spacing: 8) {
                if let ctx = state.promptContext {
                    ContextChip(context: ctx)
                }
                ShimmeringText(label)
                    .font(.system(size: 13.5))
            }
            .padding(.leading, 84)
            .padding(.trailing, 16)
        }
    }
}

// MARK: - Result

struct ResultView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ZStack(alignment: .leading) {
            CardBackground(wash: .green)

            if let result = state.searchResult {
                VStack(alignment: .leading, spacing: 7) {
                    Text(result.title)
                        .font(.system(size: 15, weight: .semibold))

                    VStack(spacing: 4) {
                        ForEach(result.items.prefix(3), id: \.label) { item in
                            HStack {
                                Text(item.label).font(.system(size: 12.5, weight: .semibold))
                                Spacer()
                                Text(item.detail).font(.system(size: 12.5)).foregroundColor(Color(hex: "#9398A1"))
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    if let note = result.note {
                        Text(note).font(.system(size: 11)).foregroundColor(Color(hex: "#6E737C"))
                    }

                    HStack(spacing: 8) {
                        // The URL comes from the model, which may have read attacker-controlled
                        // files or pages: only plain web links may leave the app.
                        let openURL = safeWebURL(result.items.first?.url)
                        PrimaryButton("Open") {
                            if let openURL { NSWorkspace.shared.open(openURL) }
                        }
                        .disabled(openURL == nil)
                        .help(openURL?.absoluteString ?? "")
                        SecondaryButton("Copy") {
                            let text = result.items.map { "\($0.label): \($0.detail)" }.joined(separator: "\n")
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        }
                        SecondaryButton("Close") { state.view = state.tasks.isEmpty ? .empty : .overview }
                    }
                }
                .padding(.leading, 84)
                .padding(.trailing, 16)
            }
        }
    }
}

// MARK: - Note (short message, auto-closes)

struct NoteView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ZStack(alignment: .leading) {
            CardBackground(wash: nil)
            VStack(alignment: .leading, spacing: 4) {
                Text(state.noteMessage ?? "")
                    .font(.system(size: 15, weight: .semibold))
            }
            .padding(.leading, 98)
        }
    }
}

// MARK: - Integration card (overview left card when an integration pill is focused)

struct IntegrationCardView: View {
    let task: AgentTask
    @Binding var showingDetail: Bool
    @State private var espaceSelected: Int = 0
    @State private var sitesSelectedId: String = ""
    @State private var agendaSelected: Int = 0
    var onDiffTap: ((Int) -> Void)? = nil
    @ObservedObject private var appState = AppState.shared
    @State private var githubDetailSection: GitHubDetailSection = .myPRs

    private var isConfigured: Bool {
        switch task.id {
        case "integration_claude":
            #if APPSTORE
            // Sandboxed: can't read ~/.claude directly — check install flag set by HookServer
            return UserDefaults.standard.bool(forKey: "oliHooksInstalled")
            #else
            let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let hooks = json["hooks"] as? [String: Any],
                  let ss = hooks["SessionStart"] as? [[String: Any]] else { return false }
            return ss.contains { ($0["hooks"] as? [[String: Any]])?.contains {
                HookServer.isOliHookCommand($0["command"] as? String)
            } ?? false }
            #endif
        case "agent_gemini":
            #if !APPSTORE
            return HookServer.geminiHooksInstalled()
            #else
            return false
            #endif
        case "agent_antigravity":
            #if !APPSTORE
            return HookServer.agyHooksInstalled()
            #else
            return false
            #endif
        case "agent_cursor", "agent_codex":
            return false  // coming soon
        case "integration_music":
            #if !APPSTORE
            return true  // Apple Music is always installed on macOS
            #else
            return false
            #endif
        case "ai_anthropic":  return KeychainStore.shared.get("anthropic-api-key") != nil
        case "ai_google":     return KeychainStore.shared.get("google-api-key")    != nil
        case "ai_openai":     return KeychainStore.shared.get("openai-api-key")    != nil
        case "ai_ollama":     return !AppState.shared.ollamaServerURL.isEmpty
        case "ai_lmstudio":   return !AppState.shared.lmstudioServerURL.isEmpty
        case "integration_resend":  return KeychainStore.shared.get("resend-api-key") != nil
        case "integration_n8n":     return KeychainStore.shared.get("n8n-api-key")    != nil
        case "integration_vercel":  return KeychainStore.shared.get("vercel-token")   != nil
        case "integration_espace":  return KeychainStore.shared.get("espace-token")   != nil
        case "integration_sites":   return !appState.siteChecks.isEmpty || !SitesPoller.targets.isEmpty
        case "integration_instagram": return KeychainStore.shared.get("instagram-token") != nil
        case "integration_agenda":  return KeychainStore.shared.get("agenda-ics-url") != nil
        case "integration_github":  return KeychainStore.shared.get("github-token")   != nil
        case "integration_stripe":  return KeychainStore.shared.get("stripe-api-key") != nil
        case "integration_notion":  return KeychainStore.shared.get("notion-api-key") != nil
        case "integration_calcom":  return KeychainStore.shared.get("calcom-api-key") != nil
        default: return false
        }
    }

    private var openURL: URL? {
        switch task.id {
        case "integration_claude":  return nil  // uses terminal button below
        case "integration_resend":  return URL(string: "https://resend.com/emails")
        case "integration_n8n":
            if let s = KeychainStore.shared.get("n8n-url") { return URL(string: s) }
            return nil
        case "integration_vercel":  return URL(string: "https://vercel.com/dashboard")
        case "integration_espace":  return EspacePoller.adminURL
        case "integration_sites":   return nil  // the list view has its own buttons
        case "integration_agenda":  return AgendaPoller.calendarURL
        case "integration_instagram":
            let name = appState.social?.username ?? ""
            return URL(string: name.isEmpty ? "https://www.instagram.com" : "https://www.instagram.com/\(name)/")
        case "integration_github":  return URL(string: "https://github.com")
        case "integration_stripe":  return URL(string: "https://dashboard.stripe.com/payments")
        case "integration_notion":  return URL(string: "https://notion.so")
        case "integration_calcom":  return URL(string: "https://app.cal.com/bookings")
        default: return nil
        }
    }

    // Workspace/agent pill with active session: show ticker layout
    private var agentSessionActive: Bool {
        guard let def = PillCatalog.definition(for: task.id) else { return false }
        guard def.category == .workspace || def.category == .agent else { return false }
        return task.state != .idle || !task.steps.isEmpty
    }

    // n8n with a finished execution: show result row instead of "Open n8n" button
    private var n8nHasActivity: Bool {
        task.id == "integration_n8n" && !task.steps.isEmpty &&
        (task.state == .finished || task.state == .error)
    }

    // Espace client with projects loaded
    private var espaceHasData: Bool {
        task.id == "integration_espace" && !appState.espaceClients.isEmpty
    }

    // Sites clients with at least one check done
    private var sitesHasData: Bool {
        task.id == "integration_sites" && !appState.siteChecks.isEmpty
    }
    private var sitesSelected: SiteCheck? {
        appState.siteChecks.first { $0.id == sitesSelectedId }
            ?? appState.siteChecks.sorted { $0.status.order < $1.status.order }.first
    }

    // Agenda Oculot with events loaded (iCal)
    private var agendaHasData: Bool {
        task.id == "integration_agenda" && !appState.agendaEvents.isEmpty
    }

    // Instagram read at least once (or in error: the list explains it)
    private var socialHasData: Bool {
        task.id == "integration_instagram" && appState.social?.fetchedAt != nil
    }

    // Vercel with recent deployments
    private var vercelHasActivity: Bool {
        task.id == "integration_vercel" && !appState.vercelDeployments.isEmpty
    }

    // GitHub with stats or pulse loaded
    private var githubHasData: Bool {
        task.id == "integration_github" && (appState.githubPulse != nil || appState.githubStats != nil)
    }

    // GitHub with pulse loaded (richer card)
    private var githubHasPulse: Bool {
        task.id == "integration_github" && appState.githubPulse != nil
    }

    // Apple Music: show card when a track is loaded (playing or paused) or automation is denied
    private var musicIsActive: Bool {
        #if !APPSTORE
        guard task.id == "integration_music" else { return false }
        if appState.musicAutomationDenied { return true }
        return MusicController.shared.trackTitle != nil
        #else
        return false
        #endif
    }

    private var statusDot: Color {
        #if !APPSTORE
        if task.id == "integration_music" {
            if appState.musicAutomationDenied { return Color(hex: "#F4505E") }
            return appState.musicPlaying ? Color(hex: "#FA2D48") : Color(hex: "#22C55E")
        }
        #endif
        if PillCatalog.definition(for: task.id)?.comingSoon == true { return Color(hex: "#6B7079") }
        return isConfigured ? Color(hex: "#22C55E") : Color(hex: "#F4505E")
    }

    private var statusLabel: String {
        #if !APPSTORE
        if task.id == "integration_music" {
            if appState.musicAutomationDenied { return "Automation not allowed" }
            if appState.musicPlaying { return "Playing · \(MusicController.shared.trackTitle ?? "Unknown")" }
            return "Not playing"
        }
        #endif
        if PillCatalog.definition(for: task.id)?.comingSoon == true { return "Coming soon" }
        if task.id == "integration_sites" {
            return isConfigured ? "\(SitesPoller.targets.count) sites · vérification en cours…" : "Aucun site"
        }
        let isHooks = task.id == "agent_gemini" || task.id == "agent_antigravity"
        let isAI    = ChatProvider(pillID: task.id) != nil
        if isConfigured {
            if isHooks { return "Hooks installed" }
            if isAI {
                let provider = ChatProvider(pillID: task.id)!
                if provider.isLocal {
                    let model = provider == .ollama ? appState.ollamaChatModel : appState.lmstudioChatModel
                    return "Connected · \(model)"
                }
                let model: String
                switch task.id {
                case "ai_anthropic": model = appState.claudeModel
                case "ai_google":    model = appState.googleChatModel
                case "ai_openai":    model = appState.openAIChatModel
                default:             model = ""
                }
                return "Key configured · \(model)"
            }
            return "Connecté · chargement…"
        } else {
            if isHooks { return "Hooks not installed" }
            if isAI {
                let provider = ChatProvider(pillID: task.id)!
                return provider.isLocal ? "Non connecté" : "Clé à ajouter dans les Réglages"
            }
            return "Clé à ajouter dans les Réglages"
        }
    }

    var body: some View {
        if showingDetail && espaceHasData {
            EspaceDetailView(client: appState.espaceClients[min(espaceSelected, appState.espaceClients.count - 1)]) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { showingDetail = false }
            }
            .transition(.opacity)
        } else if espaceHasData {
            EspaceListView(clients: appState.espaceClients, alerts: appState.espaceAlerts, onOpen: { i in
                espaceSelected = i
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { showingDetail = true }
            })
            .transition(.opacity)
        } else if showingDetail && sitesHasData, let site = sitesSelected {
            SitesDetailView(site: site, audit: appState.siteAudits[site.url]) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { showingDetail = false }
            }
            .transition(.opacity)
        } else if sitesHasData {
            SitesListView(checks: appState.siteChecks, audits: appState.siteAudits, onOpen: { id in
                sitesSelectedId = id
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { showingDetail = true }
            })
            .transition(.opacity)
        } else if showingDetail && agendaHasData {
            AgendaDetailView(event: appState.agendaEvents[min(agendaSelected, appState.agendaEvents.count - 1)]) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { showingDetail = false }
            }
            .transition(.opacity)
        } else if agendaHasData {
            AgendaListView(events: appState.agendaEvents, onOpen: { i in
                agendaSelected = i
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { showingDetail = true }
            })
            .transition(.opacity)
        } else if socialHasData, let snap = appState.social {
            SocialListView(snapshot: snap)
                .transition(.opacity)
        } else if showingDetail && vercelHasActivity {
            VercelDetailView(deployment: appState.vercelDeployments[0]) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { showingDetail = false }
            }
            .transition(.opacity)
        } else if vercelHasActivity {
            VercelDeploymentListView(deployments: appState.vercelDeployments, onOpenDetail: {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { showingDetail = true }
            })
            .transition(.opacity)
        } else if showingDetail && githubHasPulse {
            GitHubDetailView(
                section: githubDetailSection,
                pulse: appState.githubPulse!,
                activity: appState.githubActivity,
                stats: appState.githubStats,
                onBack: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { showingDetail = false }
                }
            )
            .transition(.opacity)
        } else if githubHasPulse {
            GitHubPulseCardView(
                pulse: appState.githubPulse!,
                stats: appState.githubStats,
                activity: appState.githubActivity,
                onTapSection: { section in
                    githubDetailSection = section
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { showingDetail = true }
                }
            )
            .transition(.opacity)
        } else if githubHasData {
            GitHubStatsCardView(stats: appState.githubStats!)
                .transition(.opacity)
        } else if musicIsActive {
            #if !APPSTORE
            MusicCardView()
                .transition(.opacity)
            #endif
        } else if agentSessionActive {
            // Active session view — reuse overview layout
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: task.color))
                        .frame(width: 7, height: 7)
                    Text(task.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#F5F6F8"))
                        .lineLimit(1).truncationMode(.tail)
                        .layoutPriority(1)
                    Text(PillCatalog.definition(for: task.id)?.sessionSubtitle ?? "Agent")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 2)
                    if task.steps.count > 1 {
                        Text("\(min(task.stepIndex + 1, task.steps.count))/\(task.steps.count)")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#6B7079"))
                            .fixedSize()
                    }
                }
                .padding(.top, 6)
                .padding(.leading, 108)
                .padding(.trailing, 36)

                TickerView(task: task, onDiffTap: onDiffTap)
                    .frame(height: 44)
                    .padding(.top, 6)
                    .padding(.leading, 108)
                    .padding(.trailing, 12)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.top, 4)
        } else if task.id == appState.mainPillId && task.id == "integration_claude" {
            // Nothing running in Claude Code: the Oculot dashboard instead of a « Connected » card.
            OculotHomeView(state: appState)
                .transition(.opacity)
        } else {
            // Idle / not connected view — slides in from left when returning from detail
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: task.color))
                        .frame(width: 7, height: 7)
                    Text(PillCatalog.definition(for: task.id)?.name ?? task.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#F5F6F8"))
                    Text(PillCatalog.definition(for: task.id)?.subtitle ?? "Integration")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#8E939C"))
                    Spacer(minLength: 2)
                }
                .padding(.top, 6)
                .padding(.leading, 108)
                .padding(.trailing, 36)

                HStack(spacing: 5) {
                    Circle().fill(statusDot).frame(width: 5, height: 5)
                    Text(statusLabel)
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#6B7079"))
                }
                .padding(.leading, 108)
                .padding(.top, 2)

                HStack(spacing: 8) {
                    if task.id == "integration_claude" {
                        Button("Open Visual Studio Code") { openVSCode() }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: task.color).opacity(0.7))
                            .buttonStyle(.plain)
                    } else if task.id == "agent_cursor" {
                        #if !APPSTORE
                        if let url = NSWorkspace.shared.urlForApplication(
                            withBundleIdentifier: "com.todesktop.230313mzl4w4u92") {
                            Button("Open Cursor") {
                                NSWorkspace.shared.openApplication(at: url, configuration: .init(),
                                                                   completionHandler: nil)
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: task.color).opacity(0.85))
                            .buttonStyle(.plain)
                        }
                        #endif
                    } else if task.id == "agent_codex" {
                        #if !APPSTORE
                        if let url = NSWorkspace.shared.urlForApplication(
                            withBundleIdentifier: "com.openai.codex") {
                            Button("Open Codex") {
                                NSWorkspace.shared.openApplication(at: url, configuration: .init(),
                                                                   completionHandler: nil)
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: task.color).opacity(0.85))
                            .buttonStyle(.plain)
                        }
                        #endif
                    } else if let provider = ChatProvider(pillID: task.id) {
                        if isConfigured {
                            Button("Chat with \(task.name)") {
                                switchChatProvider(provider)
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: task.color).opacity(0.85))
                            .buttonStyle(.plain)
                        }
                    } else if task.id == "integration_music" {
                        #if !APPSTORE
                        Button("Open Music") { MusicController.shared.openMusic() }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: task.color).opacity(0.85))
                            .buttonStyle(.plain)
                        if appState.musicAutomationDenied {
                            Button("Open Settings…") { MusicController.shared.openAutomationSettings() }
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: "#8E939C"))
                                .buttonStyle(.plain)
                        }
                        #endif
                    } else if n8nHasActivity {
                        // Clickable pill — tap to open execution detail
                        let success = task.state == .finished
                        let accent  = success ? Color(hex: "#22C55E") : Color(hex: "#F4505E")
                        Button(action: {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { showingDetail = true }
                        }) {
                            HStack(spacing: 5) {
                                Circle().fill(accent).frame(width: 5, height: 5)
                                Text(task.steps.first ?? "Workflow")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(hex: "#C5C8CD"))
                                    .lineLimit(1).truncationMode(.tail)
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundColor(Color(hex: "#6B7079"))
                            }
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(accent.opacity(0.1))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    } else if let url = openURL {
                        Button("Open \(task.name)") { NSWorkspace.shared.open(url) }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: task.color).opacity(0.85))
                            .buttonStyle(.plain)
                    }
                    // Settings button: shown when not configured, except cursor/codex and music
                    if !isConfigured
                       && task.id != "agent_cursor"
                       && task.id != "agent_codex"
                       && task.id != "integration_music" {
                        Button("Settings…") {
                            let section: String
                            switch PillCatalog.definition(for: task.id)?.category {
                            case .workspace, .agent: section = "agents"
                            case .ai:                section = "chat"
                            default:                 section = "integrations"
                            }
                            NotificationCenter.default.post(name: .openFullSettings, object: section)
                        }
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 108)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.top, 4)
            .transition(.opacity)
        }
    }

    private func openVSCode() {
        let ids = ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.vscodium.codium"]
        let appURL = ids.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first

        // If we have a project folder, open it directly in VS Code
        if let cwd = task.sessionCwd, !cwd.isEmpty, let appURL = appURL {
            NSWorkspace.shared.open(
                [URL(fileURLWithPath: cwd)],
                withApplicationAt: appURL,
                configuration: .init(),
                completionHandler: nil
            )
            return
        }

        // No cwd: activate running instance or launch fresh
        if let running = ids.compactMap({ id in
            NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == id }
        }).first {
            running.activate(options: .activateIgnoringOtherApps)
            return
        }
        if let appURL = appURL {
            NSWorkspace.shared.openApplication(at: appURL, configuration: .init(), completionHandler: nil)
        }
    }

}

// MARK: - Vercel Deployment List View

struct VercelDeploymentListView: View {
    let deployments: [VercelDeployment]
    let onOpenDetail: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: "#7C5CFF"))
                    .frame(width: 7, height: 7)
                Text("Vercel")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                Text("Deployments")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#8E939C"))
            }
            .padding(.top, 6)
            .padding(.leading, 108)
            .padding(.trailing, 36)

            // Deployment rows
            VStack(alignment: .leading, spacing: 3) {
                // First deployment — highlighted, with detail button
                if let first = deployments.first {
                    let accent = Color(hex: first.isSuccess ? "#22C55E" : "#F4505E")
                    HStack(spacing: 5) {
                        Circle().fill(accent).frame(width: 5, height: 5)
                        Text(first.projectName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: "#C5C8CD"))
                            .lineLimit(1).truncationMode(.tail)
                            .layoutPriority(1)
                        Text(first.timeAgo)
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#6B7079"))
                        Button(action: onOpenDetail) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(Color(hex: "#6B7079"))
                                .frame(width: 18, height: 18)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(accent.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }

                // Remaining deployments — plain rows, identical structure → perfect alignment
                ForEach(Array(deployments.dropFirst().prefix(2))) { dep in
                    let accent = Color(hex: dep.isSuccess ? "#22C55E" : "#F4505E")
                    HStack(spacing: 5) {
                        Circle().fill(accent).frame(width: 5, height: 5)
                        Text(dep.projectName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: "#9398A1"))
                            .lineLimit(1).truncationMode(.tail)
                            .layoutPriority(1)
                        Text(dep.timeAgo)
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#6B7079"))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 5)
            .padding(.leading, 108)
            .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 4)
    }
}

// MARK: - Vercel Deployment Detail View

struct VercelDetailView: View {
    let deployment: VercelDeployment
    let onClose: () -> Void

    private var accent: Color { Color(hex: deployment.isSuccess ? "#22C55E" : "#F4505E") }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 7) {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(hex: "#6B7079"))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Circle().fill(accent).frame(width: 6, height: 6)
                Text(deployment.projectName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                    .lineLimit(1).truncationMode(.middle)
                    .layoutPriority(1)
                Spacer(minLength: 2)
                Text(deployment.statusLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(accent)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(accent.opacity(0.14))
                    .clipShape(Capsule())
            }

            // Details
            VStack(alignment: .leading, spacing: 4) {
                if let commit = deployment.commitMessage {
                    Text(commit)
                        .font(.system(size: 10.5))
                        .foregroundColor(Color(hex: "#C5C8CD"))
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    if let branch = deployment.branch {
                        Label(branch, systemImage: "arrow.branch")
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#6B7079"))
                    }
                    Text(deployment.timeAgo + " ago")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#6B7079"))
                }
                Button(action: {
                    if let url = URL(string: "https://\(deployment.url)") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Text(deployment.url)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color(hex: "#7C5CFF").opacity(0.85))
                        .lineLimit(1).truncationMode(.middle)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
        .padding(.leading, 108)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
    }
}


// MARK: - GitHub Pulse Card View

private func ciWorstState(_ prs: [GitHubPR]) -> CIState {
    if prs.contains(where: { $0.ci == .failure }) { return .failure }
    if prs.contains(where: { $0.ci == .pending }) { return .pending }
    if prs.contains(where: { $0.ci == .success }) { return .success }
    return .unknown
}

private func ciColor(_ state: CIState) -> String {
    switch state {
    case .failure: return "#F4505E"
    case .pending: return "#F5A524"
    case .success: return "#22C55E"
    case .unknown: return "#6B7079"
    }
}

private func mainCIWorst(_ repos: [GitHubRepoCI]) -> CIState {
    if repos.contains(where: { $0.ci == .failure }) { return .failure }
    if repos.contains(where: { $0.ci == .pending }) { return .pending }
    if repos.contains(where: { $0.ci == .success }) { return .success }
    return .unknown
}

struct GitHubPulseCardView: View {
    let pulse: GitHubPulse
    let stats: GitHubStats?
    let activity: GitHubActivity?
    let onTapSection: (GitHubDetailSection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: "#F4505E"))
                    .frame(width: 7, height: 7)
                Text("GitHub")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                if let s = stats {
                    // Stars + 7-day mini-row → opens Activity detail
                    Button(action: { onTapSection(.activity) }) {
                        HStack(spacing: 4) {
                            Text("★ \(formatCount(s.totalStars))")
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: "#8E939C"))
                                .lineLimit(1)
                            if let act = activity {
                                HStack(spacing: 2) {
                                    ForEach(act.lastDays(7), id: \.date) { day in
                                        RoundedRectangle(cornerRadius: 1.5)
                                            .fill(contributionColor(day.level))
                                            .frame(width: 7, height: 7)
                                    }
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                } else if let act = activity {
                    // No stats yet but activity loaded — show mini-row only
                    Button(action: { onTapSection(.activity) }) {
                        HStack(spacing: 2) {
                            ForEach(act.lastDays(7), id: \.date) { day in
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(contributionColor(day.level))
                                    .frame(width: 7, height: 7)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Overview")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#8E939C"))
                }
            }
            .padding(.top, 6)
            .padding(.leading, 108)
            .padding(.trailing, 36)

            // Stat rows
            VStack(alignment: .leading, spacing: 4) {
                // My PRs
                let prWorst = ciWorstState(pulse.myPRs)
                let prValue: String = {
                    let n = pulse.myPRs.count
                    if n == 0 { return "0" }
                    let failing = pulse.myPRs.filter { $0.ci == .failure }.count
                    let pending = pulse.myPRs.filter { $0.ci == .pending }.count
                    if failing > 0 { return "\(n) · \(failing) failing" }
                    if pending > 0 { return "\(n) · running" }
                    return "\(n)"
                }()
                GitHubStatRow(
                    icon: "arrow.triangle.pull", iconColor: ciColor(prWorst),
                    label: "My PRs", value: prValue
                ) { onTapSection(.myPRs) }

                // To review
                let reviewCount = pulse.toReview.count
                GitHubStatRow(
                    icon: "eye",
                    iconColor: reviewCount > 0 ? "#8AB4F8" : "#6B7079",
                    label: "To review",
                    value: "\(reviewCount)"
                ) { onTapSection(.toReview) }

                // Default branch CI
                let mainWorst = mainCIWorst(pulse.mainCI)
                let (ciIcon, ciIconColor, ciValue): (String, String, String) = {
                    switch mainWorst {
                    case .failure:
                        let n = pulse.mainCI.filter { $0.ci == .failure }.count
                        return ("xmark.octagon.fill", "#F4505E", "\(n) failing")
                    case .pending:
                        return ("checkmark.seal.fill", "#F5A524", "running")
                    case .success:
                        return ("checkmark.seal.fill", "#22C55E", "all green")
                    case .unknown:
                        return ("checkmark.seal.fill", "#6B7079", pulse.mainCI.isEmpty ? "no repos" : "unknown")
                    }
                }()
                GitHubStatRow(
                    icon: ciIcon, iconColor: ciIconColor,
                    label: "Default branch CI", value: ciValue
                ) { onTapSection(.mainCI) }
            }
            .padding(.top, 6)
            .padding(.leading, 108)
            .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 4)
        .clipped()
    }

    private func formatCount(_ n: Int) -> String {
        if n >= 1000 { return String(format: "%.1fk", Double(n) / 1000) }
        return "\(n)"
    }
}

private struct GitHubStatRow: View {
    let icon: String
    let iconColor: String
    let label: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: iconColor))
                    .frame(width: 14)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#6B7079"))
                Spacer()
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#C5C8CD"))
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - GitHub Detail View

struct GitHubDetailView: View {
    let section: GitHubDetailSection
    let pulse: GitHubPulse
    let activity: GitHubActivity?
    let stats: GitHubStats?
    let onBack: () -> Void
    @ObservedObject private var appState = AppState.shared

    private var title: String {
        switch section {
        case .myPRs:    return "My PRs"
        case .toReview: return "To review"
        case .mainCI:   return "Default branch CI"
        case .activity: return "Activity"
        }
    }

    private var items: [GitHubPR] {
        switch section {
        case .myPRs:    return pulse.myPRs
        case .toReview: return pulse.toReview
        case .mainCI, .activity: return []
        }
    }

    private var repoItems: [GitHubRepoCI] {
        section == .mainCI ? pulse.mainCI : []
    }

    private var totalItems: Int { items.count + repoItems.count }

    var body: some View {
        if section == .activity {
            GitHubActivityDetailContent(
                activity: activity,
                stats: stats,
                login: pulse.login,
                onBack: onBack
            )
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 6) {
                    Button(action: onBack) {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 8, weight: .medium))
                            Text(title)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(Color(hex: "#F5F6F8"))
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 2)
                }
                .padding(.top, 6)
                .padding(.leading, 108)
                .padding(.trailing, 12)

                // List
                if items.isEmpty && repoItems.isEmpty {
                    Text("Nothing here")
                        .font(.system(size: 10.5))
                        .foregroundColor(Color(hex: "#6B7079"))
                        .padding(.top, 8)
                        .padding(.leading, 108)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { idx, pr in
                                GitHubPRRowView(pr: pr, showCI: section == .myPRs,
                                               selected: appState.cardSelection == idx)
                            }
                            ForEach(Array(repoItems.enumerated()), id: \.element.repo) { idx, repo in
                                GitHubRepoCIRowView(repo: repo,
                                                   selected: appState.cardSelection == items.count + idx)
                            }
                        }
                    }
                    .frame(maxHeight: 60)  // 3 rows × 20 pt; rest scrolls
                    .mask(
                        Group {
                            if totalItems > 3 {
                                LinearGradient(
                                    stops: [
                                        .init(color: .black, location: 0),
                                        .init(color: .black, location: 0.8),
                                        .init(color: .clear,  location: 1.0)
                                    ],
                                    startPoint: .top, endPoint: .bottom
                                )
                            } else {
                                Color.black
                            }
                        }
                    )
                    .padding(.top, 4)
                    .padding(.leading, 108)
                    .padding(.trailing, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.top, 4)
            .clipped()
            .onAppear {
                GithubPoller.shared.refreshIfStale()
                appState.cardItemCount = totalItems
            }
            .onDisappear { appState.cardItemCount = 0 }
            .onReceive(NotificationCenter.default.publisher(for: .islandActivateCardSelection)) { _ in
                guard let sel = appState.cardSelection else { return }
                if sel < items.count {
                    let pr = items[sel]
                    if let url = safeWebURL(pr.url), url.host == "github.com" {
                        NSWorkspace.shared.open(url)
                    }
                } else {
                    let repoIdx = sel - items.count
                    guard repoIdx < repoItems.count else { return }
                    let repo = repoItems[repoIdx]
                    let actionsURL = repo.url.hasSuffix("/") ? repo.url + "actions" : repo.url + "/actions"
                    if let url = safeWebURL(actionsURL), url.host == "github.com" {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            .onExitCommand { onBack() }
        }
    }
}

// MARK: - GitHub Activity Detail

private struct GitHubActivityDetailContent: View {
    let activity: GitHubActivity?
    let stats: GitHubStats?
    let login: String
    let onBack: () -> Void

    @State private var hoveredDay: ContributionDay? = nil

    // Dynamic grid: s=7pt, spacing=1.5pt; numWeeks = floor((202 + 1.5) / (7 + 1.5)) = 23
    private let squareSize: CGFloat = 7
    private let spacing: CGFloat = 1.5
    private var numWeeks: Int { Int((202 + spacing) / (squareSize + spacing)) }

    private var headerRight: String {
        if let day = hoveredDay {
            let label: String
            switch day.count {
            case 0:  label = "No contributions"
            case 1:  label = "1 contribution"
            default: label = "\(day.count) contributions"
            }
            return "\(activityDateLabel(day.date)) · \(label)"
        }
        guard let act = activity else { return "" }
        let total = activityTotalLabel(act.total)
        if let s = stats { return "\(total) past year · \(s.totalRepos) repos" }
        return "\(total) past year"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Button(action: onBack) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 8, weight: .medium))
                        Text("Activity")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(Color(hex: "#F5F6F8"))
                }
                .buttonStyle(.plain)
                Spacer(minLength: 2)
                if activity != nil {
                    Button(action: {
                        let urlStr = "https://github.com/\(login)"
                        if let url = safeWebURL(urlStr), url.host == "github.com" {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        Text(headerRight)
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#8E939C"))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 6)
            .padding(.leading, 108)
            .padding(.trailing, 12)

            // Grid
            if let act = activity {
                let weeks = act.lastWeeks(numWeeks)
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(weeks.indices, id: \.self) { wi in
                        VStack(spacing: spacing) {
                            ForEach(0..<7, id: \.self) { dow in
                                if let day = weeks[wi].first(where: { $0.weekday == dow }) {
                                    RoundedRectangle(cornerRadius: 1.5)
                                        .fill(contributionColor(day.level))
                                        .frame(width: squareSize, height: squareSize)
                                        .onHover { hovering in hoveredDay = hovering ? day : nil }
                                        .onTapGesture {
                                            hoveredDay = (hoveredDay?.date == day.date) ? nil : day
                                        }
                                } else {
                                    Color.clear.frame(width: squareSize, height: squareSize)
                                }
                            }
                        }
                    }
                }
                .padding(.top, 5)
                .padding(.leading, 108)
                .padding(.trailing, 12)
            } else {
                Text("Loading…")
                    .font(.system(size: 10.5))
                    .foregroundColor(Color(hex: "#6B7079"))
                    .padding(.top, 8)
                    .padding(.leading, 108)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 4)
        .clipped()
        .onAppear { GithubPoller.shared.refreshActivityIfStale() }
        .onExitCommand { onBack() }
    }

    private func activityDateLabel(_ dateStr: String) -> String {
        let parts = dateStr.split(separator: "-")
        guard parts.count == 3,
              let month = Int(parts[1]), month >= 1 && month <= 12,
              let day   = Int(parts[2]) else { return dateStr }
        let months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
        return "\(months[month - 1]) \(day)"
    }

    private func activityTotalLabel(_ n: Int) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.locale = Locale(identifier: "en_US")
        return nf.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

private func contributionColor(_ level: Int) -> Color {
    switch level {
    case 1: return Color(hex: "#0E4429")
    case 2: return Color(hex: "#006D32")
    case 3: return Color(hex: "#26A641")
    case 4: return Color(hex: "#39D353")
    default: return Color.white.opacity(0.06)
    }
}

private func ghCIDot(_ ci: CIState) -> Color {
    switch ci {
    case .failure: return Color(hex: "#F4505E")
    case .pending: return Color(hex: "#F5A524")
    case .success: return Color(hex: "#22C55E")
    case .unknown: return Color.clear
    }
}

private struct GitHubPRRowView: View {
    let pr: GitHubPR
    let showCI: Bool
    var selected: Bool = false

    var body: some View {
        Button(action: {
            if let url = safeWebURL(pr.url), url.host == "github.com" {
                NSWorkspace.shared.open(url)
            }
        }) {
            HStack(spacing: 5) {
                if showCI {
                    Circle()
                        .fill(ghCIDot(pr.ci))
                        .frame(width: 5, height: 5)
                        .opacity(pr.ci == .unknown ? 0 : 1)
                } else {
                    Spacer().frame(width: 5)
                }
                Text("\(pr.repo.components(separatedBy: "/").last ?? pr.repo)#\(pr.number)")
                    .font(.system(size: 10.5))
                    .foregroundColor(Color(hex: "#9398A1"))
                    .lineLimit(1)
                Text(pr.title)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#C5C8CD"))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if pr.isDraft {
                    Text("Draft")
                        .font(.system(size: 9.5))
                        .foregroundColor(Color(hex: "#6B7079"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 20)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.12))
                    .opacity(selected ? 1 : 0)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct GitHubRepoCIRowView: View {
    let repo: GitHubRepoCI
    var selected: Bool = false

    private var ciStateWord: String? {
        switch repo.ci {
        case .failure: return "failing"
        case .pending: return "running"
        case .success: return "passing"
        case .unknown: return nil
        }
    }

    var body: some View {
        Button(action: {
            let actionsURL = repo.url.hasSuffix("/") ? repo.url + "actions" : repo.url + "/actions"
            if let url = safeWebURL(actionsURL), url.host == "github.com" {
                NSWorkspace.shared.open(url)
            }
        }) {
            HStack(spacing: 5) {
                Circle()
                    .fill(ghCIDot(repo.ci))
                    .frame(width: 5, height: 5)
                    .opacity(repo.ci == .unknown ? 0 : 1)
                Text(repo.repo.components(separatedBy: "/").last ?? repo.repo)
                    .font(.system(size: 10.5))
                    .foregroundColor(Color(hex: "#9398A1"))
                    .lineLimit(1)
                Text(repo.branch)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#C5C8CD"))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                if let word = ciStateWord {
                    Text(word)
                        .font(.system(size: 10))
                        .foregroundColor(ghCIDot(repo.ci))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 20)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.12))
                    .opacity(selected ? 1 : 0)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - GitHub Stats Card View

struct GitHubStatsCardView: View {
    let stats: GitHubStats

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: "#F4505E"))
                    .frame(width: 7, height: 7)
                Text("GitHub")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                Text("Overview")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#8E939C"))
            }
            .padding(.top, 6)
            .padding(.leading, 108)
            .padding(.trailing, 36)

            // Stats rows
            VStack(alignment: .leading, spacing: 5) {
                StatRow(icon: "star.fill", color: "#F5A524",
                        label: "Total stars", value: formatCount(stats.totalStars))
                StatRow(icon: "square.stack.fill", color: "#6B7079",
                        label: "Repositories", value: "\(stats.totalRepos)")
            }
            .padding(.top, 8)
            .padding(.leading, 108)
            .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 4)
    }

    private func formatCount(_ n: Int) -> String {
        if n >= 1000 { return String(format: "%.1fk", Double(n) / 1000) }
        return "\(n)"
    }
}

private struct StatRow: View {
    let icon: String
    let color: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(Color(hex: color))
                .frame(width: 14)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#6B7079"))
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hex: "#C5C8CD"))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}


// MARK: - Ticker (overview scrolling task steps) V2

struct TickerView: View {
    let task: AgentTask?
    var onDiffTap: ((Int) -> Void)? = nil

    @State private var rowA: String = "…"   // completed (above, left-shifted)
    @State private var rowB: String = "…"   // current (below) → animates diagonally up-left
    @State private var rowC: String = ""    // incoming current — slides in from below

    @State private var rowAOffset: CGFloat = 0
    @State private var rowAOpacity: Double = 1
    @State private var rowBOffset: CGFloat = 22
    @State private var rowBPhase:  Double  = 0   // 0=current, 1=completed (drives X+scale)
    @State private var rowCOffset: CGFloat = 44
    @State private var rowCOpacity: Double = 0

    @State private var displayIndex: Int = -1
    @State private var isTransitioning = false

    private let completedScale: CGFloat = 11.5 / 13   // 0.885 — matches completed font size

    var steps: [String] {
        let raw = task?.steps ?? []
        return raw.isEmpty ? ["…"] : raw
    }

    var body: some View {
        let isActive = task?.state == .thinking || task?.state == .working
        let rowADiffTap: (() -> Void)? = rowA.parseDiffStep().map { dp in { onDiffTap?(dp.diffId) } }
        let rowBDiffTap: (() -> Void)? = rowB.parseDiffStep().map { dp in { onDiffTap?(dp.diffId) } }

        ZStack(alignment: .topLeading) {
            Color.clear

            // Row A: completed row — always rendered at phase=1 + completedScale
            TickerRowView(text: rowA, phase: 1.0, isActive: isActive, onDiffTap: rowADiffTap)
                .scaleEffect(completedScale, anchor: .leading)
                .offset(x: -10, y: rowAOffset)
                .opacity(rowAOpacity)

            // Row B: current step → animates diagonally up-left, phase 0→1, scale 1→completedScale
            TickerRowView(text: rowB, phase: rowBPhase, isActive: isActive, onDiffTap: rowBDiffTap)
                .scaleEffect(1 - rowBPhase * (1 - completedScale), anchor: .leading)
                .offset(x: -rowBPhase * 10, y: rowBOffset)

            // Row C: incoming new step — slides in from below at phase=0
            TickerRowView(text: rowC, phase: 0.0, isActive: isActive)
                .offset(y: rowCOffset)
                .opacity(rowCOpacity)
        }
        .frame(height: 44)
        .clipped()
        .mask(LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.12),
                .init(color: .black, location: 0.85),
                .init(color: .clear, location: 1)
            ],
            startPoint: .top, endPoint: .bottom
        ))
        .onAppear {
            let idx = task?.stepIndex ?? -1
            displayIndex = idx
            if idx >= 0, !steps.isEmpty {
                rowA = idx > 0 ? steps[max(0, idx - 1)] : "…"
                rowB = steps[min(idx, steps.count - 1)]
            }
        }
        .onChange(of: task?.steps.count) { _, _ in
            guard let task, !task.steps.isEmpty, !isTransitioning else { return }
            let newIdx = task.stepIndex
            if displayIndex < 0 {
                displayIndex = newIdx
                rowA = newIdx > 0 ? steps[max(0, newIdx - 1)] : "…"
                rowB = steps[min(newIdx, steps.count - 1)]
                return
            }
            guard newIdx != displayIndex else { return }
            tickerAnimate(to: newIdx)
        }
    }

    private func tickerAnimate(to newIdx: Int) {
        isTransitioning = true
        rowC = steps[min(newIdx, steps.count - 1)]
        rowCOffset = 44
        rowCOpacity = 0

        // Old completed (rowA): fades + slides further up
        withAnimation(.easeOut(duration: 0.28)) {
            rowAOffset  = -22
            rowAOpacity = 0
        }

        // Current (rowB): moves diagonally up-left + shrinks to completed size
        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.38)) {
            rowBOffset = 0
            rowBPhase  = 1
        }

        // New current (rowC): slides in from below
        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.38)) {
            rowCOffset  = 22
            rowCOpacity = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.50) {
            self.displayIndex    = newIdx
            self.rowA            = self.rowB
            self.rowAOffset      = 0
            self.rowAOpacity     = 1
            self.rowB            = self.rowC
            self.rowBOffset      = 22
            self.rowBPhase       = 0
            self.rowCOffset      = 44
            self.rowCOpacity     = 0
            self.isTransitioning = false
        }
    }
}

struct TickerRowView: View {
    let text: String
    let phase: Double   // 0 = current (shimmer, large), 1 = completed (dim, scaled down by caller)
    var isActive: Bool = true
    var onDiffTap: (() -> Void)? = nil

    var body: some View {
        let chevronOpacity:   Double = isActive ? max(0, 1 - phase * 2)       : 0
        let checkmarkOpacity: Double = isActive ? max(0, phase * 2 - 1)       : 1
        let shimmerOpacity:   Double = isActive ? max(0, 1 - phase * 1.6)     : 0
        let staticOpacity:    Double = isActive ? min(1, max(0, phase * 2 - 0.4)) : 1
        let staticColor = (!isActive && phase < 0.5) ? Color(hex: "#C9CDD4") : Color(hex: "#6B7079")

        if let dp = text.parseDiffStep() {
            HStack(spacing: 6) {
                ZStack {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .opacity(chevronOpacity)
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .regular))
                        .foregroundColor(Color(hex: "#454850"))
                        .opacity(checkmarkOpacity)
                }
                .frame(width: 12, alignment: .center)
                // Filename + counts
                HStack(spacing: 0) {
                    ZStack(alignment: .leading) {
                        TickerShimmerText(text: dp.filename)
                            .opacity(shimmerOpacity)
                        Text(dp.filename)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(staticColor)
                            .lineLimit(1).truncationMode(.tail)
                            .opacity(staticOpacity)
                    }
                    if dp.added > 0 {
                        Text(" +\(dp.added)")
                            .font(.system(size: 10, weight: .medium).monospaced())
                            .foregroundColor(Color(hex: "#22C55E"))
                            .fixedSize()
                    }
                    if dp.removed > 0 {
                        Text(" −\(dp.removed)")
                            .font(.system(size: 10, weight: .medium).monospaced())
                            .foregroundColor(Color(hex: "#F4505E"))
                            .fixedSize()
                    }
                }
            }
            .frame(height: 22, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { onDiffTap?() }
        } else {
            HStack(spacing: 6) {
                // Icon: chevron fades out first half, checkmark fades in second half
                ZStack {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .opacity(chevronOpacity)
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .regular))
                        .foregroundColor(Color(hex: "#454850"))
                        .opacity(checkmarkOpacity)
                }
                .frame(width: 12, alignment: .center)

                // Text: shimmer fades out, dim completed text fades in (overlapping cross-fade)
                ZStack(alignment: .leading) {
                    TickerShimmerText(text: text)
                        .opacity(shimmerOpacity)
                    Text(text)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(staticColor)
                        .lineLimit(1).truncationMode(.tail)
                        .opacity(staticOpacity)
                }
            }
            .frame(height: 22, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct TickerShimmerText: View {
    let text: String

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let p = CGFloat(t.truncatingRemainder(dividingBy: 2.2) / 2.2)
            // phase sweeps -0.1 → 1.1 so white peak enters from left and exits right
            let phase = p * 1.2 - 0.1
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(LinearGradient(stops: [
                    .init(color: Color(hex: "#7c818a"), location: max(0, phase - 0.3)),
                    .init(color: Color(hex: "#F2F3F5"), location: max(0, min(1, phase))),
                    .init(color: Color(hex: "#7c818a"), location: min(1, phase + 0.3)),
                ], startPoint: .leading, endPoint: .trailing))
        }
    }
}

// MARK: - Agent pills (overview right card)

struct AgentPillsView: View {
    @ObservedObject var state: AppState
    @State private var swapping = false

    private var others: [AgentTask] {
        state.tasks.filter { $0.id != state.focusId }
    }

    private var displayTasks: [AgentTask] {
        Array(others.prefix(4))
    }

    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(displayTasks) { task in
                    #if !APPSTORE
                    if task.id == "integration_music" {
                        MusicPill(task: task, state: state, swapping: $swapping) {
                            swapping = true
                            state.setFocus(task.id)
                            SoundEngine.shared.play("blip")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { swapping = false }
                        }
                    } else {
                        AgentPill(task: task, state: state, swapping: $swapping) {
                            swapping = true
                            state.setFocus(task.id)
                            SoundEngine.shared.play("blip")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { swapping = false }
                        }
                    }
                    #else
                    AgentPill(task: task, state: state, swapping: $swapping) {
                        swapping = true
                        state.setFocus(task.id)
                        SoundEngine.shared.play("blip")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { swapping = false }
                    }
                    #endif
                }
            }
            .padding(.horizontal, 8)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AgentPill: View {
    let task: AgentTask
    @ObservedObject var state: AppState
    @Binding var swapping: Bool
    let onTap: () -> Void
    @State private var isHovered = false

    private var effectiveColor: String { task.color }

    // VS Code pill always shows "VS Code" label regardless of active project name
    private var displayName: String {
        task.id == "integration_claude" ? "VS Code" : task.name
    }

    var body: some View {
        Button(action: { onTap() }) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Capsule()
                        .fill(isHovered
                              ? Color(hex: effectiveColor).opacity(0.18)
                              : Color(hex: "#0E0F11"))
                    Capsule()
                        .stroke(Color(hex: effectiveColor).opacity(isHovered ? 0.55 : 0.14), lineWidth: 1)
                    HStack(spacing: 0) {
                        MiniBotCanvasView(task: task)
                            .frame(width: 22 / 0.6, height: 22 / 0.6)
                            .frame(width: 22, height: 22, alignment: .center)
                            .padding(.leading, 8)
                        Spacer()
                    }
                    Text(displayName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(isHovered
                                         ? Color(hex: effectiveColor).lighter(by: 0.3)
                                         : Color(hex: "#6B7079"))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .shadow(color: Color(hex: effectiveColor).opacity(isHovered ? 0.35 : 0), radius: 10, x: 0, y: 2)

                // Alert badge (approval / finished / error)
                if let badge = task.pillBadge {
                    PillBadgeView(badge: badge, taskColor: effectiveColor)
                        .offset(x: 3, y: -3)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.04 : 1.0)
        .brightness(isHovered ? 0.06 : 0)
        .onHover { newHover in
            guard !swapping else { return }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { isHovered = newHover }
        }
    }
}

// MARK: - Music Pill (GitHub build only)

#if !APPSTORE
struct MusicPill: View {
    let task: AgentTask
    @ObservedObject var state: AppState
    @Binding var swapping: Bool
    let onTap: () -> Void
    @State private var isHovered = false

    private var isPlaying: Bool { AppState.shared.musicPlaying }
    private var showControls: Bool { isHovered && MusicController.shared.trackTitle != nil }

    var body: some View {
        ZStack {
            // Selection target — full pill area, receives taps where controls don't
            Capsule()
                .fill(Color.clear)
                .contentShape(Capsule())
                .onTapGesture { onTap() }

            // Visual fills
            Capsule()
                .fill(isHovered ? Color(hex: task.color).opacity(0.18) : Color(hex: "#0E0F11"))
                .allowsHitTesting(false)
            Capsule()
                .stroke(Color(hex: task.color).opacity(isHovered ? 0.55 : 0.14), lineWidth: 1)
                .allowsHitTesting(false)

            // Mini Oli at leading edge
            HStack(spacing: 0) {
                MiniBotCanvasView(task: task, isDancing: isPlaying)
                    .frame(width: 22 / 0.6, height: 22 / 0.6)
                    .frame(width: 22, height: 22, alignment: .center)
                    .padding(.leading, 8)
                Spacer()
            }
            .allowsHitTesting(false)

            // Title — trailing padding grows on hover to make room for buttons
            Text(task.name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(isHovered ? Color(hex: task.color).lighter(by: 0.3) : Color(hex: "#6B7079"))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, 34)
                .padding(.trailing, showControls ? 52 : 10)
                .frame(maxWidth: .infinity, alignment: .center)
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: showControls)
                .allowsHitTesting(false)

            // Playback controls — appear on hover when a track is loaded
            if showControls {
                HStack(spacing: 0) {
                    Spacer()
                    HStack(spacing: 2) {
                        MusicControlButton(icon: isPlaying ? "pause.fill" : "play.fill", color: task.color) {
                            MusicController.shared.playPause()
                        }
                        MusicControlButton(icon: "forward.fill", color: task.color) {
                            MusicController.shared.nextTrack()
                        }
                    }
                    .padding(.trailing, 4)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .trailing)))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .shadow(color: Color(hex: task.color).opacity(isHovered ? 0.35 : 0), radius: 10, x: 0, y: 2)
        .scaleEffect(isHovered ? 1.04 : 1.0)
        .brightness(isHovered ? 0.06 : 0)
        .onHover { newHover in
            guard !swapping else { return }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { isHovered = newHover }
        }
    }
}

struct MusicControlButton: View {
    let icon: String
    let color: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isHovered ? Color(hex: color).opacity(0.18) : Color(hex: "#0E0F11"))
                Circle()
                    .stroke(Color(hex: color).opacity(isHovered ? 0.55 : 0.14), lineWidth: 1)
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(isHovered ? Color(hex: color).lighter(by: 0.3) : Color(hex: "#6B7079"))
            }
            .frame(width: 20, height: 20)
            .shadow(color: Color(hex: color).opacity(isHovered ? 0.35 : 0), radius: 6)
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.1 : 1.0)
        .onHover { newHover in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { isHovered = newHover }
        }
    }
}
#endif

// MARK: - Music Card View (GitHub build only)

#if !APPSTORE
struct MusicCardView: View {
    @ObservedObject private var controller = MusicController.shared
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if appState.musicAutomationDenied {
                // Automation denied — prompt user to fix
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: "#F4505E"))
                        .frame(width: 7, height: 7)
                    Text("Apple Music")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#F5F6F8"))
                    Spacer(minLength: 2)
                }
                .padding(.top, 6)
                .padding(.leading, 108)
                .padding(.trailing, 36)

                Text("Allow Oli to control Music")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#8E939C"))
                    .padding(.leading, 108)
                    .padding(.trailing, 12)

                Button("Open Settings…") { MusicController.shared.openAutomationSettings() }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(hex: "#FA2D48").opacity(0.85))
                    .buttonStyle(.plain)
                    .padding(.leading, 108)
                    .padding(.top, 2)
            } else {
                // Line 1: dot + title
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: "#FA2D48"))
                        .frame(width: 7, height: 7)
                    if let title = controller.trackTitle {
                        Text(title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(hex: "#F5F6F8"))
                            .lineLimit(1).truncationMode(.tail)
                            .frame(maxWidth: 150, alignment: .leading)
                    }
                }
                .padding(.top, 6)
                .padding(.leading, 108)

                // Line 2: artist
                if let artist = controller.artist {
                    Text(artist)
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: 150, alignment: .leading)
                        .padding(.leading, 108)
                }

                // Line 3: controls
                HStack(spacing: 8) {
                    Button(action: { MusicController.shared.previousTrack() }) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#8E939C"))
                    }
                    .buttonStyle(.plain)
                    Button(action: { MusicController.shared.playPause() }) {
                        Image(systemName: appState.musicPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#FA2D48"))
                    }
                    .buttonStyle(.plain)
                    Button(action: { MusicController.shared.nextTrack() }) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#8E939C"))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 108)
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 4)
    }
}
#endif

struct PillBadgeView: View {
    let badge: PillBadge
    let taskColor: String

    private var badgeColor: Color {
        switch badge {
        case .approval: return Color(hex: "#F5A524")
        case .finished: return Color(hex: "#22C55E")
        case .error:    return Color(hex: "#F4505E")
        }
    }

    private var icon: String {
        switch badge {
        case .approval: return "exclamationmark"
        case .finished: return "checkmark"
        case .error:    return "xmark"
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "#0B0C0E"))
                .frame(width: 14, height: 14)
            Circle()
                .fill(badgeColor)
                .frame(width: 12, height: 12)
            Image(systemName: icon)
                .font(.system(size: 6, weight: .bold))
                .foregroundColor(.black)
        }
        .shadow(color: badgeColor.opacity(0.6), radius: 4, x: 0, y: 0)
    }
}

// MARK: - Column agents (right side of non-overview views)

struct ColumnAgentsView: View {
    @ObservedObject var state: AppState

    var others: [AgentTask] {
        state.tasks.filter { $0.id != state.focusId }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(others.prefix(4).enumerated()), id: \.1.id) { idx, task in
                MiniBotCanvasView(task: task)
                    .frame(width: 16 / 0.6, height: 16 / 0.6)
                    .frame(width: 16, height: 16)
                    .position(x: 0, y: CGFloat(50 + idx * 24))
                    .animation(.spring(response: 0.5, dampingFraction: 0.72).delay(Double(idx) * 0.035), value: idx)
            }
        }
    }
}

// MARK: - Wardrobe

struct WardrobeView: View {
    @ObservedObject var state: AppState
    @State private var hoveredOutfit: Outfit? = nil

    private let columns = Array(repeating: GridItem(.fixed(30), spacing: 5), count: 14)

    private var headerRight: String {
        // Hover takes priority: show hovered outfit name
        if let h = hoveredOutfit {
            if h == .auto {
                let seasonal = Outfit.seasonal(for: Date(), calendar: .current)
                let name = seasonal == .none ? "None" : seasonal.displayName
                return "Auto · follows the seasons (now: \(name))"
            }
            return h.displayName
        }
        // Fall back to current selection
        let sel = state.oliOutfitSelection
        if sel == .auto {
            let seasonal = Outfit.seasonal(for: Date(), calendar: .current)
            let name = seasonal == .none ? "None" : seasonal.displayName
            return "Auto · \(name)"
        }
        return sel.displayName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Text("Wardrobe")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                Spacer(minLength: 4)
                Text(headerRight)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#8E939C"))
                    .lineLimit(1)
            }
            .padding(.top, 6)
            .padding(.horizontal, 10)

            // Grid
            let allOutfits = Outfit.allCases.filter { $0 != .auto }
            let withAuto = [Outfit.auto] + allOutfits
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 5) {
                    ForEach(withAuto, id: \.rawValue) { outfit in
                        OutfitPillView(
                            outfit: outfit,
                            isSelected: state.oliOutfitSelection == outfit,
                            isHovered: hoveredOutfit == outfit,
                            onHover: { h in
                                hoveredOutfit = h ? outfit : nil
                                if h {
                                    // Preview on main Oli
                                    let preview: Outfit = outfit == .auto
                                        ? Outfit.seasonal(for: Date(), calendar: .current)
                                        : outfit
                                    state.wardrobePreviewOutfit = preview
                                } else if hoveredOutfit == nil {
                                    state.wardrobePreviewOutfit = nil
                                }
                            },
                            onTap: {
                                guard state.oliOutfitSelection != outfit else { return }
                                state.oliOutfitSelection = outfit
                                SoundEngine.shared.play("pop")
                                NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.proud)
                            },
                            seasonalOutfit: outfit == .auto ? state.resolvedOutfit : .none
                        )
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
            }
            .frame(maxHeight: .infinity)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .white, location: 0),
                        .init(color: .white, location: 0.85),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
        }
        .padding(.leading, 108)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onDisappear {
            state.wardrobePreviewOutfit = nil
            hoveredOutfit = nil
        }
        .onExitCommand {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                state.view = .overview
            }
        }
    }
}

struct OutfitPillView: View {
    let outfit: Outfit
    let isSelected: Bool
    let isHovered: Bool
    let onHover: (Bool) -> Void
    let onTap: () -> Void
    var seasonalOutfit: Outfit = .none

    var body: some View {
        Canvas { context, size in
            drawOutfitIcon(context: context, size: size, outfit: outfit, seasonal: seasonalOutfit)
        }
        .frame(width: 30, height: 30)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isHovered ? Color.white.opacity(0.10) : Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(isSelected ? Color.white.opacity(0.40) : Color.white.opacity(0.08), lineWidth: 1)
        )
        .onHover { onHover($0) }
        .onTapGesture { onTap() }
    }
}

private func drawOutfitIcon(context: GraphicsContext, size: CGSize, outfit: Outfit, seasonal: Outfit = .none) {
    let W = size.width, H = size.height
    let cx = W / 2, cy = H / 2
    let R: CGFloat = 6.5   // small scale for icon

    switch outfit {
    case .auto:
        let iconR: CGFloat = 10.0
        let rx = iconR * OliConst.bodyRX, ry = iconR * OliConst.bodyRY
        let mH = OliH(R: iconR, yaw: 0, pitch: 0)
        let bodyPath = oliOutfitPath(rx, ry)
        let iconCY = cy + iconR * 0.62

        // Draw the seasonal outfit behind body
        if seasonal != .none && seasonal != .auto {
            drawOutfitBehindStatic(context: context, outfit: seasonal, H: mH,
                                   cx: cx, cy: iconCY, tilt: 0, sx: 1, sy: 1,
                                   roll: 0, morph: 0, isMini: false)
        }
        // Body
        var ctx = context
        ctx.translateBy(x: cx, y: iconCY)
        ctx.fill(bodyPath, with: .linearGradient(
            Gradient(colors: [Color(cgColor: OliConst.baseTop),
                              Color(cgColor: OliConst.baseBottom)]),
            startPoint: CGPoint(x: rx*0.7, y: -ry*0.85),
            endPoint:   CGPoint(x: -rx*0.8, y: ry*0.9)
        ))
        ctx.fill(bodyPath, with: .radialGradient(
            Gradient(stops: [.init(color: .clear, location: 0.6),
                             .init(color: Color.black.opacity(0.2), location: 1)]),
            center: .zero, startRadius: iconR*0.15, endRadius: iconR*1.25
        ))
        // Eyes
        var eyeCtx = ctx; eyeCtx.clip(to: bodyPath)
        let ink = Color(red: 0.102, green: 0.082, blue: 0.071)
        for f in mEyeFrames(mH) {
            guard f.visible else { continue }
            var ec = eyeCtx; ec.translateBy(x: f.x, y: f.y); ec.scaleBy(x: f.fx, y: f.fy)
            let hh = max(f.h, f.w*0.3)
            var pill = Path()
            pill.addRoundedRect(in: CGRect(x: -f.w/2, y: -hh/2, width: f.w, height: hh),
                                cornerSize: CGSize(width: min(f.w/2,hh/2), height: min(f.w/2,hh/2)))
            ec.fill(pill, with: .color(ink))
        }
        // Front outfit
        if seasonal != .none && seasonal != .auto {
            drawOutfitFrontStatic(context: context, outfit: seasonal, H: mH,
                                  cx: cx, cy: iconCY, tilt: 0, sx: 1, sy: 1,
                                  roll: 0, morph: 0, isMini: false)
        }
        // AUTO badge at bottom
        var badgeCtx = context
        let badgeCY = iconCY + ry * 0.72
        badgeCtx.translateBy(x: cx, y: badgeCY)
        let bw: CGFloat = 14, bh: CGFloat = 6.5
        var badge = Path()
        badge.addRoundedRect(in: CGRect(x: -bw/2, y: -bh/2, width: bw, height: bh),
                             cornerSize: CGSize(width: bh/2, height: bh/2))
        badgeCtx.fill(badge, with: .color(Color.black.opacity(0.60)))
        badgeCtx.draw(Text("AUTO").font(.system(size: 4.2, weight: .semibold)).foregroundColor(.white),
                      at: .zero)

    case .none:
        var ctx = context
        ctx.translateBy(x: cx, y: cy)
        // Circle with diagonal slash (⊘)
        var circle = Path()
        circle.addEllipse(in: CGRect(x: -R * 0.82, y: -R * 0.82, width: R * 1.64, height: R * 1.64))
        ctx.stroke(circle, with: .color(Color(hex: "#454850")), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        var slash = Path()
        slash.move(to:    CGPoint(x: -R * 0.56, y:  R * 0.56))
        slash.addLine(to: CGPoint(x:  R * 0.56, y: -R * 0.56))
        ctx.stroke(slash, with: .color(Color(hex: "#454850")), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))

    default:
        // Small Oli wearing the outfit
        let iconR: CGFloat = 10.0
        let rx = iconR * OliConst.bodyRX, ry = iconR * OliConst.bodyRY
        let mH = OliH(R: iconR, yaw: 0, pitch: 0)
        let bodyPath = oliOutfitPath(rx, ry)
        let iconCY = cy + iconR * 0.62

        // Draw outfit behind
        drawOutfitBehindStatic(context: context, outfit: outfit, H: mH,
                               cx: cx, cy: iconCY, tilt: 0, sx: 1, sy: 1,
                               roll: 0, morph: 0, isMini: false)

        // Draw body
        var ctx = context
        ctx.translateBy(x: cx, y: iconCY)
        let pumpkin = outfit == .pumpkin
        let top = pumpkin ? Color(hex: "#FFA94D") : Color(cgColor: OliConst.baseTop)
        let bot = pumpkin ? Color(hex: "#E8590C") : Color(cgColor: OliConst.baseBottom)
        ctx.fill(bodyPath, with: .linearGradient(
            Gradient(colors: [top, bot]),
            startPoint: CGPoint(x: rx * 0.7, y: -ry * 0.85),
            endPoint:   CGPoint(x: -rx * 0.8, y: ry * 0.9)
        ))
        ctx.fill(bodyPath, with: .radialGradient(
            Gradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: 0.6),
                .init(color: Color.black.opacity(0.2), location: 1)
            ]),
            center: .zero, startRadius: iconR * 0.15, endRadius: iconR * 1.25
        ))
        ctx.fill(bodyPath, with: .radialGradient(
            Gradient(stops: [
                .init(color: Color.white.opacity(0.55), location: 0),
                .init(color: .clear, location: 1)
            ]),
            center: CGPoint(x: rx * 0.34, y: -ry * 0.46),
            startRadius: 0, endRadius: iconR * 0.42
        ))

        // Draw eyes
        var eyeCtx = ctx
        eyeCtx.clip(to: bodyPath)
        let ink = Color(red: 0.102, green: 0.082, blue: 0.071)
        for f in mEyeFrames(mH) {
            guard f.visible else { continue }
            var ec = eyeCtx
            ec.translateBy(x: f.x, y: f.y)
            ec.scaleBy(x: f.fx, y: f.fy)
            let hh = max(f.h, f.w * 0.3)
            var pill = Path()
            pill.addRoundedRect(
                in: CGRect(x: -f.w / 2, y: -hh / 2, width: f.w, height: hh),
                cornerSize: CGSize(width: min(f.w / 2, hh / 2), height: min(f.w / 2, hh / 2))
            )
            ec.fill(pill, with: .color(ink))
        }

        // Draw outfit front
        drawOutfitFrontStatic(context: context, outfit: outfit, H: mH,
                              cx: cx, cy: iconCY, tilt: 0, sx: 1, sy: 1,
                              roll: 0, morph: 0, isMini: false)
    }
}
// MARK: - Card background

struct CardBackground<Content: View>: View {
    enum Wash { case red, green, pink, amber, cyan, indigo, soft }

    let wash: Wash?
    let content: (() -> Content)?

    init(wash: Wash?, @ViewBuilder content: @escaping () -> Content) {
        self.wash = wash
        self.content = content
    }

    var washColor: Color {
        switch wash {
        case .red:    return Color(hex: "#F4505E").opacity(0.55)
        case .green:  return Color(hex: "#34D399").opacity(0.5)
        case .pink:   return Color(hex: "#F472B6").opacity(0.55)
        case .amber:  return Color(hex: "#F5A524").opacity(0.42)
        case .cyan:   return Color(hex: "#22D3EE").opacity(0.38)
        case .indigo: return Color(hex: "#6366F1").opacity(0.5)
        case .soft:   return Color.white.opacity(0.08)
        case nil:     return Color.clear
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(hex: "#141518"))
                .overlay(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: washColor, location: 0),
                            .init(color: .clear, location: 0.7)
                        ]),
                        center: UnitPoint(x: 0.5, y: 1.3),
                        startRadius: 0,
                        endRadius: 280
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.035), lineWidth: 1)
                )

            if let content = content {
                content()
            }
        }
    }
}

extension CardBackground where Content == EmptyView {
    init(wash: Wash?) {
        self.wash = wash
        self.content = nil
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(hex: "#141518"))
                .overlay(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: washColor, location: 0),
                            .init(color: .clear, location: 0.7)
                        ]),
                        center: UnitPoint(x: 0.5, y: 1.3),
                        startRadius: 0,
                        endRadius: 280
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.035), lineWidth: 1)
                )
        }
    }
}

// MARK: - Shared sub-components

struct AgentWho: View {
    let task: AgentTask?
    let label: String

    var body: some View {
        HStack(spacing: 7) {
            if let task = task {
                Circle().fill(Color(hex: task.color)).frame(width: 8, height: 8)
                Text(task.name).font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8"))
            }
            Text(label).font(.system(size: 12)).foregroundColor(Color(hex: "#8E939C"))
        }
    }
}

struct CodeBlock: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.white.opacity(0.07))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06)))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .foregroundColor(Color(hex: "#E8E9EC"))
    }
}

struct ContextChip: View {
    let context: PromptContext
    @State private var glowing = false

    var label: String {
        switch context {
        case .window(let app, _, let url):
            if let url = url, let host = URL(string: url)?.host { return "\(app) · \(host)" }
            return app
        case .file(let name, _): return name
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(LinearGradient(colors: [Color(hex: "#FF6B5B"), Color(hex: "#F7B32B"), Color(hex: "#2DD4A7"), Color(hex: "#38BDF8"), Color(hex: "#A78BFA")], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 11.5))
                .foregroundColor(Color(hex: "#F1F2F4"))
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Color.white.opacity(0.1))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(glowing ? 0.75 : 0), lineWidth: 1.5))
        .scaleEffect(glowing ? 1.06 : 1.0)
        .onAppear {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) { glowing = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                withAnimation(.easeOut(duration: 0.3)) { glowing = false }
            }
        }
    }
}


struct ShimmeringText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .foregroundStyle(
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: "#7c818a"), location: 0),
                        .init(color: .white, location: 0.4),
                        .init(color: Color(hex: "#7c818a"), location: 0.7)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
    }
}

struct ShimmerOverlay: View {
    @State private var phase: CGFloat = 0.0

    var body: some View {
        LinearGradient(
            stops: [
                // Clamp all locations to [0,1] and keep them ordered
                .init(color: .clear,                   location: max(0, phase - 0.3)),
                .init(color: Color.white.opacity(0.6), location: max(0, min(1, phase))),
                .init(color: .clear,                   location: min(1, phase + 0.3))
            ],
            startPoint: .leading, endPoint: .trailing
        )
        .blendMode(.overlay)
        .onAppear {
            withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
                phase = 1.3  // travels left→right, exits right edge cleanly
            }
        }
    }
}

// MARK: - Button styles

struct PrimaryButton: View {
    let title: String
    let kbd: String?
    let action: () -> Void

    init(_ title: String, kbd: String? = nil, action: @escaping () -> Void) {
        self.title = title; self.kbd = kbd; self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(title).font(.system(size: 12.5, weight: .medium))
                if let k = kbd {
                    Text(k).font(.system(size: 10.5))
                        .padding(.horizontal, 4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black.opacity(0.4)))
                        .opacity(0.55)
                }
            }
            .padding(.horizontal, 13).padding(.vertical, 7)
            .background(Color(hex: "#F5F6F8"))
            .foregroundColor(Color(hex: "#0B0C0E"))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct SecondaryButton: View {
    let title: String
    let kbd: String?
    let action: () -> Void

    init(_ title: String, kbd: String? = nil, action: @escaping () -> Void) {
        self.title = title; self.kbd = kbd; self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(title).font(.system(size: 12.5, weight: .medium))
                if let k = kbd {
                    Text(k).font(.system(size: 10.5))
                        .padding(.horizontal, 4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.4)))
                        .opacity(0.55)
                }
            }
            .padding(.horizontal, 13).padding(.vertical, 7)
            .background(Color.white.opacity(0.09))
            .foregroundColor(Color(hex: "#F1F2F4"))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 28, height: 28)
            .background(Color.white.opacity(0.08))
            .clipShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}

struct SendButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 28, height: 28)
            .background(Color(hex: "#F5F6F8"))
            .clipShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}

// MARK: - Settings island view (Point 7)

struct SettingsIslandView: View {
    @ObservedObject var state: AppState

    private var claudeConnected: Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any],
              let ss = hooks["SessionStart"] as? [[String: Any]] else { return false }
        return ss.contains { matcher in
            (matcher["hooks"] as? [[String: Any]])?.contains {
                HookServer.isOliHookCommand($0["command"] as? String)
            } ?? false
        }
    }

    private var apiConnected: Bool {
        KeychainStore.shared.get("anthropic-api-key") != nil
    }

    var body: some View {
        ZStack(alignment: .leading) {
            CardBackground(wash: nil)
            VStack(alignment: .leading, spacing: 10) {
                // Sound row
                HStack(spacing: 10) {
                    Toggle("", isOn: $state.soundEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .scaleEffect(0.75)
                        .frame(width: 44)
                    Text("Sound")
                        .font(.system(size: 12.5))
                        .foregroundColor(Color(hex: "#C5C8CD"))
                    Slider(value: $state.soundVolume, in: 0...0.2)
                        .frame(width: 72)
                        .opacity(state.soundEnabled ? 1 : 0.4)
                }

                // Auto-close row
                HStack(spacing: 10) {
                    Image(systemName: "timer")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .frame(width: 16)
                    Text("Auto-close · \(Int(state.autoCloseInterval))s")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#C5C8CD"))
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach([10, 15, 30], id: \.self) { s in
                            Button("\(s)s") {
                                state.autoCloseInterval = Double(s)
                            }
                            .font(.system(size: 11))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(state.autoCloseInterval == Double(s) ? Color(hex: "#252830") : Color.clear)
                            .foregroundColor(state.autoCloseInterval == Double(s) ? Color(hex: "#F5F6F8") : Color(hex: "#6B7079"))
                            .clipShape(Capsule())
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Connection status
                HStack(spacing: 14) {
                    StatusBadge(label: "Claude Code", ok: claudeConnected)
                    StatusBadge(label: "API", ok: apiConnected)
                    Spacer()
                    Button("Settings…") {
                        NotificationCenter.default.post(name: .openFullSettings, object: nil)
                    }
                    .font(.system(size: 11.5))
                    .foregroundColor(Color(hex: "#8E939C"))
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 84)
            .padding(.trailing, 16)
            .padding(.vertical, 14)
        }
    }
}

struct StatusBadge: View {
    let label: String
    let ok: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(ok ? Color(hex: "#22C55E") : Color(hex: "#F4505E"))
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#8E939C"))
        }
    }
}

// MARK: - Color extension (lighten)

// MARK: - Chat-provider switch (used by AI pill buttons and ↗ action)

/// Mirrors ModelPickerView provider-chip tap: animates, fires surprised emote + "pop" sound,
/// then opens the chat view. No-op if provider is already selected (just opens chat).
@MainActor
func switchChatProvider(_ provider: ChatProvider) {
    let state = AppState.shared
    if provider != state.chatProvider {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
            state.chatProvider = provider
        }
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.surprised)
        SoundEngine.shared.play("pop")
    }
    state.view = .prompt
}

extension Color {
    func lighter(by amount: Double) -> Color {
        guard let components = NSColor(self).usingColorSpace(.sRGB) else { return self }
        return Color(
            red: min(1, Double(components.redComponent) + amount),
            green: min(1, Double(components.greenComponent) + amount),
            blue: min(1, Double(components.blueComponent) + amount)
        )
    }
}


// MARK: - Espace client (Oculot) views

struct EspaceListView: View {
    let clients: [EspaceClient]
    let alerts: [EspaceAlert]
    let onOpen: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(Color(hex: "#FF5B37")).frame(width: 7, height: 7)
                Text("Espace client")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                Text(clients.count == 1 ? "1 projet" : "\(clients.count) projets")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#8E939C"))
                if !alerts.isEmpty {
                    Text("\(alerts.count)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color(hex: "#15130F"))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color(hex: "#FFD65C"))
                        .clipShape(Capsule())
                }
            }
            .padding(.top, 6)
            .padding(.leading, 108)
            .padding(.trailing, 36)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(clients.prefix(3).enumerated()), id: \.element.id) { i, c in
                    let accent = Color(hex: c.urgency.hex)
                    HStack(spacing: 5) {
                        Circle().fill(accent).frame(width: 5, height: 5)
                        Text(c.name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: i == 0 ? "#C5C8CD" : "#9398A1"))
                            .lineLimit(1).truncationMode(.tail)
                            .layoutPriority(1)
                        Text(c.stepLabel)
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#6B7079"))
                            .lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 4)
                        Text(c.daysLabel)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(accent)
                        Text("\(c.progress) %")
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#6B7079"))
                            .monospacedDigit()
                        Button(action: { onOpen(i) }) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(Color(hex: "#6B7079"))
                                .frame(width: 18, height: 18)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(i == 0 ? accent.opacity(0.08) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
            }
            .padding(.top, 5)
            .padding(.leading, 108)
            .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 4)
    }
}

struct EspaceDetailView: View {
    let client: EspaceClient
    let onClose: () -> Void

    private var accent: Color { Color(hex: client.urgency.hex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(hex: "#6B7079"))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Circle().fill(accent).frame(width: 6, height: 6)
                Text(client.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                    .lineLimit(1).truncationMode(.tail)
                    .layoutPriority(1)
                Text(client.kindLabel)
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#8E939C"))
                Spacer(minLength: 2)
                Text(client.daysLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(accent)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(accent.opacity(0.14))
                    .clipShape(Capsule())
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule().fill(Color(hex: "#FF5B37"))
                                .frame(width: max(4, g.size.width * CGFloat(client.progress) / 100))
                        }
                    }
                    .frame(height: 4)
                    Text("\(client.progress) %")
                        .font(.system(size: 10)).monospacedDigit()
                        .foregroundColor(Color(hex: "#C5C8CD"))
                }
                HStack(spacing: 8) {
                    Label(client.stepLabel, systemImage: "flag")
                        .font(.system(size: 10.5))
                        .foregroundColor(Color(hex: "#C5C8CD"))
                        .lineLimit(1)
                    Text("\(client.stepsDone)/\(client.stepsTotal) étapes")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#6B7079"))
                    if !client.contact.isEmpty {
                        Label(client.contact, systemImage: "person")
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#6B7079"))
                            .lineLimit(1)
                    }
                }
                if let u = client.lastUpdate {
                    Text("\(u.author.isEmpty ? "Équipe" : u.author) : \(u.body)")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#9398A1"))
                        .lineLimit(2)
                } else {
                    Text("Aucun petit mot envoyé pour l’instant · inactif depuis \(client.inactiveDays) j")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#9398A1"))
                }
                HStack(spacing: 10) {
                    Button(action: { if let u = URL(string: client.adminUrl) { NSWorkspace.shared.open(u) } }) {
                        Label("Ouvrir la fiche", systemImage: "arrow.up.right.square")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color(hex: "#FF5B37"))
                    }
                    .buttonStyle(.plain)
                    let site = client.liveUrl.isEmpty ? client.previewUrl : client.liveUrl
                    if !site.isEmpty, let u = URL(string: site) {
                        Button(action: { NSWorkspace.shared.open(u) }) {
                            Label(client.liveUrl.isEmpty ? "Prévisualisation" : "Site en ligne", systemImage: "globe")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(Color(hex: "#C5C8CD"))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.top, 8)
        .padding(.leading, 108)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
    }
}

// MARK: - Instagram (Oculot) view

struct SocialListView: View {
    let snapshot: SocialSnapshot
    private let accent = Color(hex: "#E1306C")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(accent).frame(width: 7, height: 7)
                Text(snapshot.username.isEmpty ? "Instagram" : "@\(snapshot.username)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                    .lineLimit(1)
                if snapshot.error == nil {
                    Text(snapshot.followersLabel)
                        .font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C"))
                    Text("·").font(.system(size: 11)).foregroundColor(Color(hex: "#6B7079"))
                    Text(snapshot.lastPostLabel())
                        .font(.system(size: 11))
                        .foregroundColor((snapshot.daysSinceLastPost() ?? 99) >= SocialSnapshot.quietDays ? Color(hex: "#FFD65C") : Color(hex: "#8E939C"))
                        .lineLimit(1)
                }
                Spacer(minLength: 2)
            }
            .padding(.top, 6)
            .padding(.leading, 108)
            .padding(.trailing, 36)

            VStack(alignment: .leading, spacing: 3) {
                if let e = snapshot.error {
                    Text(e)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: "#F4505E"))
                    Text("Vérifie le jeton dans Réglages → Connexions → Instagram.")
                        .font(.system(size: 10)).foregroundColor(Color(hex: "#8E939C"))
                } else if !snapshot.unanswered.isEmpty {
                    ForEach(snapshot.unanswered.prefix(3)) { c in
                        row(icon: "bubble.left.fill", tint: Color(hex: "#FFD65C"),
                            title: "@\(c.username)", detail: c.text, url: c.postPermalink)
                    }
                } else {
                    ForEach(snapshot.posts.prefix(3)) { post in
                        row(icon: "photo", tint: Color(hex: "#6B7079"),
                            title: post.caption.isEmpty ? "Sans légende" : String(post.caption.prefix(60)),
                            detail: "♥ \(post.likes)  💬 \(post.comments)", url: post.permalink)
                    }
                }
            }
            .padding(.top, 5)
            .padding(.leading, 108)
            .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 4)
    }

    private func row(icon: String, tint: Color, title: String, detail: String, url: String) -> some View {
        Button(action: { if let u = URL(string: url), !url.isEmpty { NSWorkspace.shared.open(u) } }) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 9)).foregroundColor(tint)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(hex: "#C5C8CD"))
                    .lineLimit(1).truncationMode(.tail)
                    .layoutPriority(1)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#8E939C"))
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 2)
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sites clients (Oculot) views

struct SitesListView: View {
    let checks: [SiteCheck]
    var audits: [String: SiteAudit] = [:]
    let onOpen: (String) -> Void

    private var sorted: [SiteCheck] {
        checks.sorted { a, b in
            if a.status.order != b.status.order { return a.status.order < b.status.order }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
    private var upCount: Int { checks.filter { $0.status == .ok }.count }
    private var downCount: Int { checks.filter { $0.status == .down }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let down = sorted.first(where: { $0.status == .down }) {
                // Outage headline: which site, and why, in plain words.
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(hex: "#F4505E"))
                    Text(downCount > 1 ? "\(downCount) sites en panne" : "\(down.name) est en panne")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(hex: "#FF8D97"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .layoutPriority(1)
                    Text(down.reason ?? "injoignable")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: "#F4505E"))
                        .lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 2)
                }
                .padding(.top, 6)
                .padding(.leading, 108)
                .padding(.trailing, 36)
            } else {
            HStack(spacing: 6) {
                Circle().fill(Color(hex: "#F7C3D4")).frame(width: 7, height: 7)
                Text("Sites clients")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                Text("\(upCount) en ligne")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#8E939C"))
                Text("·").font(.system(size: 11)).foregroundColor(Color(hex: "#6B7079"))
                Text("\(downCount) en panne")
                    .font(.system(size: 11))
                    .foregroundColor(downCount > 0 ? Color(hex: "#F4505E") : Color(hex: "#8E939C"))
                Spacer(minLength: 2)
            }
            .padding(.top, 6)
            .padding(.leading, 108)
            .padding(.trailing, 36)
            }

            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(sorted.prefix(3).enumerated()), id: \.element.id) { i, c in
                    let accent = Color(hex: c.status.hex)
                    HStack(spacing: 5) {
                        Circle().fill(accent).frame(width: 5, height: 5)
                        Text(c.name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: i == 0 ? "#C5C8CD" : "#9398A1"))
                            .lineLimit(1).truncationMode(.tail)
                            .layoutPriority(1)
                        if c.name != c.shortHost {
                            Text(c.shortHost)
                                .font(.system(size: 10))
                                .foregroundColor(Color(hex: "#6B7079"))
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer(minLength: 4)
                        let auditIssue = c.status == .ok ? audits[c.url]?.issues.first : nil
                        Text(c.reason ?? auditIssue ?? c.latencyLabel)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(c.reason != nil ? accent : auditIssue != nil ? Color(hex: SiteStatus.warning.hex) : Color(hex: "#6B7079"))
                            .lineLimit(1).truncationMode(.tail)
                            .monospacedDigit()
                        Button(action: { onOpen(c.id) }) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(Color(hex: "#6B7079"))
                                .frame(width: 18, height: 18)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(i == 0 && c.status != .ok ? accent.opacity(0.08) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
            }
            .padding(.top, 5)
            .padding(.leading, 108)
            .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 4)
    }
}

struct SitesDetailView: View {
    let site: SiteCheck
    var audit: SiteAudit? = nil
    let onClose: () -> Void
    @State private var fixStatus: String? = nil

    /// Daily / weekly facts on one line, e.g. "PageSpeed 87 · domaine expire dans 359 j · sitemap 20 URL".
    private var auditLine: String {
        guard let a = audit else { return "contrôles du jour et de la semaine à venir" }
        var parts = [a.pagespeedLabel, a.domainLabel]
        if let ok = a.sitemapOK { parts.append(ok ? "sitemap \(a.sitemapCount ?? 0) URL" : "pas de sitemap") }
        if a.weeklyAt != nil { parts.append(a.brokenLinks.isEmpty ? "\(a.linksChecked) liens ok" : "\(a.brokenLinks.count)/\(a.linksChecked) liens cassés") }
        return parts.joined(separator: " · ")
    }

    private var accent: Color { Color(hex: site.status.hex) }
    private var checkedLabel: String {
        guard let d = site.lastCheckedAt else { return "pas encore vérifié" }
        let s = Int(Date().timeIntervalSince(d))
        if s < 60 { return "vérifié à l’instant" }
        if s < 3600 { return "vérifié il y a \(s / 60) min" }
        return "vérifié à \(d.formatted(date: .omitted, time: .shortened))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(hex: "#6B7079"))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Circle().fill(accent).frame(width: 6, height: 6)
                Text(site.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                    .lineLimit(1).truncationMode(.tail)
                    .layoutPriority(1)
                Text(site.shortHost)
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#8E939C"))
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 2)
                Text(site.status.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(accent)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(accent.opacity(0.14))
                    .clipShape(Capsule())
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(site.finalURL ?? site.url)
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#9398A1"))
                    .lineLimit(1).truncationMode(.middle)
                HStack(spacing: 8) {
                    Label(site.httpLabel, systemImage: "network")
                        .font(.system(size: 10.5))
                        .foregroundColor(Color(hex: "#C5C8CD"))
                    Label(site.latencyLabel, systemImage: "timer")
                        .font(.system(size: 10.5))
                        .foregroundColor(site.latencyMs.map { $0 > SiteCheck.slowMs } == true ? Color(hex: "#FFD65C") : Color(hex: "#C5C8CD"))
                        .monospacedDigit()
                    Label(site.tlsLabel, systemImage: "lock")
                        .font(.system(size: 10))
                        .foregroundColor(site.tlsDaysLeft.map { $0 < SiteCheck.tlsWarningDays } == true ? Color(hex: "#FFD65C") : Color(hex: "#6B7079"))
                        .lineLimit(1)
                }
                Text(auditLine)
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#9398A1"))
                    .lineLimit(1).truncationMode(.tail)
                if let issues = audit?.issues, !issues.isEmpty {
                    Text(issues.prefix(2).joined(separator: " · ") + (audit?.brokenLinks.first.map { " — \($0)" } ?? ""))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(hex: SiteStatus.warning.hex))
                        .lineLimit(1).truncationMode(.tail)
                }
                HStack(spacing: 6) {
                    Text(checkedLabel)
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#6B7079"))
                    if let e = site.lastError {
                        Text("· \(e)")
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#F4505E"))
                            .lineLimit(1)
                    }
                    if let f = fixStatus {
                        Text("· \(f)")
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#9398A1"))
                            .lineLimit(1).truncationMode(.tail)
                    }
                }
                HStack(spacing: 10) {
                    if let u = URL(string: site.url) {
                        Button(action: { NSWorkspace.shared.open(u) }) {
                            Label("Ouvrir le site", systemImage: "globe")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(Color(hex: "#F7C3D4"))
                        }
                        .buttonStyle(.plain)
                    }
                    Button(action: {
                        SitesPoller.shared.checkNow()
                        SitesPoller.shared.auditDue(force: site.url)
                    }) {
                        Label("Revérifier", systemImage: "arrow.clockwise")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color(hex: "#C5C8CD"))
                    }
                    .buttonStyle(.plain)
                    if SitesPoller.repo(for: site.url) != nil {
                        Button(action: { fixStatus = SitesPoller.openInClaudeCode(site) }) {
                            Label("Corriger avec Claude Code", systemImage: "terminal")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(Color(hex: "#C5C8CD"))
                        }
                        .buttonStyle(.plain)
                        .help("Ouvre Claude Code dans le dépôt du client")
                    }
                }
            }
        }
        .padding(.top, 8)
        .padding(.leading, 108)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
    }
}

// MARK: - Agenda (Oculot) views

struct AgendaListView: View {
    let events: [AgendaEvent]
    let onOpen: (Int) -> Void

    private var todayCount: Int { events.filter(\.isToday).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(Color(hex: "#FFD65C")).frame(width: 7, height: 7)
                Text("Agenda · aujourd’hui")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                Text(todayCount == 0 ? "rien de prévu" : todayCount == 1 ? "1 rendez-vous" : "\(todayCount) rendez-vous")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#8E939C"))
            }
            .padding(.top, 6)
            .padding(.leading, 108)
            .padding(.trailing, 36)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(events.prefix(3).enumerated()), id: \.element.id) { i, e in
                    let accent = Color(hex: e.isToday ? "#FFD65C" : "#8E939C")
                    HStack(spacing: 5) {
                        Circle().fill(accent).frame(width: 5, height: 5)
                        Text(e.dayLabel.isEmpty ? e.timeLabel : "\(e.dayLabel) \(e.timeLabel)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(accent)
                            .monospacedDigit()
                            .lineLimit(1)
                            .layoutPriority(2)
                        Text(e.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: i == 0 ? "#C5C8CD" : "#9398A1"))
                            .lineLimit(1).truncationMode(.tail)
                            .layoutPriority(1)
                        if !e.shortLocation.isEmpty {
                            Text(e.shortLocation)
                                .font(.system(size: 10))
                                .foregroundColor(Color(hex: "#6B7079"))
                                .lineLimit(1).truncationMode(.tail)
                        }
                        Spacer(minLength: 4)
                        if e.meetingURL != nil {
                            Image(systemName: "video")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(Color(hex: "#6B7079"))
                        }
                        Button(action: { onOpen(i) }) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(Color(hex: "#6B7079"))
                                .frame(width: 18, height: 18)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(i == 0 ? accent.opacity(0.08) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
            }
            .padding(.top, 5)
            .padding(.leading, 108)
            .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 4)
    }
}

struct AgendaDetailView: View {
    let event: AgendaEvent
    let onClose: () -> Void

    private var accent: Color { Color(hex: event.isToday ? "#FFD65C" : "#8E939C") }

    private var countdown: String {
        let m = event.minutesUntilStart()
        if event.isAllDay { return event.isToday ? "aujourd’hui" : event.dayLabel }
        if m < 0 { return Date() < event.end ? "en cours" : "terminé" }
        if m < 60 { return "dans \(m) min" }
        if m < 24 * 60 { return "dans \(m / 60) h" }
        return event.dayLabel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(hex: "#6B7079"))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Circle().fill(accent).frame(width: 6, height: 6)
                Text(event.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                    .lineLimit(1).truncationMode(.tail)
                    .layoutPriority(1)
                Spacer(minLength: 2)
                Text(countdown)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(accent)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(accent.opacity(0.14))
                    .clipShape(Capsule())
            }

            VStack(alignment: .leading, spacing: 5) {
                Label(event.fullDateLabel, systemImage: "clock")
                    .font(.system(size: 10.5))
                    .foregroundColor(Color(hex: "#C5C8CD"))
                    .lineLimit(1)
                if !event.location.isEmpty, !event.location.hasPrefix("http") {
                    Label(event.location.replacingOccurrences(of: "\n", with: ", "), systemImage: "mappin.and.ellipse")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#9398A1"))
                        .lineLimit(1).truncationMode(.tail)
                }
                let desc = event.description.trimmingCharacters(in: .whitespacesAndNewlines)
                if !desc.isEmpty {
                    Text(desc.replacingOccurrences(of: "\n", with: " "))
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#9398A1"))
                        .lineLimit(2)
                }
                HStack(spacing: 10) {
                    if let u = event.meetingURL {
                        Button(action: { NSWorkspace.shared.open(u) }) {
                            Label("Rejoindre la visio", systemImage: "video")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(Color(hex: "#FFD65C"))
                        }
                        .buttonStyle(.plain)
                    }
                    Button(action: { NSWorkspace.shared.open(AgendaPoller.calendarURL) }) {
                        Label("Ouvrir l’agenda", systemImage: "arrow.up.right.square")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color(hex: event.meetingURL == nil ? "#FFD65C" : "#C5C8CD"))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 8)
        .padding(.leading, 108)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
    }
}
