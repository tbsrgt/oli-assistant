package studio.oculot.oli.core

import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale

// Agenda : lecture simple d'un flux iCalendar (portage allégé d'AgendaICS.swift).
// VEVENT, dates UTC / TZID / journée entière, dépliage des lignes, échappements,
// DTEND ou DURATION, RRULE DAILY/WEEKLY (INTERVAL, COUNT, UNTIL, BYDAY), EXDATE, RECURRENCE-ID, annulés.

data class AgendaEvent(
    val id: String,
    val title: String,
    val start: Instant,
    val end: Instant,
    val isAllDay: Boolean,
    val location: String,
    val description: String = "",
    val url: String = "",
) {
    fun timeLabel(zone: ZoneId = ZoneId.systemDefault()): String =
        if (isAllDay) "Journée" else DateTimeFormatter.ofPattern("HH:mm", Locale.FRANCE).format(start.atZone(zone))

    /** « aujourd’hui », « demain » ou « lun. 6 oct. ». */
    fun dayLabel(today: LocalDate = LocalDate.now(), zone: ZoneId = ZoneId.systemDefault()): String {
        val d = start.atZone(zone).toLocalDate()
        return when (d) {
            today -> "aujourd’hui"
            today.plusDays(1) -> "demain"
            else -> DateTimeFormatter.ofPattern("EEE d MMM", Locale.FRANCE).format(d)
        }
    }

    /** Premier morceau du lieu (avant la virgule). */
    val shortLocation: String
        get() {
            val l = location.trim()
            if (l.isEmpty()) return ""
            if (l.startsWith("http")) return "Visio"
            return l.substringBefore(',').trim()
        }
}

object Ics {

    private class Prop(val name: String, val params: Map<String, String>, val value: String)

    private class Block(val props: MutableList<Prop> = mutableListOf()) {
        fun first(n: String) = props.firstOrNull { it.name == n }
        fun all(n: String) = props.filter { it.name == n }
        fun value(n: String) = first(n)?.value
    }

    private class ParsedDate(val instant: Instant, val isAllDay: Boolean, val zone: ZoneId)

    /** Occurrences entre `now − 1 h` et `now + days` jours, triées. */
    fun parse(text: String, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault(), days: Long = 14): List<AgendaEvent> {
        val windowStart = now.minus(1, ChronoUnit.HOURS)
        val windowEnd = now.plus(days, ChronoUnit.DAYS)
        val blocks = eventBlocks(unfold(text))

        // Occurrences modifiées (RECURRENCE-ID) : on retire l'occurrence générée correspondante.
        val overridden = HashSet<String>()
        for (b in blocks) {
            val uid = b.value("UID") ?: continue
            val rid = b.first("RECURRENCE-ID") ?: continue
            parseDate(rid.value, rid.params, zone)?.let { overridden += "$uid@${it.instant.epochSecond}" }
        }

        val out = ArrayList<AgendaEvent>()
        for (b in blocks) {
            if (b.value("STATUS")?.uppercase() == "CANCELLED") continue
            val dt = b.first("DTSTART") ?: continue
            val start = parseDate(dt.value, dt.params, zone) ?: continue
            val uid = b.value("UID") ?: "sans-uid-${out.size}"
            val title = b.value("SUMMARY")?.let(::unescape)?.ifBlank { null } ?: "(sans titre)"
            val location = b.value("LOCATION")?.let(::unescape).orEmpty()
            val description = b.value("DESCRIPTION")?.let(::unescape).orEmpty()
            val link = (b.value("URL") ?: b.value("X-GOOGLE-CONFERENCE")).orEmpty().trim()

            val duration: Duration = b.first("DTEND")?.let { p ->
                parseDate(p.value, p.params, zone)?.let { e ->
                    Duration.between(start.instant, e.instant).let { if (it.isNegative) Duration.ZERO else it }
                }
            } ?: b.value("DURATION")?.let(::parseDuration)
            ?: if (start.isAllDay) Duration.ofDays(1) else Duration.ZERO

            val exdates = b.all("EXDATE").flatMap { p ->
                p.value.split(',').mapNotNull { parseDate(it, p.params, zone)?.instant }
            }
            val isOverride = b.first("RECURRENCE-ID") != null
            val rrule = b.value("RRULE")
            val starts = if (rrule != null && !isOverride) expand(rrule, start, windowEnd) else listOf(start.instant)

            for (s in starts) {
                if (exdates.any { it == s }) continue
                val id = "$uid@${s.epochSecond}"
                if (!isOverride && id in overridden) continue
                if (s.isBefore(windowStart) || s.isAfter(windowEnd)) {
                    // Un événement en cours (commencé avant la fenêtre mais pas fini) reste utile.
                    if (!(s.isBefore(windowStart) && s.plus(duration).isAfter(now))) continue
                }
                out += AgendaEvent(id, title, s, s.plus(duration), start.isAllDay, location, description, link)
            }
        }
        return out.sortedWith(compareBy<AgendaEvent> { it.start }.thenBy { it.isAllDay }.thenBy { it.title })
    }

