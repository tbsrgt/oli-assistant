package studio.oculot.oli.data

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import studio.oculot.oli.core.AgendaApi
import studio.oculot.oli.core.AgendaEvent
import studio.oculot.oli.core.AgendaLire
import studio.oculot.oli.core.ChatResult
import studio.oculot.oli.core.ClaudeBoard
import studio.oculot.oli.core.ClaudeCode
import studio.oculot.oli.core.Espace
import studio.oculot.oli.core.EspaceProject
import studio.oculot.oli.core.Ics
import studio.oculot.oli.core.MacLink
import studio.oculot.oli.core.MacPairing
import studio.oculot.oli.core.MacStatus
import studio.oculot.oli.core.ProbeResult
import studio.oculot.oli.core.SiteCheck
import studio.oculot.oli.core.Sites
import java.io.IOException
import java.net.SocketTimeoutException

/** Résultat d'une source : les données, ou un message d'erreur lisible. */
sealed interface Load<out T> {
    data object NotConfigured : Load<Nothing>
    data class Ok<T>(val value: T) : Load<T>
    data class Failed(val message: String) : Load<Nothing>
}

/** Un passage de surveillance : vérifications, pannes nouvelles, sites revenus. */
data class SiteRun(val checks: List<SiteCheck>, val outages: List<SiteCheck>, val recoveries: List<SiteCheck>)

/** Point d'entrée commun à l'écran et aux tâches de fond. */
class Repository(private val context: Context) {
    private val settingsStore by lazy { SettingsStore(context) }
    private val state by lazy { SiteStateStore(context) }

    fun settings(): Settings = settingsStore.load()
    fun saveSettings(s: Settings) = settingsStore.save(s)
    fun cachedChecks(): List<SiteCheck> = Sites.sorted(state.loadChecks().values.toList())
    fun espaceSites(): List<Pair<String, String>> = state.loadEspaceSites()

    /** Un passage sur tous les sites (4 à la fois). */
    suspend fun checkSites(): SiteRun = lock.withLock {
        withContext(Dispatchers.IO) {
            val s = settingsStore.load()
            // Les sites sous suivi sont vérifiés par le serveur (même téléphone en veille) : on lit leur état,
            // on ne sonde nous-mêmes que les autres.
            val server = state.loadChecks(SERVER_CHECKS).values.toList()
            val serverUrls = server.map { it.url }.toSet()
            val targets = Sites.targets(s.sites, state.loadEspaceSites()).filter { it.url !in serverUrls }
            val previous = state.loadChecks()
            val offline = !isOnline()
            val gate = Semaphore(4)
            val results = coroutineScope {
                targets.map { t ->
                    async { t to if (offline) ProbeResult(offline = true) else gate.withPermit { Net.probe(t.url) } }
                }.awaitAll()
            }
            val now = System.currentTimeMillis()
            val checks = results.map { (t, r) -> Sites.evaluate(previous[t.url], t, r, now) } + server
            state.saveChecks(checks)
            val before = state.loadNotified()
            val recovered = Sites.recoveries(checks, before)
            val (toNotify, notified) = Sites.outagesToNotify(checks, before)
            state.saveNotified(notified)
            SiteRun(Sites.sorted(checks), toNotify, recovered)
        }
    }

    suspend fun loadEspace(): Load<List<EspaceProject>> = withContext(Dispatchers.IO) {
        val s = settingsStore.load()
        if (s.espaceToken.isBlank()) return@withContext Load.NotConfigured
        try {
            val body = Net.getText(Espace.summaryUrl(s.espaceUrl), bearer = s.espaceToken, accept = "application/json")
            val projects = Espace.parseSummary(body)
            state.saveEspaceSites(projects.filter { it.liveUrl.isNotBlank() && it.suivi == null }.map { it.name to it.liveUrl })
            state.saveChecks(projects.mapNotNull { it.suivi }, SERVER_CHECKS)
            Load.Ok(projects)
        } catch (e: Net.HttpError) {
            Load.Failed(if (e.code == 401 || e.code == 403) "Le code d’équipe n’est plus accepté : reconnecte l’espace client."
                        else "L’espace client répond « HTTP ${e.code} ».")
        } catch (e: org.json.JSONException) {
            Load.Failed("Réponse de l’espace client illisible.")
        } catch (e: Exception) {
            Load.Failed("Impossible de joindre l’espace client.")
        }
    }

