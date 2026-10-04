package studio.oculot.oli.work

import android.content.Context
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import studio.oculot.oli.data.Repository
import java.util.concurrent.TimeUnit

/**
 * Toutes les 15 min : vérifie les sites (une alerte par panne, une au retour), relit l'espace client
 * (veille de mise en ligne) et l'agenda (rappels 10 min avant), puis met le widget à jour.
 */
class SiteWatchWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        val repo = Repository(applicationContext)
        val espace = runCatching { repo.loadEspace() }.getOrNull()
        val agenda = runCatching { repo.loadAgenda() }.getOrNull()
        val run = repo.checkSites()
        Automator.afterRefresh(applicationContext, espace, agenda, run)
        if (Repository(applicationContext).settings().mac != null) runCatching { Automator.claudeCheck(applicationContext) }
        return Result.success()
    }

    companion object {
        private const val WORK_NAME = "oli-surveillance-sites"

        fun schedule(context: Context) {
            val request = PeriodicWorkRequestBuilder<SiteWatchWorker>(15, TimeUnit.MINUTES)
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .build()
            WorkManager.getInstance(context)
                .enqueueUniquePeriodicWork(WORK_NAME, ExistingPeriodicWorkPolicy.KEEP, request)
        }
    }
}
