package studio.oculot.oli.core

import org.json.JSONObject
import java.net.URI
import java.net.URLDecoder

// Jumelage avec Oli sur le Mac (qui fait tourner Claude Code avec l'abonnement de l'utilisateur).
// Contrat : QR « oli://pair?host=<IP locale>&port=<port>&token=<jeton>&name=<nom %-encodé> »,
// puis GET /v1/status et POST /v1/chat sur http://<host>:<port>, en-tête « Authorization: Bearer <jeton> ».

data class MacPairing(val host: String, val port: Int, val token: String, val name: String) {
    val baseUrl: String get() = "http://${if (host.contains(':')) "[$host]" else host}:$port"
}

data class MacStatus(val name: String, val claude: Boolean, val model: String)

sealed interface ChatResult {
    data class Ok(val reply: String, val session: String?) : ChatResult
    data class Error(val message: String) : ChatResult
}

object MacLink {

    /** Lit le lien du QR code. Renvoie le jumelage, ou un message d'erreur lisible. */
    fun parsePairLink(raw: String): Result<MacPairing> {
        val text = raw.trim()
        val uri = try { URI(text) } catch (_: Exception) { return fail("Ce n’est pas un lien de jumelage Oli.") }
        if (!uri.scheme.equals("oli", ignoreCase = true)) return fail("Ce n’est pas un lien de jumelage Oli.")
        // « oli://pair?… » : selon l'analyse, « pair » est l'hôte ou le début du chemin.
        val target = (uri.rawAuthority ?: uri.rawSchemeSpecificPart?.removePrefix("//")?.substringBefore('?') ?: "")
        if (!target.equals("pair", ignoreCase = true)) return fail("Ce n’est pas un lien de jumelage Oli.")
        val query = uri.rawQuery ?: text.substringAfter('?', "")
        val params = query.split('&').filter { it.isNotEmpty() }.associate {
            val k = it.substringBefore('=')
            val v = it.substringAfter('=', "")
            decode(k) to decode(v)
        }
        val host = params["host"]?.trim().orEmpty()
        val port = params["port"]?.trim()?.toIntOrNull()
        val token = params["token"]?.trim().orEmpty()
        val name = params["name"]?.trim().orEmpty().ifEmpty { "ton Mac" }
        if (host.isEmpty() || token.isEmpty() || port == null || port !in 1..65535) {
            return fail("Le lien est incomplet : rescanne le QR code affiché sur ton Mac.")
        }
        if (!isLocalHost(host)) return fail("Pour ta sécurité, Oli ne se jumelle qu’avec un Mac du même réseau Wi-Fi.")
        return Result.success(MacPairing(host, port, token, name))
    }

    /** « %-encodage » sans transformer « + » en espace (les jetons peuvent en contenir). */
    private fun decode(s: String): String =
        try { URLDecoder.decode(s.replace("+", "%2B"), "UTF-8") } catch (_: Exception) { s }

    private fun fail(msg: String): Result<MacPairing> = Result.failure(IllegalArgumentException(msg))

    /**
     * Adresse du réseau local uniquement : IPv4 privées (10/8, 172.16/12, 192.168/16), lien local
     * (169.254/16), boucle locale, IPv6 locales (fe80::, fc00::/7) et noms « .local ».
     * C'est cette règle qui encadre le trafic en clair (voir res/xml/network_security_config.xml).
     */
    fun isLocalHost(host: String): Boolean {
        val h = host.trim().lowercase().removePrefix("[").removeSuffix("]")
        if (h.isEmpty()) return false
        if (h == "localhost" || h.endsWith(".local")) return true
        val parts = h.split('.')
        if (parts.size == 4 && parts.all { p -> p.toIntOrNull()?.let { it in 0..255 } == true && p.isNotEmpty() }) {
            val a = parts[0].toInt(); val b = parts[1].toInt()
            return a == 10 || a == 127 || (a == 172 && b in 16..31) || (a == 192 && b == 168) || (a == 169 && b == 254)
        }
        if (h.contains(':')) return h.startsWith("fe80:") || h.startsWith("fc") || h.startsWith("fd") || h == "::1"
        return false
    }

    fun chatBody(message: String, session: String?): String =
        JSONObject().put("message", message).put("session", session ?: JSONObject.NULL).toString()

    fun parseStatus(body: String): MacStatus? = try {
        val o = JSONObject(body)
        MacStatus(
            name = o.optString("name", "").ifBlank { "ton Mac" },
            claude = o.optBoolean("claude", false),
            model = o.optString("model", ""),
        )
    } catch (_: Exception) { null }

    /** Lit la réponse de POST /v1/chat. */
    fun parseChat(code: Int, body: String): ChatResult {
        val o = try { JSONObject(body) } catch (_: Exception) { null }
        if (code == 401 || code == 403) return ChatResult.Error("Le jumelage n’est plus valide : refais-le depuis Réglages → Connexions.")
        if (code != 200) {
            val err = o?.optString("error", "")?.takeIf { it.isNotBlank() }
            return ChatResult.Error(err ?: "Oli n’a pas pu répondre (code $code).")
        }
        if (o == null) return ChatResult.Error("Réponse illisible de ton Mac.")
        o.optString("error", "").takeIf { it.isNotBlank() }?.let { return ChatResult.Error(it) }
        val reply = o.optString("reply", "")
        if (reply.isBlank()) return ChatResult.Error("Oli n’a rien répondu, réessaie.")
        val session = if (o.has("session") && !o.isNull("session")) o.optString("session").ifBlank { null } else null
        return ChatResult.Ok(reply, session)
    }

    const val UNREACHABLE = "Ton Mac est injoignable : il doit être allumé, Oli lancé, et sur le même Wi-Fi."
}
