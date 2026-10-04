package studio.oculot.oli.data

import studio.oculot.oli.core.ProbeResult
import java.io.IOException
import java.net.ConnectException
import java.net.HttpURLConnection
import java.net.SocketTimeoutException
import java.net.URL
import java.net.UnknownHostException
import java.security.cert.CertificateExpiredException
import java.security.cert.X509Certificate
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLException
import javax.net.ssl.SSLHandshakeException

/** Accès réseau minimal (HttpURLConnection, aucune bibliothèque). À appeler hors du fil principal. */
object Net {
    private const val USER_AGENT = "Oli/1.0 (Oculot; Android)"
    private const val TIMEOUT_MS = 15_000

    /** Un GET avec redirections, 15 s maximum ; relève le code HTTP, la latence et l'expiration du certificat. */
    fun probe(urlString: String): ProbeResult {
        val url = try { URL(urlString) } catch (_: Exception) { return ProbeResult(error = "adresse invalide") }
        if (url.protocol != "http" && url.protocol != "https") return ProbeResult(error = "adresse invalide")
        val start = System.nanoTime()
        var conn: HttpURLConnection? = null
        return try {
            conn = (url.openConnection() as HttpURLConnection).apply {
                connectTimeout = TIMEOUT_MS
                readTimeout = TIMEOUT_MS
                instanceFollowRedirects = true
                useCaches = false
                setRequestProperty("User-Agent", USER_AGENT)
                setRequestProperty("Accept", "text/html,*/*;q=0.8")
            }
            val code = conn.responseCode
            var tls: Long? = null
            if (conn is HttpsURLConnection) {
                tls = runCatching { (conn.serverCertificates.firstOrNull() as? X509Certificate)?.notAfter?.time }.getOrNull()
            }
            ProbeResult(httpCode = code, latencyMs = (System.nanoTime() - start) / 1_000_000, tlsExpiresAtMs = tls)
        } catch (e: Exception) {
            ProbeResult(latencyMs = (System.nanoTime() - start) / 1_000_000, error = describe(e))
        } finally {
            conn?.disconnect()
        }
    }

    private fun describe(e: Exception): String = when {
        e is SocketTimeoutException -> "délai dépassé (15 s)"
        e is UnknownHostException -> "domaine introuvable"
        e is ConnectException -> "connexion refusée"
        e is SSLHandshakeException && e.hasCause<CertificateExpiredException>() -> "certificat expiré"
        e is SSLHandshakeException -> "certificat invalide"
        e is SSLException -> "échec de la connexion sécurisée"
        e is IOException -> "connexion perdue"
        else -> "erreur inattendue"
    }

    private inline fun <reified T : Throwable> Throwable.hasCause(): Boolean {
        var c: Throwable? = this
        while (c != null) { if (c is T) return true; c = c.cause }
        return false
    }

    class HttpError(val code: Int) : IOException("HTTP $code")

    /** GET texte (JSON, iCal). Lève HttpError si le code n'est pas 2xx. */
    fun getText(urlString: String, bearer: String? = null, accept: String = "*/*"): String {
        val conn = (URL(urlString).openConnection() as HttpURLConnection).apply {
            connectTimeout = TIMEOUT_MS
            readTimeout = TIMEOUT_MS
            instanceFollowRedirects = true
            setRequestProperty("User-Agent", USER_AGENT)
            setRequestProperty("Accept", accept)
            if (bearer != null) setRequestProperty("Authorization", "Bearer $bearer")
        }
        try {
            val code = conn.responseCode
            if (code !in 200..299) throw HttpError(code)
            return conn.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
        } finally {
            conn.disconnect()
        }
    }

    /** Réponse brute d'un appel : code HTTP et corps (même en cas d'erreur). */
    data class Reply(val code: Int, val body: String)

    /**
     * POST JSON. Ne lève pas d'exception sur un code ≠ 2xx (le corps d'erreur est renvoyé),
     * seulement sur un problème réseau (IOException).
     */
    fun postJson(
        urlString: String,
        json: String,
        headers: Map<String, String> = emptyMap(),
        connectTimeoutMs: Int = TIMEOUT_MS,
        readTimeoutMs: Int = TIMEOUT_MS,
    ): Reply = send("POST", urlString, json, headers, connectTimeoutMs, readTimeoutMs)

    /** GET qui renvoie le code et le corps sans lever d'exception sur un code ≠ 2xx. */
    fun getReply(
        urlString: String,
        headers: Map<String, String> = emptyMap(),
        connectTimeoutMs: Int = TIMEOUT_MS,
        readTimeoutMs: Int = TIMEOUT_MS,
    ): Reply = send("GET", urlString, null, headers, connectTimeoutMs, readTimeoutMs)

    private fun send(
        method: String, urlString: String, json: String?, headers: Map<String, String>,
        connectTimeoutMs: Int, readTimeoutMs: Int,
    ): Reply {
        val conn = (URL(urlString).openConnection() as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = connectTimeoutMs
            readTimeout = readTimeoutMs
            instanceFollowRedirects = true
            useCaches = false
            setRequestProperty("User-Agent", USER_AGENT)
            setRequestProperty("Accept", "application/json")
            headers.forEach { (k, v) -> setRequestProperty(k, v) }
            if (json != null) {
                doOutput = true
                setRequestProperty("Content-Type", "application/json; charset=utf-8")
            }
        }
        try {
            if (json != null) conn.outputStream.use { it.write(json.toByteArray(Charsets.UTF_8)) }
            val code = conn.responseCode
            val stream = if (code in 200..299) conn.inputStream else conn.errorStream
            val body = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }.orEmpty()
            return Reply(code, body)
        } finally {
            conn.disconnect()
        }
    }
}
