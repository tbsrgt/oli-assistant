package studio.oculot.oli.core

import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDate

// Gamification légère : expérience, niveau d'Oli, séries de jours, défis du jour, badges.
// Tout reste sur le téléphone. Règles pures, testables sur la JVM.

enum class GameEvent(val xp: Int, val countsForStreak: Boolean = false) {
    BRIEFING_READ(20, true),
    PHONE_CLEANED(30, true),
    PHONE_TIDIED(30, true),
    SECURITY_CHECK(15),
    CONNECTED(25),
    ASKED_OLI(10),
    CLAUDE_DECISION(10),
    CHALLENGE_DONE(40),
}

data class Level(val level: Int, val xpInLevel: Int, val xpForNext: Int) {
    val progress: Float get() = if (xpForNext == 0) 1f else xpInLevel.toFloat() / xpForNext
}

data class Challenge(val id: String, val title: String, val manual: Boolean = false, val help: String = "")

data class Badge(val id: String, val title: String, val description: String)

data class GameState(
    val xp: Int = 0,
    val streak: Int = 0,
    val bestStreak: Int = 0,
    val lastStreakDay: String? = null,
    val day: String? = null,                    // jour des compteurs « aujourd'hui »
    val todayEvents: Set<String> = emptySet(),
    val challengesDone: Set<String> = emptySet(), // défis réussis aujourd'hui
    val freedToday: Long = 0,
    val freedTotal: Long = 0,
    val lastOutageDay: String? = null,
    val challengesTotal: Int = 0,
    val counters: Map<String, Int> = emptyMap(),
    val bestSecurity: Int = 0,
    val allConnected: Boolean = false,
    val badges: Set<String> = emptySet(),
) {
    val level: Level get() = Game.levelFor(xp)

    fun toJson(): String = JSONObject().apply {
        put("xp", xp); put("streak", streak); put("best", bestStreak)
        put("lastStreak", lastStreakDay ?: JSONObject.NULL); put("day", day ?: JSONObject.NULL)
        put("events", JSONArray(todayEvents.toList())); put("done", JSONArray(challengesDone.toList()))
        put("freedToday", freedToday); put("freedTotal", freedTotal)
        put("lastOutage", lastOutageDay ?: JSONObject.NULL); put("challenges", challengesTotal)
        put("counters", JSONObject(counters as Map<*, *>)); put("bestSecurity", bestSecurity)
        put("allConnected", allConnected); put("badges", JSONArray(badges.toList()))
    }.toString()

    companion object {
        fun fromJson(raw: String?): GameState {
            if (raw.isNullOrBlank()) return GameState()
            return try {
                val o = JSONObject(raw)
                fun set(k: String) = o.optJSONArray(k)?.let { a -> (0 until a.length()).map { a.getString(it) }.toSet() } ?: emptySet()
                fun str(k: String) = if (o.isNull(k)) null else o.optString(k).ifBlank { null }
                val c = o.optJSONObject("counters")
                GameState(
                    xp = o.optInt("xp"), streak = o.optInt("streak"), bestStreak = o.optInt("best"),
                    lastStreakDay = str("lastStreak"), day = str("day"),
                    todayEvents = set("events"), challengesDone = set("done"),
                    freedToday = o.optLong("freedToday"), freedTotal = o.optLong("freedTotal"),
                    lastOutageDay = str("lastOutage"), challengesTotal = o.optInt("challenges"),
                    counters = c?.keys()?.asSequence()?.associateWith { c.optInt(it) } ?: emptyMap(),
                    bestSecurity = o.optInt("bestSecurity"), allConnected = o.optBoolean("allConnected"),
                    badges = set("badges"),
                )
            } catch (_: Exception) { GameState() }
        }
    }
}

/** Résultat d'une action : nouvel état, badges et défis débloqués (pour la petite fête). */
data class GameUpdate(val state: GameState, val newBadges: List<Badge>, val newChallenges: List<Challenge>, val levelUp: Boolean)

