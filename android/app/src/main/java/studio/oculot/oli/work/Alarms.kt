package studio.oculot.oli.work

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import studio.oculot.oli.core.AgendaEvent
import studio.oculot.oli.core.Automations
import studio.oculot.oli.data.AutomationPrefs
import studio.oculot.oli.data.Load
import studio.oculot.oli.data.MemoryStore
import studio.oculot.oli.data.Repository
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

/** Alarmes du briefing (8 h 30) et des rappels de rendez-vous (10 min avant). */
object Alarms {
    const val ACTION_BRIEFING = "studio.oculot.oli.BRIEFING"
    const val ACTION_REMINDER = "studio.oculot.oli.RAPPEL"
    private const val BRIEFING_CODE = 830

    private fun manager(context: Context) = context.getSystemService(AlarmManager::class.java)

    fun canBeExact(context: Context): Boolean =
        Build.VERSION.SDK_INT < 31 || manager(context)?.canScheduleExactAlarms() == true

    /**
     * Exacte si le système l'autorise, sinon dans une fenêtre de 10 min : qui finit à l'heure voulue
     * (rappels, pour ne jamais prévenir en retard) ou qui commence à l'heure voulue (briefing).
     */
    private fun setAt(context: Context, atMs: Long, pi: PendingIntent, windowBefore: Boolean = true) {
        val am = manager(context) ?: return
        val start = if (windowBefore) atMs - 10 * 60_000L else atMs
        try {
            if (canBeExact(context)) am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMs, pi)
            else am.setWindow(AlarmManager.RTC_WAKEUP, start, 10 * 60_000L, pi)
        } catch (_: SecurityException) {
            am.setWindow(AlarmManager.RTC_WAKEUP, start, 10 * 60_000L, pi)
        }
    }

    private fun briefingIntent(context: Context) = PendingIntent.getBroadcast(
        context, BRIEFING_CODE, Intent(context, AlarmReceiver::class.java).setAction(ACTION_BRIEFING),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    /** (Re)programme le prochain briefing, ou l'annule s'il est désactivé. */
    fun scheduleBriefing(context: Context) {
        val pi = briefingIntent(context)
        if (!AutomationPrefs(context).isOn(AutomationPrefs.Key.BRIEFING)) {
            manager(context)?.cancel(pi); return
        }
        val next = Automations.nextBriefing(ZonedDateTime.now())
        setAt(context, next.toInstant().toEpochMilli(), pi, windowBefore = false)
    }

    /** Programme un rappel par rendez-vous à venir et annule ceux qui n'existent plus. */
    fun scheduleReminders(context: Context, events: List<AgendaEvent>) {
        val memory = MemoryStore(context)
        val am = manager(context) ?: return
        val enabled = AutomationPrefs(context).isOn(AutomationPrefs.Key.REMINDERS)
        val plan = if (enabled) Automations.reminders(events, Instant.now()) else emptyList()
        val fmt = DateTimeFormatter.ofPattern("HH:mm", Locale.FRANCE)
        val newCodes = HashSet<String>()
        for (r in plan.take(30)) {
            val code = r.id.hashCode()
            val intent = Intent(context, AlarmReceiver::class.java).setAction(ACTION_REMINDER)
                .putExtra("id", r.id).putExtra("titre", r.title)
                .putExtra("heure", fmt.format(r.start.atZone(ZoneId.systemDefault())))
                .putExtra("visio", r.joinUrl).putExtra("adresse", r.address)
            val pi = PendingIntent.getBroadcast(context, code, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            setAt(context, r.triggerAt.toEpochMilli(), pi)
            newCodes += code.toString()
        }
        for (old in memory.reminderCodes() - newCodes) {
            val code = old.toIntOrNull() ?: continue
            val pi = PendingIntent.getBroadcast(context, code, Intent(context, AlarmReceiver::class.java).setAction(ACTION_REMINDER),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_NO_CREATE)
            if (pi != null) { am.cancel(pi); pi.cancel() }
        }
        memory.saveReminderCodes(newCodes)
    }
}

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Alarms.ACTION_REMINDER -> {
                if (!AutomationPrefs(context).isOn(AutomationPrefs.Key.REMINDERS)) return
                Notifier.createChannels(context)
                Notifier.reminder(
                    context,
                    id = intent.getStringExtra("id") ?: return,
                    title = intent.getStringExtra("titre") ?: "Rendez-vous",
                    timeLabel = intent.getStringExtra("heure").orEmpty(),
                    joinUrl = intent.getStringExtra("visio"),
                    address = intent.getStringExtra("adresse"),
                )
            }
            Alarms.ACTION_BRIEFING -> {
                WorkManager.getInstance(context).enqueueUniqueWork(
                    "oli-briefing", ExistingWorkPolicy.REPLACE,
                    OneTimeWorkRequestBuilder<BriefingWorker>()
                        .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                        .build(),
                )
                Alarms.scheduleBriefing(context)    // le lendemain
            }
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIMEZONE_CHANGED, Intent.ACTION_TIME_CHANGED -> {
                Alarms.scheduleBriefing(context)
                SiteWatchWorker.schedule(context)
            }
        }
    }
}

/** Prépare et affiche le briefing du matin. */
class BriefingWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val ctx = applicationContext
        if (!AutomationPrefs(ctx).isOn(AutomationPrefs.Key.BRIEFING)) return Result.success()
        val memory = MemoryStore(ctx)
        val today = java.time.LocalDate.now().toString()
        if (memory.lastBriefingDay() == today) return Result.success()   // un seul briefing par jour
        val repo = Repository(ctx)
        val espace = repo.loadEspace()
        val agenda = repo.loadAgenda()
        val run = repo.checkSites()
        Automator.afterRefresh(ctx, espace, agenda, run)
        val text = Automations.briefing(
            events = (agenda as? Load.Ok)?.value.orEmpty(),
            projects = (espace as? Load.Ok)?.value,
            sites = run.checks,
            now = Instant.now(),
            zone = ZoneId.systemDefault(),
        )
        Notifier.createChannels(ctx)
        Notifier.briefing(ctx, text)
        memory.saveLastBriefingDay(today)
        return Result.success()
    }
}