    /** Tous les rendez-vous des 14 prochains jours (l'écran n'en affiche qu'une partie). */
    suspend fun loadAgenda(): Load<List<AgendaEvent>> = withContext(Dispatchers.IO) {
        val s = settingsStore.load()
        if (s.icsUrl.isBlank()) return@withContext Load.NotConfigured
        try {
            val url = s.icsUrl.trim().replaceFirst(Regex("^webcals?://", RegexOption.IGNORE_CASE), "https://")
            Load.Ok(Ics.parse(Net.getText(url, accept = "text/calendar,*/*")))
        } catch (e: Net.HttpError) {
            Load.Failed("Le lien de l’agenda répond « HTTP ${e.code} ».")
        } catch (e: Exception) {
            Load.Failed("Impossible de lire l’agenda.")
        }
    }

    // Connexions : chaque vérification a lieu AVANT l'enregistrement.

    /** Vérifie le code d'équipe de l'espace client. null si tout va bien, sinon le message à afficher. */
    suspend fun verifyEspace(code: String): String? = withContext(Dispatchers.IO) {
        try {
            val r = Net.getReply(Espace.summaryUrl(settingsStore.load().espaceUrl),
                headers = mapOf("Authorization" to "Bearer ${code.trim()}"))
            when (r.code) {
                200 -> null
                401, 403 -> "Code refusé. Vérifie-le et réessaie."
                else -> "L’espace client répond « HTTP ${r.code} ». Réessaie dans un instant."
            }
        } catch (_: IOException) {
            "Impossible de joindre l’espace client. Vérifie ta connexion."
        }
    }

    suspend fun agendaLire(code: String): Result<AgendaLire> = withContext(Dispatchers.IO) {
        try {
            val r = Net.postJson(AgendaApi.RPC_URL, AgendaApi.lireBody(code.trim()),
                headers = mapOf("apikey" to AgendaApi.PUBLIC_KEY))
            AgendaApi.parseLire(r.code, r.body)
        } catch (_: IOException) {
            Result.failure(IllegalStateException("Impossible de joindre l’agenda. Vérifie ta connexion."))
        }
    }

    /** Obtient le lien iCal du membre, puis vérifie qu'il se lit bien. */
    suspend fun agendaLink(code: String, memberId: String): Result<String> = withContext(Dispatchers.IO) {
        try {
            val r = Net.postJson(AgendaApi.PUSH_URL, AgendaApi.lienIcsBody(code.trim(), memberId))
            val link = AgendaApi.parseLienIcs(r.code, r.body).getOrElse { return@withContext Result.failure(it) }
            verifyIcs(link)?.let { return@withContext Result.failure(IllegalStateException(it)) }
            Result.success(link)
        } catch (_: IOException) {
            Result.failure(IllegalStateException("Impossible de joindre l’agenda. Vérifie ta connexion."))
        }
    }

    /** Vérifie un lien iCal collé à la main. null si lisible. */
    suspend fun verifyIcs(link: String): String? = withContext(Dispatchers.IO) {
        try {
            val url = link.trim().replaceFirst(Regex("^webcals?://", RegexOption.IGNORE_CASE), "https://")
            val text = Net.getText(url, accept = "text/calendar,*/*")
            if (!text.contains("BEGIN:VCALENDAR", ignoreCase = true)) "Ce lien ne donne pas un agenda iCal." else null
        } catch (e: Net.HttpError) {
            "Le lien répond « HTTP ${e.code} »."
        } catch (_: Exception) {
            "Impossible de lire ce lien."
        }
    }

    suspend fun macStatus(p: MacPairing): Result<MacStatus> = withContext(Dispatchers.IO) {
        if (!MacLink.isLocalHost(p.host)) return@withContext Result.failure(IllegalStateException("Adresse du Mac non locale : refais le jumelage."))
        try {
            val r = Net.getReply(p.baseUrl + "/v1/status", headers = mapOf("Authorization" to "Bearer ${p.token}"),
                connectTimeoutMs = 5_000, readTimeoutMs = 10_000)
            when {
                r.code == 401 || r.code == 403 -> { lastRefusedAt = System.currentTimeMillis(); Result.failure(IllegalStateException("Ton Mac refuse ce jumelage : affiche un nouveau QR code et rescanne-le.")) }
                r.code != 200 -> Result.failure(IllegalStateException("Ton Mac répond « HTTP ${r.code} »."))
                else -> MacLink.parseStatus(r.body)?.let { Result.success(it) }
                    ?: Result.failure(IllegalStateException("Réponse illisible de ton Mac."))
            }
        } catch (_: IOException) {
            Result.failure(IllegalStateException(unreachable()))
        }
    }