object Game {
    /** Niveau L atteint à 50·L·(L−1) XP : 0, 100, 300, 600, 1 000… */
    fun xpForLevel(level: Int): Int = 50 * level * (level - 1)

    fun levelFor(xp: Int): Level {
        var l = 1
        while (xpForLevel(l + 1) <= xp) l++
        return Level(l, xp - xpForLevel(l), xpForLevel(l + 1) - xpForLevel(l))
    }

    /** Série de jours : même jour → inchangée, lendemain → +1, sinon → repart à 1. */
    fun nextStreak(lastDay: LocalDate?, streak: Int, today: LocalDate): Int = when (lastDay) {
        today -> streak
        today.minusDays(1) -> streak + 1
        else -> 1
    }

    val pool = listOf(
        Challenge("briefing", "Lis le briefing du matin"),
        Challenge("liberer", "Libère 500 Mo"),
        Challenge("zero_panne", "Zéro site en panne cette semaine"),
        Challenge("ranger", "Range tes téléchargements"),
        Challenge("question", "Pose une question à Oli"),
        Challenge("securite", "Fais l’audit de sécurité du téléphone"),
        Challenge("instagram", "Réponds aux 2 commentaires Instagram", manual = true,
            help = "Instagram n’est pas relié à l’app Android : coche quand c’est fait."),
        Challenge("relance", "Relance un devis en attente", manual = true, help = "Coche quand c’est fait."),
        Challenge("boite", "Passe ta boîte mail sous les 10 messages", manual = true, help = "Coche quand c’est fait."),
    )

    /** Trois défis par jour, toujours les mêmes pour une date donnée (dont au plus un à cocher soi-même). */
    fun challengesFor(day: LocalDate): List<Challenge> {
        val auto = pool.filter { !it.manual }
        val manual = pool.filter { it.manual }
        val n = day.toEpochDay().toInt()
        val a1 = auto[Math.floorMod(n, auto.size)]
        val a2 = auto[Math.floorMod(n * 7 + 3, auto.size)].let { if (it == a1) auto[Math.floorMod(n + 1, auto.size)] else it }
        return listOf(a1, a2, manual[Math.floorMod(n, manual.size)])
    }

    val badges = listOf(
        Badge("premier_pas", "Premier pas", "Ta première action avec Oli."),
        Badge("tout_connecte", "Tout est branché", "Espace, agenda, sites et Claude connectés."),
        Badge("serie_3", "Sur ta lancée", "3 jours de suite."),
        Badge("serie_7", "Semaine parfaite", "7 jours de suite."),
        Badge("niveau_5", "Oli niveau 5", "Atteindre le niveau 5."),
        Badge("giga", "Un giga de libre", "1 Go libéré au total."),
        Badge("forteresse", "Forteresse", "Une note de sécurité d’au moins 90."),
        Badge("defis_10", "Joueur régulier", "10 défis réussis."),
        Badge("binome", "Binôme de Claude", "5 décisions Claude Code prises depuis le téléphone."),
    )

    private fun earned(s: GameState): Set<String> = buildSet {
        if (s.xp > 0) add("premier_pas")
        if (s.allConnected) add("tout_connecte")
        if (s.bestStreak >= 3) add("serie_3")
        if (s.bestStreak >= 7) add("serie_7")
        if (s.level.level >= 5) add("niveau_5")
        if (s.freedTotal >= 1L shl 30) add("giga")
        if (s.bestSecurity >= 90) add("forteresse")
        if (s.challengesTotal >= 10) add("defis_10")
        if ((s.counters[GameEvent.CLAUDE_DECISION.name] ?: 0) >= 5) add("binome")
    }

