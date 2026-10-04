package studio.oculot.oli.core

import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDate
import java.time.temporal.ChronoUnit

// Espace client Oculot : lecture de GET {base}/api/espace/summary (portage d'EspacePoller.swift).

data class EspaceProject(
    val id: String,
    val name: String,
    val kind: String,
    val dueAt: String?,
    val daysLeft: Long?,
    val currentStep: String?,
    val stepsDone: Int,
    val stepsTotal: Int,
    val liveUrl: String,
) {
    val isDone: Boolean get() = stepsTotal > 0 && stepsDone == stepsTotal
    val isLate: Boolean get() = !isDone && (daysLeft ?: 0) < 0

    val stepLabel: String get() = currentStep ?: if (isDone) "Terminé" else "Pas d’étape"

    val kindLabel: String
        get() = when (kind) {
            "refonte" -> "Refonte"
            "creation" -> "Création"
            else -> "Sur-mesure"
        }

    /** « J-3 », « aujourd’hui », « J+2 » (retard) ou « sans date ». */
    val daysLabel: String
        get() {
            val d = daysLeft ?: return "sans date"
            return when {
                d < 0 -> "J+${-d}"
                d == 0L -> "aujourd’hui"
                else -> "J-$d"
            }
        }
}

object Espace {
    const val DEFAULT_BASE_URL = "https://espace.oculot.studio"

    /** Base de l'API : adresse personnalisée si renseignée, sans « / » final. */
    fun baseUrl(custom: String?): String {
        val c = custom?.trim().orEmpty()
        val base = if (c.isEmpty()) DEFAULT_BASE_URL else Sites.normalize(c)
        return base.trimEnd('/')
    }

    fun summaryUrl(custom: String?): String = baseUrl(custom) + "/api/espace/summary"

    /**
     * Lit la réponse JSON `{ "clients": [...] }`. Les projets archivés sont ignorés.
     * Tri : échéance la plus proche d'abord, projets sans date à la fin.
     */
    fun parseSummary(json: String, today: LocalDate = LocalDate.now()): List<EspaceProject> {
        val root = JSONObject(json)
        val raw = root.optJSONArray("clients") ?: return emptyList()
        val out = ArrayList<EspaceProject>()
        for (i in 0 until raw.length()) {
            val d = raw.optJSONObject(i) ?: continue
            parseClient(d, today)?.let { out += it }
        }
        return out.sortedBy { it.daysLeft ?: Long.MAX_VALUE }
    }

    private fun parseClient(d: JSONObject, today: LocalDate): EspaceProject? {
        val id = d.optStringOrNull("id") ?: return null
        val name = d.optStringOrNull("name") ?: return null
        if (d.optBoolean("archived", false)) return null

        // Étape en cours : la première « doing », sinon la première « todo » (ordre du serveur).
        val steps: JSONArray = d.optJSONArray("steps") ?: JSONArray()
        var doing: String? = null
        var todo: String? = null
        var done = 0
        for (i in 0 until steps.length()) {
            val s = steps.optJSONObject(i) ?: continue
            when (s.optString("state")) {
                "doing" -> if (doing == null) doing = s.optStringOrNull("label")
                "todo" -> if (todo == null) todo = s.optStringOrNull("label")
                "done" -> done++
            }
        }

        val dueAt = d.optStringOrNull("dueAt")
        val daysLeft = dueAt?.takeIf { it.length >= 10 }?.let {
            try { ChronoUnit.DAYS.between(today, LocalDate.parse(it.substring(0, 10))) } catch (_: Exception) { null }
        }

        return EspaceProject(
            id = id,
            name = name,
            kind = d.optString("kind", ""),
            dueAt = dueAt,
            daysLeft = daysLeft,
            currentStep = doing ?: todo,
            stepsDone = done,
            stepsTotal = steps.length(),
            liveUrl = d.optString("liveUrl", ""),
        )
    }

    private fun JSONObject.optStringOrNull(key: String): String? =
        if (has(key) && !isNull(key)) optString(key).takeIf { it.isNotEmpty() } else null
}
