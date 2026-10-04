package studio.oculot.oli.data

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import studio.oculot.oli.core.AgendaEvent
import studio.oculot.oli.core.Espace
import studio.oculot.oli.core.EspaceProject
import studio.oculot.oli.core.Ics
import studio.oculot.oli.core.ProbeResult
import studio.oculot.oli.core.SiteCheck
import studio.oculot.oli.core.Sites
import kotlinx.coroutines.coroutineScope

/** Résultat d'une source : les données, ou un message d'erreur lisible. */
sealed interface Load<out T> {
    data object NotConfigured : Load<Nothing>
    data class Ok<T>(val value: T) : Load<T>
    data class Failed(val message: String) : Load<Nothing>
}

/** Point d'entrée commun à l'écran et à la tâche de fond. */
class Repository(private val context: Context) {
    private val settingsStore by lazy { SettingsStore(context) }
    private val state by lazy { SiteStateStore(context) }

    fun settings(): Settings = settingsStore.load()
    fun saveSettings(s: Settings) = settingsStore.save(s)
    fun cachedChecks(): List<SiteCheck> = Sites.sorted(state.loadChecks().values.toList())

    /** Un passage sur tous les sites (4 à la fois). Renvoie les vérifications et les pannes à notifier. */
    suspend fun checkSites(): Pair<List<SiteCheck>, List<SiteCheck>> = lock.withLock {
        withContext(Dispatchers.IO) {
            val s = settingsStore.load()
            val targets = Sites.targets(s.sites, state.loadEspaceSites())
            val previous = state.loadChecks()
            val offline = !isOnline()
            val gate = Semaphore(4)
            val results = coroutineScope {
                targets.map { t ->
                    async { t to if (offline) ProbeResult(offline = true) else gate.withPermit { Net.probe(t.url) } }
                }.awaitAll()
            }
            val now = System.currentTimeMillis()
            val checks = results.map { (t, r) -> Sites.evaluate(previous[t.url], t, r, now) }
            state.saveChecks(checks)
            val (toNotify, notified) = Sites.outagesToNotify(checks, state.loadNotified())
            state.saveNotified(notified)
            Sites.sorted(checks) to toNotify
        }
    }

    suspend fun loadEspace(): Load<List<EspaceProject>> = withContext(Dispatchers.IO) {
        val s = settingsStore.load()
        if (s.espaceToken.isBlank()) return@withContext Load.NotConfigured
        try {
            val body = Net.getText(Espace.summaryUrl(s.espaceUrl), bearer = s.espaceToken, accept = "application/json")
            val projects = Espace.parseSummary(body)
            state.saveEspaceSites(projects.filter { it.liveUrl.isNotBlank() }.map { it.name to it.liveUrl })
            Load.Ok(projects)
        } catch (e: Net.HttpError) {
            Load.Failed(if (e.code == 401 || e.code == 403) "Le jeton n’est pas accepté : vérifie-le dans les réglages."
                        else "L’espace client répond « HTTP ${e.code} ».")
        } catch (e: org.json.JSONException) {
            Load.Failed("Réponse de l’espace client illisible.")
        } catch (e: Exception) {
            Load.Failed("Impossible de joindre l’espace client.")
        }
    }

    suspend fun loadAgenda(): Load<List<AgendaEvent>> = withContext(Dispatchers.IO) {
        val s = settingsStore.load()
        if (s.icsUrl.isBlank()) return@withContext Load.NotConfigured
        try {
            val url = s.icsUrl.trim().replaceFirst(Regex("^webcals?://", RegexOption.IGNORE_CASE), "https://")
            Load.Ok(Ics.parse(Net.getText(url, accept = "text/calendar,*/*")).take(8))
        } catch (e: Net.HttpError) {
            Load.Failed("Le lien de l’agenda répond « HTTP ${e.code} ».")
        } catch (e: Exception) {
            Load.Failed("Impossible de lire l’agenda.")
        }
    }

    private fun isOnline(): Boolean {
        val cm = context.getSystemService(ConnectivityManager::class.java) ?: return true
        val caps = cm.getNetworkCapabilities(cm.activeNetwork) ?: return false
        return caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
    }

    companion object {
        /** Évite que l'écran et la tâche de fond comptent deux fois le même échec. */
        private val lock = Mutex()
    }
}
