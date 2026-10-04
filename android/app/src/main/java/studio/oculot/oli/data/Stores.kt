package studio.oculot.oli.data

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import org.json.JSONArray
import org.json.JSONObject
import studio.oculot.oli.core.SiteCheck
import studio.oculot.oli.core.SiteStatus

/** Réglages saisis par l'équipe. Chiffrés (clé AES dans l'Android Keystore). */
data class Settings(
    val espaceToken: String = "",
    val espaceUrl: String = "",
    val sites: String = "",
    val icsUrl: String = "",
    // Agenda Oculot : mot de passe de l'agenda et membre choisi (le lien iCal en découle).
    val agendaCode: String = "",
    val agendaMemberId: String = "",
    val agendaMemberName: String = "",
    // Jumelage avec Oli sur le Mac (Claude).
    val macHost: String = "",
    val macPort: Int = 0,
    val macToken: String = "",
    val macName: String = "",
) {
    val mac: studio.oculot.oli.core.MacPairing?
        get() = if (macHost.isNotBlank() && macToken.isNotBlank() && macPort > 0)
            studio.oculot.oli.core.MacPairing(macHost, macPort, macToken, macName.ifBlank { "ton Mac" }) else null
}

class SettingsStore(context: Context) {
    private val prefs: SharedPreferences = run {
        val key = MasterKey.Builder(context).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build()
        EncryptedSharedPreferences.create(
            context, "oli_reglages", key,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    fun load() = Settings(
        espaceToken = prefs.getString("espace_token", "").orEmpty(),
        espaceUrl = prefs.getString("espace_url", "").orEmpty(),
        sites = prefs.getString("sites", "").orEmpty(),
        icsUrl = prefs.getString("ics_url", "").orEmpty(),
        agendaCode = prefs.getString("agenda_code", "").orEmpty(),
        agendaMemberId = prefs.getString("agenda_membre", "").orEmpty(),
        agendaMemberName = prefs.getString("agenda_nom", "").orEmpty(),
        macHost = prefs.getString("mac_host", "").orEmpty(),
        macPort = prefs.getInt("mac_port", 0),
        macToken = prefs.getString("mac_token", "").orEmpty(),
        macName = prefs.getString("mac_name", "").orEmpty(),
    )

    fun save(s: Settings) {
        prefs.edit()
            .putString("espace_token", s.espaceToken.trim())
            .putString("espace_url", s.espaceUrl.trim())
            .putString("sites", s.sites.trim())
            .putString("ics_url", s.icsUrl.trim())
            .putString("agenda_code", s.agendaCode)
            .putString("agenda_membre", s.agendaMemberId)
            .putString("agenda_nom", s.agendaMemberName)
            .putString("mac_host", s.macHost.trim())
            .putInt("mac_port", s.macPort)
            .putString("mac_token", s.macToken.trim())
            .putString("mac_name", s.macName)
            .apply()
    }
}

/** État des sites entre deux passages (statuts, échecs de suite, pannes déjà signalées). Rien de secret. */
class SiteStateStore(context: Context) {
    private val prefs = context.getSharedPreferences("oli_etat_sites", Context.MODE_PRIVATE)

    fun loadChecks(key: String = "checks"): Map<String, SiteCheck> {
        val raw = prefs.getString(key, null) ?: return emptyMap()
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).associate { i ->
                val o = arr.getJSONObject(i)
                val c = SiteCheck(
                    name = o.getString("name"),
                    url = o.getString("url"),
                    status = runCatching { SiteStatus.valueOf(o.getString("status")) }.getOrDefault(SiteStatus.UNKNOWN),
                    httpCode = o.optIntOrNull("httpCode"),
                    latencyMs = o.optLongOrNull("latencyMs"),
                    tlsExpiresAtMs = o.optLongOrNull("tls"),
                    lastCheckedAtMs = o.optLongOrNull("checkedAt"),
                    lastError = if (o.has("error")) o.getString("error") else null,
                    consecutiveFailures = o.optInt("fails", 0),
                )
                c.url to c
            }
        } catch (_: Exception) {
            emptyMap()
        }
    }

    fun saveChecks(checks: List<SiteCheck>, key: String = "checks") {
        val arr = JSONArray()
        for (c in checks) {
            arr.put(JSONObject().apply {
                put("name", c.name); put("url", c.url); put("status", c.status.name)
                c.httpCode?.let { put("httpCode", it) }
                c.latencyMs?.let { put("latencyMs", it) }
                c.tlsExpiresAtMs?.let { put("tls", it) }
                c.lastCheckedAtMs?.let { put("checkedAt", it) }
                c.lastError?.let { put("error", it) }
                put("fails", c.consecutiveFailures)
            })
        }
        prefs.edit().putString(key, arr.toString()).apply()
    }

    fun loadNotified(): Set<String> = prefs.getStringSet("notified", emptySet())?.toSet() ?: emptySet()
    fun saveNotified(urls: Set<String>) { prefs.edit().putStringSet("notified", urls).apply() }

    /** Sites en ligne de l'espace client, gardés pour la surveillance en arrière-plan. */
    fun loadEspaceSites(): List<Pair<String, String>> {
        val raw = prefs.getString("espace_sites", null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).map { arr.getJSONObject(it).let { o -> o.getString("n") to o.getString("u") } }
        } catch (_: Exception) { emptyList() }
    }

    fun saveEspaceSites(list: List<Pair<String, String>>) {
        val arr = JSONArray()
        list.forEach { (n, u) -> arr.put(JSONObject().put("n", n).put("u", u)) }
        prefs.edit().putString("espace_sites", arr.toString()).apply()
    }

    private fun JSONObject.optIntOrNull(k: String): Int? = if (has(k)) getInt(k) else null
    private fun JSONObject.optLongOrNull(k: String): Long? = if (has(k)) getLong(k) else null
}
