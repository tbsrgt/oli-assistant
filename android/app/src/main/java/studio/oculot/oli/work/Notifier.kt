package studio.oculot.oli.work

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import studio.oculot.oli.MainActivity
import studio.oculot.oli.R
import studio.oculot.oli.core.BriefingText
import studio.oculot.oli.core.EspaceProject
import studio.oculot.oli.core.SiteCheck

/** Toutes les notifications d'Oli. Aucune n'envoie quoi que ce soit : elles informent et ouvrent. */
object Notifier {
    const val CH_OUTAGES = "pannes"
    const val CH_BRIEFING = "briefing"
    const val CH_REMINDERS = "rappels"
    const val CH_DEADLINES = "echeances"

    private const val TOMATO = 0xFFFF5B37.toInt()

    fun createChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(NotificationManager::class.java) ?: return
        listOf(
            NotificationChannel(CH_OUTAGES, "Sites en panne", NotificationManager.IMPORTANCE_HIGH)
                .apply { description = "Oli te prévient quand un site surveillé ne répond plus, puis quand il revient." },
            NotificationChannel(CH_BRIEFING, "Briefing du matin", NotificationManager.IMPORTANCE_DEFAULT)
                .apply { description = "Le résumé de ta journée, à 8 h 30." },
            NotificationChannel(CH_REMINDERS, "Rappels de rendez-vous", NotificationManager.IMPORTANCE_HIGH)
                .apply { description = "10 minutes avant chaque rendez-vous." },
            NotificationChannel(CH_DEADLINES, "Mises en ligne", NotificationManager.IMPORTANCE_DEFAULT)
                .apply { description = "La veille d’une mise en ligne prévue dans l’espace client." },
        ).forEach { nm.createNotificationChannel(it) }
    }

    fun openApp(context: Context, requestCode: Int = 0): PendingIntent = PendingIntent.getActivity(
        context, requestCode,
        Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    private fun base(context: Context, channel: String, title: String, text: String) =
        NotificationCompat.Builder(context, channel)
            .setSmallIcon(R.drawable.ic_notif_oli)
            .setColor(TOMATO)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setContentIntent(openApp(context))
            .setAutoCancel(true)

    private fun post(context: Context, id: Int, n: Notification) {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return
        try {
            NotificationManagerCompat.from(context).notify(id, n)
        } catch (_: SecurityException) {
            // Permission retirée entre-temps : rien à faire.
        }
    }

    fun outage(context: Context, site: SiteCheck) = post(context, site.url.hashCode(),
        base(context, CH_OUTAGES, "${site.name} est en panne",
            site.reason()?.let { "Raison : $it. Oli garde un œil dessus." } ?: "Oli garde un œil dessus.")
            .setPriority(NotificationCompat.PRIORITY_HIGH).build())

    fun recovery(context: Context, site: SiteCheck) = post(context, site.url.hashCode(),
        base(context, CH_OUTAGES, "${site.name} est de nouveau en ligne", "Ouf, le site répond à nouveau. Tout est rentré dans l’ordre.")
            .build())

    fun briefing(context: Context, b: BriefingText) = post(context, 8_30,
        base(context, CH_BRIEFING, b.title, b.body).build())

    fun deadline(context: Context, p: EspaceProject) = post(context, ("echeance" + p.id).hashCode(),
        base(context, CH_DEADLINES, "Demain : mise en ligne de ${p.name}",
            "${p.kindLabel} · étape en cours : ${p.stepLabel}" +
                (if (p.stepsTotal > 0) " (${p.stepsDone}/${p.stepsTotal})" else "") + ". Tout est prêt ?")
            .build())

    /** Rappel de rendez-vous, avec « Rejoindre la visio » et/ou « Itinéraire » si possible. */
    fun reminder(context: Context, id: String, title: String, timeLabel: String, joinUrl: String?, address: String?) {
        val code = id.hashCode()
        val text = buildString {
            append("Dans 10 minutes, à $timeLabel.")
            if (address != null) append(" $address")
        }
        val b = base(context, CH_REMINDERS, title, text)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
        if (joinUrl != null) {
            val pi = PendingIntent.getActivity(context, code + 1,
                Intent(Intent.ACTION_VIEW, Uri.parse(joinUrl)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            b.addAction(0, "Rejoindre la visio", pi)
        }
        if (address != null) {
            val maps = Uri.parse("https://www.google.com/maps/dir/?api=1&destination=" + Uri.encode(address))
            val pi = PendingIntent.getActivity(context, code + 2,
                Intent(Intent.ACTION_VIEW, maps).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            b.addAction(0, "Itinéraire", pi)
        }
        post(context, code, b.build())
    }
}
