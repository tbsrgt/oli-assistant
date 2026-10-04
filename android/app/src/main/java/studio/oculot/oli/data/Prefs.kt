package studio.oculot.oli.data

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/** Interrupteurs des automatisations (toutes actives par défaut). Rien de secret. */
class AutomationPrefs(context: Context) {
    private val prefs = context.getSharedPreferences("oli_automatisations", Context.MODE_PRIVATE)

    enum class Key(val id: String, val title: String, val help: String, val defaultOn: Boolean = true) {
        BRIEFING("briefing", "Briefing du matin", "À 8 h 30 : tes rendez-vous du jour, les projets urgents et l’état des sites."),
        REMINDERS("rappels", "Rappels de rendez-vous", "10 min avant, avec « Rejoindre la visio » ou « Itinéraire »."),
        OUTAGES("pannes", "Pannes de site", "Une alerte quand un site tombe, une autre quand il revient."),
        DEADLINES("echeances", "Veille de mise en ligne", "La veille d’une mise en ligne d’un projet de l’espace client."),
        SHARE("partage", "Partage vers Oli", "Oli apparaît quand tu partages un fichier ou un lien."),
        CLAUDE("claude", "Claude Code", "« Claude attend ton accord » et « Claude a fini », si ton Mac est joignable."),
        EVENING("soir", "Mode avion du soir", "Un rappel à 22 h pour couper le téléphone. Android ne laisse pas une app activer le mode avion elle-même.", defaultOn = false),
        FLOATING("flottant", "Oli flottant", "Une pastille en haut de l’écran, par-dessus les autres apps.", defaultOn = false),
    }

    fun isOn(k: Key): Boolean = prefs.getBoolean(k.id, k.defaultOn)
    fun set(k: Key, on: Boolean) { prefs.edit().putBoolean(k.id, on).apply() }
}

/** Petites mémoires des automatisations et instantané pour le widget. Rien de secret. */
class MemoryStore(context: Context) {
    private val prefs = context.getSharedPreferences("oli_memoire", Context.MODE_PRIVATE)

    fun deadlinesNotified(): Set<String> = prefs.getStringSet("echeances", emptySet())?.toSet() ?: emptySet()
    fun saveDeadlinesNotified(s: Set<String>) { prefs.edit().putStringSet("echeances", s).apply() }

    /** Codes des alarmes de rappel programmées (pour annuler celles qui n'ont plus lieu d'être). */
    fun reminderCodes(): Set<String> = prefs.getStringSet("rappels", emptySet())?.toSet() ?: emptySet()
    fun saveReminderCodes(s: Set<String>) { prefs.edit().putStringSet("rappels", s).apply() }

    // Claude Code : états des sessions et demandes déjà signalées, résumé pour la pastille et l'accueil.
    fun claudeStates(): String? = prefs.getString("claude_etats", null)
    fun claudeSeenApprovals(): Set<String> = prefs.getStringSet("claude_vus", emptySet())?.toSet() ?: emptySet()
    fun saveClaude(states: String, seen: Set<String>, line: String, waiting: Int) {
        prefs.edit().putString("claude_etats", states).putStringSet("claude_vus", seen)
            .putString("claude_ligne", line).putInt("claude_attente", waiting).apply()
    }
    fun claudeLine(): String? = prefs.getString("claude_ligne", null)
    fun claudeWaiting(): Int = prefs.getInt("claude_attente", 0)

    /** Dernière note de l'audit de sécurité (−1 si jamais fait). */
    fun securityScore(): Int = prefs.getInt("note_securite", -1)
    fun saveSecurityScore(n: Int) { prefs.edit().putInt("note_securite", n).apply() }

    fun lastBriefingDay(): String? = prefs.getString("dernier_briefing", null)
    fun saveLastBriefingDay(day: String) { prefs.edit().putString("dernier_briefing", day).apply() }

    /** Prochain rendez-vous pour le widget : titre et début (ms), ou rien. */
    fun nextEvent(): Pair<String, Long>? {
        val t = prefs.getString("prochain_titre", null) ?: return null
        val at = prefs.getLong("prochain_debut", 0L)
        return if (at > 0) t to at else null
    }

    fun saveNextEvent(title: String?, startMs: Long?) {
        val e = prefs.edit()
        if (title == null || startMs == null) e.remove("prochain_titre").remove("prochain_debut")
        else e.putString("prochain_titre", title).putLong("prochain_debut", startMs)
        e.apply()
    }
}

/** Un message de la conversation « Demander à Oli ». */
data class ChatMessage(val fromMe: Boolean, val text: String, val isError: Boolean = false)

/** Conversation et session, gardées sur le téléphone (stockage privé de l'app). */
class ChatStore(context: Context) {
    private val prefs = context.getSharedPreferences("oli_conversation", Context.MODE_PRIVATE)

    fun session(): String? = prefs.getString("session", null)

    fun messages(): List<ChatMessage> = try {
        val arr = JSONArray(prefs.getString("messages", "[]"))
        (0 until arr.length()).map { i ->
            arr.getJSONObject(i).let { ChatMessage(it.getBoolean("moi"), it.getString("t"), it.optBoolean("err", false)) }
        }
    } catch (_: Exception) { emptyList() }

    fun save(messages: List<ChatMessage>, session: String?) {
        val arr = JSONArray()
        messages.takeLast(80).forEach { arr.put(JSONObject().put("moi", it.fromMe).put("t", it.text).put("err", it.isError)) }
        val e = prefs.edit().putString("messages", arr.toString())
        if (session == null) e.remove("session") else e.putString("session", session)
        e.apply()
    }

    fun clear() { prefs.edit().clear().apply() }
}
