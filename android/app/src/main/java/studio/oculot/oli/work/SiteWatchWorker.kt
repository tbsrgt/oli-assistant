package studio.oculot.oli.work

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import studio.oculot.oli.MainActivity
import studio.oculot.oli.R
import studio.oculot.oli.core.SiteCheck
import studio.oculot.oli.data.Repository
import java.util.concurrent.TimeUnit

/** Toutes les 15 min : vérifie les sites et prévient une seule fois par panne. */
class SiteWatchWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        val repo = Repository(applicationContext)
        // Rafraîchit la liste des sites livrés de l'espace client (si un jeton est réglé), sans bloquer.
        runCatching { repo.loadEspace() }
        val (_, outages) = repo.checkSites()
        outages.forEach { notifyOutage(applicationContext, it) }
        return Result.success()
    }

    companion object {
        private const val WORK_NAME = "oli-surveillance-sites"
        const val CHANNEL_ID = "pannes"

        fun schedule(context: Context) {
            val request = PeriodicWorkRequestBuilder<SiteWatchWorker>(15, TimeUnit.MINUTES)
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .build()
            WorkManager.getInstance(context)
                .enqueueUniquePeriodicWork(WORK_NAME, ExistingPeriodicWorkPolicy.KEEP, request)
        }

        fun createChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val channel = NotificationChannel(CHANNEL_ID, "Sites en panne", NotificationManager.IMPORTANCE_HIGH)
                .apply { description = "Oli te prévient quand un site surveillé ne répond plus." }
            context.getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
        }

        fun notifyOutage(context: Context, site: SiteCheck) {
            if (Build.VERSION.SDK_INT >= 33 &&
                ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
            ) return
            val open = PendingIntent.getActivity(
                context, 0,
                Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            val n = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_notif_oli)
                .setColor(0xFFFF5B37.toInt())
                .setContentTitle("${site.name} est en panne")
                .setContentText(site.reason()?.let { "Raison : $it. Oli garde un œil dessus." } ?: "Oli garde un œil dessus.")
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setContentIntent(open)
                .setAutoCancel(true)
                .build()
            try {
                NotificationManagerCompat.from(context).notify(site.url.hashCode(), n)
            } catch (_: SecurityException) {
                // Permission retirée entre-temps : rien à faire.
            }
        }
    }
}
