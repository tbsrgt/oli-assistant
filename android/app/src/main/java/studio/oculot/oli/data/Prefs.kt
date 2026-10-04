package studio.oculot.oli.data

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/** Interrupteurs des automatisations (toutes actives par défaut). Rien de secret. */
class AutomationPrefs(context: Context) {
    private val prefs = context.getSharedPreferences("oli_automatisations", Context.MODE_PRIVATE)

    enum class Key(val id: String, val title: String, val help: String) {
        BRIEFING("briefing", "Briefing du matin", "À 8 h 30 : tes rendez-vous du jour, les projets urgents et l’état des sites."),
        REMINDERS("rappels", "Rappels de rendez-vous", "10 min avant, avec « Rejoindre la visio » ou « Itinéraire »."),
        OUTAGES("pannes", "Pannes de site", "Une alerte quand un site tombe, une autre quand il revient."),
        DEADLINES("echeances", "Veille de mise en ligne", "La veille d’une mise en ligne d’un projet de l’espace client."),
        SHARE("partage", "Partage vers Oli", "Oli apparaît quand tu partages un fichier ou un lien."),
    }

    fun isOn(k: Key): Boolean = prefs.getBoolean(k.id, true)
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
