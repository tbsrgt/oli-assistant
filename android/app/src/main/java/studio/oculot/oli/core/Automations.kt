package studio.oculot.oli.core

import java.time.Duration
import java.time.Instant
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

// Règles pures des automatisations (briefing, rappels, échéances, verrou) : testables sur la JVM.

data class Reminder(
    val id: String,
    val title: String,
    val start: Instant,
    val triggerAt: Instant,
    val joinUrl: String?,
    val address: String?,
)

data class BriefingText(val title: String, val body: String)

object Automations {
    val BRIEFING_TIME: LocalTime = LocalTime.of(8, 30)
    val REMINDER_BEFORE: Duration = Duration.ofMinutes(10)
    /** Au-delà de 5 min en arrière-plan, l'app redemande l'empreinte ou le code. */
    const val LOCK_AFTER_MS = 5 * 60 * 1000L
    /** Heure à partir de laquelle on prévient la veille d'une mise en ligne. */
    const val DEADLINE_HOUR = 9

    /** Prochain briefing : aujourd'hui à 8 h 30 si c'est encore à venir, sinon demain (heure locale). */
    fun nextBriefing(now: ZonedDateTime, at: LocalTime = BRIEFING_TIME): ZonedDateTime {
        val today = now.toLocalDate().atTime(at).atZone(now.zone)
        return if (today.isAfter(now)) today else now.toLocalDate().plusDays(1).atTime(at).atZone(now.zone)
    }

    /** Rappels à programmer : rendez-vous à heure fixe dont l'instant « 10 min avant » est encore à venir. */
    fun reminders(events: List<AgendaEvent>, now: Instant): List<Reminder> =
        events.filter { !it.isAllDay }
            .map { e ->
                Reminder(e.id, e.title, e.start, e.start.minus(REMINDER_BEFORE), meetingLink(e), address(e))
            }
            .filter { it.triggerAt.isAfter(now) }
            .distinctBy { it.id }

    private val meetingHosts = listOf("meet.google.com", "zoom.us", "zoom.com", "teams.microsoft.com", "teams.live.com", "whereby.com", "meet.jit.si")
    private val urlRegex = Regex("https?://[^\\s<>\"')]+", RegexOption.IGNORE_CASE)

    /** Premier lien Meet / Zoom / Teams trouvé dans le lieu, le lien ou la description. */
    fun meetingLink(e: AgendaEvent): String? {
        for (text in listOf(e.location, e.url, e.description)) {
            for (m in urlRegex.findAll(text)) {
                val u = m.value.trimEnd('.', ',', ';', '>')
                if (meetingHosts.any { h -> u.lowercase().substringAfter("://").substringBefore('/').let { it == h || it.endsWith(".$h") } }) return u
            }
        }
        return null
    }

    private val notAddresses = setOf("visio", "visioconférence", "google meet", "meet", "zoom", "teams", "microsoft teams", "en ligne", "téléphone", "telephone", "appel")

    /** Le lieu s'il ressemble à une adresse (ni un lien, ni « Visio »). */
    fun address(e: AgendaEvent): String? {
        val l = e.location.trim()
        if (l.isEmpty() || urlRegex.containsMatchIn(l)) return null
        if (l.lowercase() in notAddresses) return null
        return l
    }

    /** Rendez-vous du jour (heure locale) qui ne sont pas encore terminés. */
    fun todayEvents(events: List<AgendaEvent>, now: Instant, zone: ZoneId): List<AgendaEvent> {
        val today = now.atZone(zone).toLocalDate()
        return events.filter { it.start.atZone(zone).toLocalDate() == today && it.end.isAfter(now) || (it.isAllDay && it.start.atZone(zone).toLocalDate() == today) }
            .distinctBy { it.id }
    }

    /** Texte du briefing du matin : rendez-vous du jour, projets en retard ou à J-3, sites en panne. */
    fun briefing(
        events: List<AgendaEvent>,
        projects: List<EspaceProject>?,
        sites: List<SiteCheck>,
        now: Instant,
        zone: ZoneId,
    ): BriefingText {
        val lines = ArrayList<String>()
        val today = todayEvents(events, now, zone)
        if (today.isNotEmpty()) {
            val fmt = DateTimeFormatter.ofPattern("HH:mm", Locale.FRANCE)
            val list = today.take(4).joinToString(", ") { e ->
                if (e.isAllDay) e.title else "${fmt.format(e.start.atZone(zone))} ${e.title}"
            } + if (today.size > 4) "…" else ""
            lines += (if (today.size == 1) "1 rendez-vous : " else "${today.size} rendez-vous : ") + list
        }
        val urgent = projects.orEmpty().filter { !it.isDone && it.daysLeft != null && it.daysLeft <= 3 }
        if (urgent.isNotEmpty()) {
            lines += "Projets : " + urgent.take(4).joinToString(", ") { p ->
                when {
                    p.isLate -> "${p.name} en retard (${p.daysLabel})"
                    p.daysLeft == 0L -> "${p.name} pour aujourd’hui"
                    else -> "${p.name} à ${p.daysLabel}"
                }
            }
        }
        val down = sites.filter { it.status == SiteStatus.DOWN }
        if (down.isNotEmpty()) {
            lines += (if (down.size == 1) "Site en panne : " else "${down.size} sites en panne : ") + down.joinToString(", ") { it.name }
        } else if (sites.isNotEmpty()) {
            lines += "Sites : tout roule."
        }
        val title = when {
            down.isNotEmpty() -> "Bonjour ! Un œil sur les sites ce matin"
            today.isEmpty() && urgent.isEmpty() -> "Bonjour ! Journée calme"
            else -> "Bonjour ! Voici ta journée"
        }
        if (today.isEmpty() && urgent.isEmpty() && down.isEmpty()) {
            lines.add(0, "Aucun rendez-vous, rien d’urgent. Profites-en !")
        }
        return BriefingText(title, lines.joinToString("\n"))
    }

    /**
     * Mises en ligne de demain à annoncer (une fois par projet et par date), à partir de 9 h.
     * Renvoie les projets à notifier et la nouvelle mémoire des annonces faites.
     */
    fun deadlinesToNotify(
        projects: List<EspaceProject>,
        alreadyNotified: Set<String>,
        nowHour: Int,
    ): Pair<List<EspaceProject>, Set<String>> {
        val eve = projects.filter { !it.isDone && it.daysLeft == 1L && it.dueAt != null }
        val keys = eve.associateBy { "${it.id}@${it.dueAt!!.take(10)}" }
        val keep = alreadyNotified.filter { it in keys }.toSet()
        if (nowHour < DEADLINE_HOUR) return emptyList<EspaceProject>() to keep
        val fresh = keys.filterKeys { it !in keep }
        return fresh.values.toList() to (keep + fresh.keys)
    }

    /**
     * Faut-il redemander le déverrouillage ? Oui au démarrage à froid (jamais déverrouillé)
     * et au retour après plus de 5 min en arrière-plan.
     */
    fun needsUnlock(lastBackgroundAtMs: Long?, nowMs: Long, unlockedOnce: Boolean): Boolean {
        if (!unlockedOnce) return true
        val bg = lastBackgroundAtMs ?: return false
        return nowMs - bg > LOCK_AFTER_MS
    }
}