    // Lignes et propriétés

    /** Dépliage RFC 5545 : une ligne qui commence par un espace ou une tabulation prolonge la précédente. */
    internal fun unfold(text: String): List<String> {
        val lines = ArrayList<String>()
        for (raw in text.split("\n")) {
            val line = raw.removeSuffix("\r")
            if (line.isNotEmpty() && (line[0] == ' ' || line[0] == '\t') && lines.isNotEmpty()) {
                lines[lines.size - 1] = lines.last() + line.substring(1)
            } else {
                lines += line
            }
        }
        return lines
    }

    private fun eventBlocks(lines: List<String>): List<Block> {
        val blocks = ArrayList<Block>()
        var current: Block? = null
        var depth = 0
        for (line in lines) {
            val upper = line.uppercase()
            if (upper.startsWith("BEGIN:")) {
                if (current != null) depth++
                else if (upper.substring(6).trim() == "VEVENT") { current = Block(); depth = 0 }
                continue
            }
            if (upper.startsWith("END:")) {
                if (current != null) {
                    if (depth > 0) depth--
                    else if (upper.substring(4).trim() == "VEVENT") { blocks += current; current = null }
                }
                continue
            }
            if (current == null || depth != 0) continue
            parseProperty(line)?.let { current.props += it }
        }
        return blocks
    }

    private fun parseProperty(line: String): Prop? {
        var inQuotes = false
        var split = -1
        for ((i, c) in line.withIndex()) {
            if (c == '"') inQuotes = !inQuotes
            else if (c == ':' && !inQuotes) { split = i; break }
        }
        if (split <= 0) return null
        val parts = line.substring(0, split).split(';').filter { it.isNotEmpty() }
        val name = parts.firstOrNull()?.uppercase() ?: return null
        val params = HashMap<String, String>()
        for (p in parts.drop(1)) {
            val eq = p.indexOf('=')
            if (eq < 0) continue
            params[p.substring(0, eq).uppercase()] = p.substring(eq + 1).trim('"')
        }
        return Prop(name, params, line.substring(split + 1))
    }

    /** Retire les échappements de texte : \n \N \, \; \\ */
    internal fun unescape(s: String): String {
        val sb = StringBuilder()
        var i = 0
        while (i < s.length) {
            val c = s[i]
            if (c != '\\' || i == s.length - 1) { sb.append(c); i++; continue }
            when (val n = s[i + 1]) {
                'n', 'N' -> sb.append('\n')
                ',', ';', '\\' -> sb.append(n)
                else -> sb.append('\\').append(n)
            }
            i += 2
        }
        return sb.toString()
    }

    // Dates