    /** Un défi automatique est-il réussi avec l'état du jour ? */
    fun isDone(c: Challenge, s: GameState, today: LocalDate, sitesWatched: Boolean): Boolean = when (c.id) {
        "briefing" -> GameEvent.BRIEFING_READ.name in s.todayEvents
        "liberer" -> s.freedToday >= 500L * 1024 * 1024
        "zero_panne" -> sitesWatched && (s.lastOutageDay == null || LocalDate.parse(s.lastOutageDay) < today.minusDays(6))
        "ranger" -> GameEvent.PHONE_TIDIED.name in s.todayEvents
        "question" -> GameEvent.ASKED_OLI.name in s.todayEvents
        "securite" -> GameEvent.SECURITY_CHECK.name in s.todayEvents
        else -> c.id in s.challengesDone
    }

    /** Remet les compteurs du jour à zéro si la date a changé. */
    fun rollDay(s: GameState, today: LocalDate): GameState =
        if (s.day == today.toString()) s else s.copy(day = today.toString(), todayEvents = emptySet(), challengesDone = emptySet(), freedToday = 0)

    /**
     * Applique une action. `freed` : octets libérés ; `securityScore` : note d'audit ;
     * `manualChallenge` : défi coché à la main ; `sitesWatched` : pour « zéro panne ».
     */
    fun apply(
        state: GameState,
        today: LocalDate,
        event: GameEvent? = null,
        freed: Long = 0,
        securityScore: Int? = null,
        manualChallenge: String? = null,
        allConnected: Boolean? = null,
        outageToday: Boolean = false,
        sitesWatched: Boolean = false,
    ): GameUpdate {
        val before = rollDay(state, today)
        var s = before
        if (event != null) {
            s = s.copy(
                xp = s.xp + event.xp,
                todayEvents = s.todayEvents + event.name,
                counters = s.counters + (event.name to (s.counters[event.name] ?: 0) + 1),
            )
            if (event.countsForStreak) {
                val streak = nextStreak(s.lastStreakDay?.let(LocalDate::parse), s.streak, today)
                s = s.copy(streak = streak, bestStreak = maxOf(s.bestStreak, streak), lastStreakDay = today.toString())
            }
        }
        if (freed > 0) s = s.copy(freedToday = s.freedToday + freed, freedTotal = s.freedTotal + freed)
        if (securityScore != null) s = s.copy(bestSecurity = maxOf(s.bestSecurity, securityScore))
        if (allConnected != null) s = s.copy(allConnected = allConnected || s.allConnected)
        if (outageToday) s = s.copy(lastOutageDay = today.toString())
        if (manualChallenge != null && challengesFor(today).any { it.id == manualChallenge && it.manual }) {
            s = s.copy(challengesDone = s.challengesDone + manualChallenge)
        }

        // Défis du jour nouvellement réussis : +40 XP chacun.
        val newly = challengesFor(today).filter { c ->
            val key = "ok:" + c.id
            key !in s.todayEvents && isDone(c, s, today, sitesWatched)
        }
        for (c in newly) {
            s = s.copy(
                xp = s.xp + GameEvent.CHALLENGE_DONE.xp,
                todayEvents = s.todayEvents + ("ok:" + c.id),
                challengesTotal = s.challengesTotal + 1,
            )
        }
        val unlocked = earned(s) - s.badges
        s = s.copy(badges = s.badges + unlocked)
        return GameUpdate(s, badges.filter { it.id in unlocked }, newly, s.level.level > before.level.level)
    }

    fun challengeSucceeded(c: Challenge, s: GameState): Boolean = ("ok:" + c.id) in s.todayEvents

    /** Humeur d'Oli pour l'accueil. */
    fun mood(sitesDown: Int, claudeWaiting: Int, late: Int, streak: Int): String = when {
        sitesDown > 0 -> "Inquiet : un site ne répond plus"
        claudeWaiting > 0 -> "Impatient : Claude attend ton accord"
        late > 0 -> "Concentré : un projet a pris du retard"
        streak >= 3 -> "En pleine forme · série de $streak jours"
        else -> "Serein, tout roule"
    }
}
