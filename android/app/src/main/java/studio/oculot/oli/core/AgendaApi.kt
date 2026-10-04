package studio.oculot.oli.core

import org.json.JSONObject
import java.text.Normalizer

// Agenda Oculot (agenda.oculot.studio) : API lue dans https://agenda.oculot.studio/app.js.
// 1) RPC Supabase « oculot_agenda_api » action « lire » → équipe, « moi », rendez-vous.
// 2) POST /api/push {type: "lien_ics"} → lien iCal personnel du membre.

data class AgendaMember(val id: String, val name: String, val role: String, val color: String)

data class AgendaLire(val team: List<AgendaMember>, val myRole: String, val myMemberId: String?)

/** Qui est l'utilisateur : déjà connu (closer), ou à choisir parmi des prénoms. */
sealed interface MemberChoice {
    data class Fixed(val member: AgendaMember) : MemberChoice
    data class Pick(val candidates: List<AgendaMember>, val preselected: String?) : MemberChoice
}

object AgendaApi {
    const val RPC_URL = "https://skyqbuunpwvzvabxhjug.supabase.co/rest/v1/rpc/oculot_agenda_api"
    /** Clé publique (« publishable ») : elle figure dans le JavaScript du site, ce n'est pas un secret. */
    const val PUBLIC_KEY = "sb_publishable_U6EQgiXNfeuQ6pp9zjH4ew_sG4AOJRQ"
    const val PUSH_URL = "https://agenda.oculot.studio/api/push"

    fun lireBody(code: String): String =
        JSONObject().put("p_code", code).put("p_action", "lire").put("p_args", JSONObject()).toString()

    fun lienIcsBody(code: String, memberId: String): String =
        JSONObject().put("type", "lien_ics").put("code", code).put("membre", memberId).toString()

    /** Lit la réponse de « lire ». Échec avec un message lisible si l'agenda renvoie `erreur`. */
    fun parseLire(code: Int, body: String): Result<AgendaLire> {
        val o = try { JSONObject(body) } catch (_: Exception) { null }
        val err = o?.let { it.optString("erreur", "").ifBlank { null } }
        if (err != null) return fail(explain(err))
        if (code !in 200..299 || o == null) {
            return fail(if (code == 401 || code == 403) "L’agenda refuse la connexion pour l’instant." else "L’agenda ne répond pas comme prévu (code $code).")
        }
        val team = ArrayList<AgendaMember>()
        val arr = o.optJSONArray("equipe")
        if (arr != null) for (i in 0 until arr.length()) {
            val m = arr.optJSONObject(i) ?: continue
            val id = m.opt("id")?.takeIf { it != JSONObject.NULL }?.toString()?.ifBlank { null } ?: continue
            team += AgendaMember(id, m.optString("nom", "").ifBlank { "Sans nom" }, m.optString("role", ""), m.optString("couleur", ""))
        }
        val moi = o.optJSONObject("moi")
        val role = moi?.optString("role", "").orEmpty()
        val membre = moi?.opt("membre")?.let { v ->
            when (v) {
                JSONObject.NULL -> null
                is JSONObject -> v.opt("id")?.toString()
                else -> v.toString()
            }
        }?.ifBlank { null }
        return Result.success(AgendaLire(team, role, membre))
    }

    private fun explain(err: String): String {
        val e = err.lowercase()
        return if (listOf("code", "mot de passe", "acc", "invalide", "refus", "incorrect").any { it in e })
            "Ce mot de passe n’est pas le bon. Vérifie-le et réessaie."
        else "L’agenda répond : $err"
    }

    /**
     * Choix du membre : un « closer » est reconnu directement ; sinon on propose les membres
     * dont le rôle n'est pas « closer », en présélectionnant celui qui ressemble au prénom saisi.
     */
    fun chooseMember(lire: AgendaLire, typedName: String? = null): MemberChoice {
        if (lire.myRole == "closer" && lire.myMemberId != null) {
            val m = lire.team.firstOrNull { it.id == lire.myMemberId } ?: AgendaMember(lire.myMemberId, "Moi", "closer", "")
            return MemberChoice.Fixed(m)
        }
        val candidates = lire.team.filter { it.role != "closer" }
        val pre = guess(candidates, typedName) ?: candidates.singleOrNull()?.id
        return MemberChoice.Pick(candidates, pre)
    }

    /** Prénom le plus proche : égalité sans accents ni casse, sinon début commun (≥ 3 lettres). */
    fun guess(candidates: List<AgendaMember>, typed: String?): String? {
        val t = norm(typed ?: return null)
        if (t.isEmpty()) return null
        candidates.firstOrNull { norm(it.name) == t }?.let { return it.id }
        candidates.firstOrNull { norm(it.name).substringBefore(' ') == t.substringBefore(' ') }?.let { return it.id }
        if (t.length >= 3) candidates.firstOrNull { norm(it.name).startsWith(t) || t.startsWith(norm(it.name)) }?.let { return it.id }
        return null
    }

    private fun norm(s: String): String =
        Normalizer.normalize(s.trim().lowercase(), Normalizer.Form.NFD).replace(Regex("\\p{M}+"), "")

    /** Lit la réponse de /api/push (lien_ics) : le lien iCal https. */
    fun parseLienIcs(code: Int, body: String): Result<String> {
        val o = try { JSONObject(body) } catch (_: Exception) { null }
        val err = o?.let { it.optString("erreur", "").ifBlank { it.optString("error", "") }.ifBlank { null } }
        if (err != null) return Result.failure(IllegalStateException(explain(err)))
        if (code !in 200..299 || o == null) return Result.failure(IllegalStateException("Impossible d’obtenir le lien de ton agenda (code $code)."))
        val url = o.optString("url", "").trim()
        if (url.startsWith("https://", ignoreCase = true)) return Result.success(url)
        val webcal = o.optString("webcal", "").trim()
        if (webcal.startsWith("webcal://", ignoreCase = true)) return Result.success("https://" + webcal.substring(9))
        return Result.failure(IllegalStateException("L’agenda n’a pas donné de lien iCal."))
    }

    private fun fail(msg: String): Result<AgendaLire> = Result.failure(IllegalStateException(msg))
}