    private fun parseDate(raw: String, params: Map<String, String>, localZone: ZoneId): ParsedDate? {
        val s = raw.trim()
        val digits = s.filter { it.isDigit() }
        if (digits.length < 8) return null
        val y = digits.substring(0, 4).toIntOrNull() ?: return null
        val mo = digits.substring(4, 6).toIntOrNull() ?: return null
        val d = digits.substring(6, 8).toIntOrNull() ?: return null
        val dateOnly = params["VALUE"]?.uppercase() == "DATE" || (s.length == 8 && digits.length == 8)
        return try {
            if (dateOnly) {
                ParsedDate(LocalDate.of(y, mo, d).atStartOfDay(localZone).toInstant(), true, localZone)
            } else {
                if (digits.length < 14) return null
                val ldt = LocalDateTime.of(y, mo, d, digits.substring(8, 10).toInt(),
                    digits.substring(10, 12).toInt(), digits.substring(12, 14).toInt())
                val zone: ZoneId = when {
                    s.endsWith("Z") -> ZoneOffset.UTC
                    params["TZID"] != null -> zoneFor(params["TZID"]!!) ?: localZone
                    else -> localZone       // heure « flottante » : fuseau du téléphone
                }
                ParsedDate(ldt.atZone(zone).toInstant(), false, zone)
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun zoneFor(tzid: String): ZoneId? {
        val windows = mapOf(
            "Romance Standard Time" to "Europe/Paris",
            "W. Europe Standard Time" to "Europe/Berlin",
            "Central European Standard Time" to "Europe/Warsaw",
            "GMT Standard Time" to "Europe/London",
        )
        return try { ZoneId.of(windows[tzid] ?: tzid) } catch (_: Exception) { null }
    }

    /** DURATION `P1DT2H30M` → durée. */
    internal fun parseDuration(s: String): Duration? {
        var total = 0L
        var num = ""
        var inTime = false
        var sign = 1L
        for (c in s.uppercase()) {
            when (c) {
                '-' -> sign = -1
                '+', 'P' -> {}
                'T' -> inTime = true
                in '0'..'9' -> num += c
                'W' -> { total += (num.toLongOrNull() ?: 0) * 7 * 86400; num = "" }
                'D' -> { total += (num.toLongOrNull() ?: 0) * 86400; num = "" }
                'H' -> { total += (num.toLongOrNull() ?: 0) * 3600; num = "" }
                'M' -> { total += (num.toLongOrNull() ?: 0) * if (inTime) 60 else 0; num = "" }
                'S' -> { total += num.toLongOrNull() ?: 0; num = "" }
                else -> return null
            }
        }
        return Duration.ofSeconds(total * sign)
    }

    // RRULE (DAILY / WEEKLY ; les autres fréquences ne donnent que la première occurrence)

    private val weekdayCodes = listOf("MO", "TU", "WE", "TH", "FR", "SA", "SU")   // index = DayOfWeek.value − 1

    private fun expand(rrule: String, start: ParsedDate, windowEnd: Instant): List<Instant> {
        val rule = rrule.split(';').mapNotNull {
            val kv = it.split('=', limit = 2)
            if (kv.size == 2) kv[0].uppercase() to kv[1].uppercase() else null
        }.toMap()
        val freq = rule["FREQ"]
        if (freq != "DAILY" && freq != "WEEKLY") return listOf(start.instant)

        val interval = (rule["INTERVAL"]?.toIntOrNull() ?: 1).coerceAtLeast(1)
        val count = rule["COUNT"]?.toIntOrNull()
        val until: Instant? = rule["UNTIL"]?.let { u ->
            parseDate(u, if (u.length == 8) mapOf("VALUE" to "DATE") else emptyMap(), start.zone)?.let {
                if (it.isAllDay) it.instant.plusSeconds(86399) else it.instant
            }
        }
        val startZdt: ZonedDateTime = start.instant.atZone(start.zone)
        val mondayBased = startZdt.dayOfWeek.value - 1
        val byDay = HashSet<Int>()
        if (freq == "WEEKLY") {
            rule["BYDAY"]?.split(',')?.forEach { code ->
                val i = weekdayCodes.indexOf(code.takeLast(2))
                if (i >= 0) byDay += i
            }
            if (byDay.isEmpty()) byDay += mondayBased
        }

        val out = ArrayList<Instant>()
        var produced = 0
        for (k in 0 until 4000) {
            val candidate = startZdt.plusDays(k.toLong())
            val inst = candidate.toInstant()
            if (inst.isAfter(windowEnd)) break
            if (until != null && inst.isAfter(until)) break
            val matches = if (freq == "DAILY") k % interval == 0
            else ((k + mondayBased) / 7) % interval == 0 && (candidate.dayOfWeek.value - 1) in byDay
            if (matches) {
                produced++
                out += inst
                if (count != null && produced >= count) break
            }
        }
        return out
    }
}
