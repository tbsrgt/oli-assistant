package studio.oculot.oli.core

import java.time.LocalDate
import java.time.temporal.ChronoUnit

// Santé du téléphone : un audit de réglages, pas un antivirus. Règles pures, testables sur la JVM.

enum class Sensitivity(val label: String) {
    SMS("lit ou envoie des SMS"),
    ACCESSIBILITY("service d’accessibilité actif (peut lire l’écran)"),
    DEVICE_ADMIN("administrateur de l’appareil"),
    OVERLAY("peut s’afficher par-dessus les autres apps"),
    NOTIFICATIONS("lit toutes tes notifications"),
    BACKGROUND_LOCATION("localisation en arrière-plan"),
    INSTALL_APPS("peut installer d’autres apps"),
}

data class AppFact(val pkg: String, val label: String, val installer: String?, val sensitivities: Set<Sensitivity> = emptySet())

data class SecurityFacts(
    val screenLock: Boolean,
    val securityPatch: String?,          // Build.VERSION.SECURITY_PATCH, ex. « 2026-08-05 »
    val developerOptions: Boolean,
    val usbDebugging: Boolean,
    val apps: List<AppFact>,             // apps installées par l'utilisateur (pas les apps système)
)

enum class SettingsTarget { SECURITY, DEVELOPER, SYSTEM_UPDATE, APP_DETAILS, ACCESSIBILITY, NOTIFICATION_LISTENERS, UNKNOWN_SOURCES, OVERLAY }

data class Advice(val title: String, val detail: String, val points: Int, val target: SettingsTarget, val pkg: String? = null)

data class SecurityReport(val score: Int, val label: String, val advices: List<Advice>, val sideloaded: List<AppFact>, val sensitive: List<AppFact>)

object Security {
    /** Magasins d'apps reconnus (Play Store et magasins des constructeurs). */
    val trustedInstallers = setOf(
        "com.android.vending", "com.google.android.feedback", "com.sec.android.app.samsungapps",
        "com.huawei.appmarket", "com.xiaomi.market", "com.xiaomi.mipicks", "com.oppo.market", "com.heytap.market",
        "com.bbk.appstore", "com.amazon.venezia", "com.oneplus.store",
    )
    const val PATCH_MAX_DAYS = 90L

    fun patchAgeDays(patch: String?, today: LocalDate): Long? =
        try { patch?.takeIf { it.length >= 10 }?.let { ChronoUnit.DAYS.between(LocalDate.parse(it.take(10)), today) } } catch (_: Exception) { null }

    fun evaluate(f: SecurityFacts, today: LocalDate, ownPackage: String): SecurityReport {
        val advices = ArrayList<Advice>()
        if (!f.screenLock) advices += Advice("Active le verrouillage de l’écran",
            "Sans code, schéma ou empreinte, n’importe qui peut ouvrir ton téléphone (et tes mails clients).", 30, SettingsTarget.SECURITY)

        val age = patchAgeDays(f.securityPatch, today)
        when {
            age == null -> advices += Advice("Vérifie les mises à jour de sécurité",
                "Je n’arrive pas à lire la date du correctif de sécurité.", 5, SettingsTarget.SYSTEM_UPDATE)
            age > PATCH_MAX_DAYS -> advices += Advice("Mets à jour Android",
                "Le dernier correctif de sécurité date de ${age} jours (${f.securityPatch}). Au-delà de 90 jours, des failles connues restent ouvertes.",
                if (age > 180) 25 else 15, SettingsTarget.SYSTEM_UPDATE)
        }
        if (f.usbDebugging) advices += Advice("Coupe le débogage USB",
            "Utile pour développer, risqué au quotidien : un ordinateur branché peut accéder au téléphone.", 10, SettingsTarget.DEVELOPER)
        else if (f.developerOptions) advices += Advice("Désactive les options pour les développeurs",
            "Tu n’en as sans doute pas besoin au quotidien.", 5, SettingsTarget.DEVELOPER)

        val apps = f.apps.filter { it.pkg != ownPackage }
        val sideloaded = apps.filter { it.installer == null || it.installer !in trustedInstallers }
        sideloaded.take(5).forEach { a ->
            advices += Advice("${a.label} ne vient pas d’un magasin d’apps",
                "Installée ${a.installer?.let { "par $it" } ?: "à la main"}. Si tu ne la reconnais pas, désinstalle-la.", 3, SettingsTarget.APP_DETAILS, a.pkg)
        }
        val heavy = setOf(Sensitivity.ACCESSIBILITY, Sensitivity.DEVICE_ADMIN)
        var heavyLeft = 16
        var lightLeft = 10
        val sensitive = apps.filter { it.sensitivities.isNotEmpty() }
        for (a in sensitive) {
            val isHeavy = a.sensitivities.any { it in heavy }
            val pts = if (isHeavy) minOf(4, heavyLeft) else minOf(2, lightLeft)
            if (isHeavy) heavyLeft -= pts else lightLeft -= pts
            val target = when {
                Sensitivity.ACCESSIBILITY in a.sensitivities -> SettingsTarget.ACCESSIBILITY
                Sensitivity.DEVICE_ADMIN in a.sensitivities -> SettingsTarget.SECURITY
                Sensitivity.NOTIFICATIONS in a.sensitivities -> SettingsTarget.NOTIFICATION_LISTENERS
                Sensitivity.INSTALL_APPS in a.sensitivities -> SettingsTarget.UNKNOWN_SOURCES
                Sensitivity.OVERLAY in a.sensitivities -> SettingsTarget.OVERLAY
                else -> SettingsTarget.APP_DETAILS
            }
            advices += Advice("${a.label} a des accès sensibles",
                a.sensitivities.joinToString(", ") { it.label }.replaceFirstChar { it.uppercase() } + ". Garde-les seulement si tu fais confiance à l’app.",
                pts, target, a.pkg)
        }
        val lost = advices.sumOf { it.points }.coerceAtMost(100)
        val score = (100 - lost).coerceIn(0, 100)
        val label = when {
            score >= 90 -> "Excellent"
            score >= 75 -> "Bon"
            score >= 55 -> "À améliorer"
            else -> "Fragile"
        }
        return SecurityReport(score, label, advices.sortedByDescending { it.points }, sideloaded, sensitive)
    }
}
