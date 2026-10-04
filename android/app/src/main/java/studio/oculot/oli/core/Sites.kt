package studio.oculot.oli.core

import java.net.URI

// Surveillance des sites : modèle et règles pures (portage de SiteCheck.swift, sans dépendance Android).

enum class SiteStatus(val label: String, val order: Int) {
    OK("en ligne", 2),
    WARNING("à surveiller", 1),
    DOWN("en panne", 0),
    UNKNOWN("pas encore vérifié", 3),
}

data class SiteTarget(val name: String, val url: String)

/** Faits bruts d'une vérification, avant application des règles. */
data class ProbeResult(
    val httpCode: Int? = null,
    val latencyMs: Long = 0,
    val tlsExpiresAtMs: Long? = null,
    val error: String? = null,
    /** Le téléphone n'a pas de réseau : on ne le reproche pas au site. */
    val offline: Boolean = false,
) {
    /** Délai dépassé, erreur réseau ou code 5xx. */
    val isFailure: Boolean get() = error != null || (httpCode != null && httpCode >= 500)
}

data class SiteCheck(
    val name: String,
    val url: String,
    val status: SiteStatus = SiteStatus.UNKNOWN,
    val httpCode: Int? = null,
    val latencyMs: Long? = null,
    val tlsExpiresAtMs: Long? = null,
    val lastCheckedAtMs: Long? = null,
    val lastError: String? = null,
    val consecutiveFailures: Int = 0,
) {
    val shortHost: String get() = Sites.host(url)

    fun tlsDaysLeft(nowMs: Long): Long? =
        tlsExpiresAtMs?.let { Math.floorDiv(it - nowMs, 86_400_000L) }

    val latencyLabel: String
        get() {
            val ms = latencyMs ?: return "—"
            return if (ms >= 1000) String.format(java.util.Locale.FRANCE, "%.1f s", ms / 1000.0) else "$ms ms"
        }

    /** Pourquoi le site n'est pas simplement en ligne (null sinon). */
    fun reason(nowMs: Long = System.currentTimeMillis()): String? = when (status) {
        SiteStatus.OK, SiteStatus.UNKNOWN -> null
        SiteStatus.DOWN -> lastError ?: httpCode?.takeIf { it >= 500 }?.let { "HTTP $it" } ?: "injoignable"
        SiteStatus.WARNING -> {
            val c = httpCode
            val d = tlsDaysLeft(nowMs)
            when {
                c != null && c in 400..499 && c != 401 && c != 403 -> "HTTP $c"
                (latencyMs ?: 0) > Sites.SLOW_MS -> "lent · $latencyLabel"
                d != null && d < Sites.TLS_WARNING_DAYS ->
                    if (d < 0) "certificat expiré depuis ${-d} j"
                    else if (d == 0L) "certificat expire aujourd’hui"
                    else "certificat expire dans $d j"
                else -> lastError ?: "à surveiller"
            }
        }
    }
}

object Sites {
    const val TLS_WARNING_DAYS = 14
    const val SLOW_MS = 4000L

    /**
     * Applique les règles à une vérification en tenant compte de la précédente.
     * Un site passe « en panne » après 2 échecs de suite ; un échec isolé garde le statut précédent.
     */
    fun evaluate(previous: SiteCheck?, target: SiteTarget, result: ProbeResult, nowMs: Long): SiteCheck {
        val base = (previous ?: SiteCheck(target.name, target.url)).copy(name = target.name, url = target.url)
        if (result.offline) return base
        var c = base.copy(
            lastCheckedAtMs = nowMs,
            httpCode = result.httpCode,
            latencyMs = result.latencyMs,
            tlsExpiresAtMs = result.tlsExpiresAtMs ?: base.tlsExpiresAtMs,
        )
        if (result.isFailure) {
            val fails = c.consecutiveFailures + 1
            c = c.copy(
                consecutiveFailures = fails,
                lastError = result.error ?: result.httpCode?.let { "HTTP $it" },
                status = if (fails >= 2) SiteStatus.DOWN else c.status,
            )
            return c
        }
        val code = result.httpCode ?: 0
        val badCode = code in 400..499 && code != 401 && code != 403
        val slow = result.latencyMs > SLOW_MS
        val tlsSoon = c.tlsDaysLeft(nowMs)?.let { it < TLS_WARNING_DAYS } ?: false
        return c.copy(
            consecutiveFailures = 0,
            lastError = null,
            status = if (badCode || slow || tlsSoon) SiteStatus.WARNING else SiteStatus.OK,
        )
    }

    /**
     * Liste de surveillance : les sites en ligne de l'espace client (nom du client en libellé),
     * puis une URL par ligne saisie à la main. Lignes vides et « # » ignorées, doublons retirés.
     */
    fun targets(manual: String, espace: List<Pair<String, String>> = emptyList()): List<SiteTarget> {
        val seen = HashSet<String>()
        val out = ArrayList<SiteTarget>()
        for ((name, liveUrl) in espace) {
            val u = normalize(liveUrl)
            if (u.isEmpty() || !seen.add(u)) continue
            out += SiteTarget(name.ifBlank { host(u) }, u)
        }
        for (line in manual.lines()) {
            val raw = line.trim()
            if (raw.isEmpty() || raw.startsWith("#")) continue
            val u = normalize(raw)
            if (u.isEmpty() || !seen.add(u)) continue
            out += SiteTarget(host(u), u)
        }
        return out
    }

    /** Retire les espaces, ajoute https:// si le schéma manque. */
    fun normalize(raw: String): String {
        val s = raw.trim()
        if (s.isEmpty()) return ""
        val l = s.lowercase()
        return if (l.startsWith("http://") || l.startsWith("https://")) s else "https://$s"
    }

    /** « oculot.studio » pour « https://www.oculot.studio/fr/ ». */
    fun host(url: String): String {
        val h = try { URI(url).host } catch (_: Exception) { null } ?: return url
        return h.removePrefix("www.")
    }

    /**
     * Décide quelles pannes notifier : un site « en panne » qui n'a pas encore été signalé.
     * Renvoie les sites à notifier et le nouvel ensemble des pannes déjà signalées
     * (un site revenu en ligne en sort, pour qu'une prochaine panne soit signalée à nouveau).
     */
    fun outagesToNotify(checks: List<SiteCheck>, alreadyNotified: Set<String>): Pair<List<SiteCheck>, Set<String>> {
        val down = checks.filter { it.status == SiteStatus.DOWN }
        val fresh = down.filter { it.url !in alreadyNotified }
        val stillDown = down.map { it.url }.toSet()
        val keep = alreadyNotified.filter { url ->
            // On garde la mémoire tant que le site est en panne ; on l'oublie s'il est revenu
            // (statut OK / WARNING). Un site retiré de la liste est oublié aussi.
            url in stillDown
        }.toSet()
        return fresh to (keep + fresh.map { it.url })
    }

    /** Tri d'affichage : en panne d'abord, puis à surveiller, en ligne, pas vérifié. */
    fun sorted(checks: List<SiteCheck>): List<SiteCheck> =
        checks.sortedWith(compareBy<SiteCheck> { it.status.order }.thenBy { it.shortHost })
}