    suspend fun macChat(message: String, session: String?): ChatResult = withContext(Dispatchers.IO) {
        val p = settingsStore.load().mac ?: return@withContext ChatResult.Error("Jumelle d’abord ton Mac : Réglages → Connexions → Claude.")
        // Trafic en clair : uniquement vers une adresse du réseau local.
        if (!MacLink.isLocalHost(p.host)) return@withContext ChatResult.Error("Adresse du Mac non locale : refais le jumelage.")
        try {
            val r = Net.postJson(p.baseUrl + "/v1/chat", MacLink.chatBody(message, session),
                headers = mapOf("Authorization" to "Bearer ${p.token}"),
                connectTimeoutMs = 6_000, readTimeoutMs = 120_000)
            MacLink.parseChat(r.code, r.body)
        } catch (e: SocketTimeoutException) {
            // Délai de connexion → Mac injoignable ; délai de lecture → Claude réfléchit trop longtemps.
            if (e.message?.contains("connect", ignoreCase = true) == true) ChatResult.Error(unreachable())
            else ChatResult.Error("Oli met trop de temps à répondre (plus de 2 min). Réessaie avec une question plus courte.")
        } catch (_: IOException) {
            ChatResult.Error(unreachable())
        }
    }

    /** Sessions Claude Code et demandes d'autorisation (GET /v1/claude/sessions). */
    suspend fun claudeBoard(quick: Boolean = false): Load<ClaudeBoard> = withContext(Dispatchers.IO) {
        val p = settingsStore.load().mac ?: return@withContext Load.NotConfigured
        if (!MacLink.isLocalHost(p.host)) return@withContext Load.Failed("Adresse du Mac non locale : refais le jumelage.")
        try {
            val r = Net.getReply(p.baseUrl + "/v1/claude/sessions", headers = mapOf("Authorization" to "Bearer ${p.token}"),
                connectTimeoutMs = if (quick) 3_000 else 5_000, readTimeoutMs = 10_000)
            when {
                r.code == 401 || r.code == 403 -> Load.Failed("Ton Mac refuse ce jumelage : refais-le depuis Connexions.")
                r.code == 404 -> Load.Failed("Oli sur ton Mac ne connaît pas encore Claude Code : mets-le à jour.")
                r.code != 200 -> Load.Failed("Ton Mac répond « HTTP ${r.code} ».")
                else -> ClaudeCode.parseBoard(r.body)?.let { Load.Ok(it) } ?: Load.Failed("Réponse illisible de ton Mac.")
            }
        } catch (_: IOException) {
            Load.Failed(unreachable())
        }
    }

    /** Autorise ou refuse une demande (POST /v1/claude/approvals/<id>). null si c'est fait, sinon le message. */
    suspend fun claudeDecide(id: String, allow: Boolean): String? = withContext(Dispatchers.IO) {
        val p = settingsStore.load().mac ?: return@withContext "Jumelle d’abord ton Mac."
        if (!MacLink.isLocalHost(p.host)) return@withContext "Adresse du Mac non locale : refais le jumelage."
        try {
            val r = Net.postJson(p.baseUrl + "/v1/claude/approvals/" + java.net.URLEncoder.encode(id, "UTF-8"),
                ClaudeCode.approvalBody(allow), headers = mapOf("Authorization" to "Bearer ${p.token}"),
                connectTimeoutMs = 5_000, readTimeoutMs = 15_000)
            if (ClaudeCode.parseApprovalReply(r.code, r.body)) null else ClaudeCode.approvalError(r.code, r.body)
        } catch (_: IOException) {
            unreachable()
        }
    }

    private fun isOnline(): Boolean {
        val cm = context.getSystemService(ConnectivityManager::class.java) ?: return true
        val caps = cm.getNetworkCapabilities(cm.activeNetwork) ?: return false
        return caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
    }

    companion object {
        /** État des sites sous suivi, lu dans l'espace client (vérifiés par le serveur). */
        private const val SERVER_CHECKS = "server_checks"

        /** Évite que l'écran et la tâche de fond comptent deux fois le même échec. */
        private val lock = Mutex()

        /** Dernier jumelage refusé : le Mac bloque l'adresse 5 min après 5 codes refusés. */
        @Volatile private var lastRefusedAt = 0L

        /** Erreur réseau : juste après un refus, c'est sans doute le blocage temporaire du Mac. */
        fun unreachable(): String =
            if (System.currentTimeMillis() - lastRefusedAt < 6 * 60_000L)
                "Ton Mac ne répond plus après plusieurs codes refusés : c'est une protection. Réessaie dans quelques minutes."
            else MacLink.UNREACHABLE
    }
}
