package studio.oculot.oli.core

import org.json.JSONObject

// Claude Code sur le Mac, via le jumelage : GET /v1/claude/sessions, POST /v1/claude/approvals/<id>.

data class ClaudeSession(val id: String, val project: String, val state: String, val activity: String, val updatedAt: Long) {
    val stateLabel: String
        get() = when (state) {
            "working" -> "au travail"
            "waiting" -> "attend ton accord"
            "done" -> "a fini"
            else -> "en pause"
        }
}

data class ClaudeApproval(val id: String, val project: String, val tool: String, val summary: String, val detail: String)

data class ClaudeBoard(
    val sessions: List<ClaudeSession>,
    val approvals: List<ClaudeApproval>,
    /** false : le Mac n'accepte pas les réponses depuis le téléphone (option à activer sur le Mac). */
    val approvalsEnabled: Boolean = true,
) {
    val working: Int get() = sessions.count { it.state == "working" }
    /** Résumé court pour la pastille et le widget. */
    val shortLine: String
        get() = when {
            approvals.isNotEmpty() -> if (approvals.size == 1) "Claude attend ton accord" else "Claude attend ${approvals.size} accords"
            working > 0 -> if (working == 1) "Claude travaille" else "$working sessions Claude au travail"
            sessions.any { it.state == "done" } -> "Claude a fini"
            else -> "Claude au repos"
        }
}

/** Ce qui mérite une notification entre deux passages. */
data class ClaudeNews(val newApprovals: List<ClaudeApproval>, val finished: List<ClaudeSession>)

object ClaudeCode {
    fun parseBoard(body: String): ClaudeBoard? = try {
        val o = JSONObject(body)
        val sessions = ArrayList<ClaudeSession>()
        o.optJSONArray("sessions")?.let { a ->
            for (i in 0 until a.length()) {
                val s = a.optJSONObject(i) ?: continue
                val id = s.optString("id", "").ifBlank { null } ?: continue
                sessions += ClaudeSession(id, s.optString("project", "").ifBlank { "Projet" }, s.optString("state", "idle"),
                    s.optString("activity", ""), s.optLong("updatedAt", 0L))
            }
        }
        val approvals = ArrayList<ClaudeApproval>()
        o.optJSONArray("approvals")?.let { a ->
            for (i in 0 until a.length()) {
                val s = a.optJSONObject(i) ?: continue
                val id = s.optString("id", "").ifBlank { null } ?: continue
                approvals += ClaudeApproval(id, s.optString("project", "").ifBlank { "Projet" }, s.optString("tool", ""),
                    s.optString("summary", "").ifBlank { "Claude demande une autorisation" }, s.optString("detail", ""))
            }
        }
        ClaudeBoard(sessions.sortedWith(compareBy<ClaudeSession> { order(it.state) }.thenByDescending { it.updatedAt }), approvals,
            approvalsEnabled = o.optBoolean("approvalsEnabled", true))
    } catch (_: Exception) { null }

    private fun order(state: String) = when (state) { "waiting" -> 0; "working" -> 1; "done" -> 2; else -> 3 }

    fun approvalBody(allow: Boolean): String = JSONObject().put("allow", allow).toString()

    /** « {"ok": true} » attendu. */
    fun parseApprovalReply(code: Int, body: String): Boolean =
        code == 200 && (try { JSONObject(body).optBoolean("ok", false) } catch (_: Exception) { false })

    /** Message à afficher quand la décision n'est pas prise : le champ « error » du Mac tel quel (403, 410…). */
    fun approvalError(code: Int, body: String): String {
        val err = try { JSONObject(body).optString("error", "") } catch (_: Exception) { "" }
        if (err.isNotBlank()) return err
        return when (code) {
            403 -> "Les réponses depuis le téléphone sont désactivées sur le Mac."
            404, 410 -> "Cette demande n’attend plus de réponse."
            else -> "Ton Mac n’a pas pris la décision en compte (code $code)."
        }
    }

    /**
     * Nouvelles demandes d'autorisation (jamais vues) et sessions passées de « working » à « done ».
     * `previousStates` : id de session → état au passage précédent.
     */
    fun news(previousStates: Map<String, String>, seenApprovals: Set<String>, board: ClaudeBoard): ClaudeNews =
        ClaudeNews(
            newApprovals = board.approvals.filter { it.id !in seenApprovals },
            finished = board.sessions.filter { it.state == "done" && previousStates[it.id] == "working" },
        )

    /** Encodage des états pour la mémoire locale : « id=état » séparés par des retours à la ligne. */
    fun encodeStates(board: ClaudeBoard): String = board.sessions.joinToString("\n") { "${it.id}=${it.state}" }
    fun decodeStates(raw: String?): Map<String, String> =
        raw.orEmpty().lines().filter { '=' in it }.associate { it.substringBefore('=') to it.substringAfter('=') }
}
