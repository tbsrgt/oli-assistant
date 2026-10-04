package studio.oculot.oli.work

import android.content.Context
import studio.oculot.oli.core.AgendaEvent
import studio.oculot.oli.core.Automations
import studio.oculot.oli.core.EspaceProject
import studio.oculot.oli.data.AutomationPrefs
import studio.oculot.oli.data.Load
import studio.oculot.oli.data.MemoryStore
import studio.oculot.oli.data.SiteRun
import studio.oculot.oli.data.Repository
import studio.oculot.oli.core.ClaudeBoard
import studio.oculot.oli.core.ClaudeCode
import studio.oculot.oli.widget.OliWidget
import java.time.Instant
import java.time.LocalTime

/** Ce qui suit chaque actualisation (écran ou tâche de fond) : alertes, rappels, widget. */
object Automator {
    suspend fun afterRefresh(
        context: Context,
        espace: Load<List<EspaceProject>>?,
        agenda: Load<List<AgendaEvent>>?,
        run: SiteRun?,
    ) {
        val prefs = AutomationPrefs(context)
        val memory = MemoryStore(context)
        Notifier.createChannels(context)

        if (run != null && run.checks.any { it.status == studio.oculot.oli.core.SiteStatus.DOWN }) {
            runCatching { studio.oculot.oli.data.GameStore(context).record(outageToday = true) }
        }
        if (run != null && prefs.isOn(AutomationPrefs.Key.OUTAGES)) {
            run.outages.forEach { Notifier.outage(context, it) }
            run.recoveries.forEach { Notifier.recovery(context, it) }
        }

        if (espace is Load.Ok) {
            val (toNotify, mem) = Automations.deadlinesToNotify(espace.value, memory.deadlinesNotified(), LocalTime.now().hour)
            memory.saveDeadlinesNotified(mem)
            if (prefs.isOn(AutomationPrefs.Key.DEADLINES)) toNotify.forEach { Notifier.deadline(context, it) }
        }

        if (agenda is Load.Ok) {
            Alarms.scheduleReminders(context, agenda.value)
            val now = Instant.now()
            val next = agenda.value.firstOrNull { !it.isAllDay && it.end.isAfter(now) } ?: agenda.value.firstOrNull { it.end.isAfter(now) }
            memory.saveNextEvent(next?.title, next?.start?.toEpochMilli())
        } else if (agenda == Load.NotConfigured) {
            Alarms.scheduleReminders(context, emptyList())
            memory.saveNextEvent(null, null)
        }

        Alarms.scheduleBriefing(context)
        Alarms.scheduleEvening(context)
        runCatching { OliWidget.refresh(context) }
        studio.oculot.oli.overlay.OverlayService.refresh(context)
    }

    /** Claude Code : notifie les nouvelles demandes d'accord et les sessions terminées (Mac joignable seulement). */
    suspend fun claudeCheck(context: Context, quick: Boolean = true, notify: Boolean = true): Load<ClaudeBoard> {
        val board = Repository(context).claudeBoard(quick)
        if (board !is Load.Ok) return board
        val memory = MemoryStore(context)
        val news = ClaudeCode.news(ClaudeCode.decodeStates(memory.claudeStates()), memory.claudeSeenApprovals(), board.value)
        if (notify && AutomationPrefs(context).isOn(AutomationPrefs.Key.CLAUDE)) {
            Notifier.createChannels(context)
            news.newApprovals.forEach { Notifier.claudeWaiting(context, it) }
            news.finished.forEach { Notifier.claudeFinished(context, it) }
        }
        memory.saveClaude(ClaudeCode.encodeStates(board.value), board.value.approvals.map { it.id }.toSet(),
            board.value.shortLine, board.value.approvals.size)
        return board
    }
}
