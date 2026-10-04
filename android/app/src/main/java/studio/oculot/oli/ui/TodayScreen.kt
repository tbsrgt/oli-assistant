package studio.oculot.oli.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Face
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import studio.oculot.oli.core.AgendaEvent
import studio.oculot.oli.core.EspaceProject
import studio.oculot.oli.core.SiteCheck
import studio.oculot.oli.core.SiteStatus
import studio.oculot.oli.data.Load
import java.time.LocalDate
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.util.Locale

data class TodayState(
    val loading: Boolean = false,
    val sites: List<SiteCheck> = emptyList(),
    val sitesConfigured: Boolean = false,
    val espace: Load<List<EspaceProject>>? = null,
    val agenda: Load<List<AgendaEvent>>? = null,
)

/** Écran de détail d'une tuile : Sites, Projets ou Agenda. */
@Composable
fun DetailScreen(kind: String, state: TodayState, onBack: () -> Unit, onRefresh: () -> Unit, onSettings: () -> Unit) {
    Column(
        Modifier
            .fillMaxSize()
            .background(Oc.Bg)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.weight(1f)) {
                ScreenHeader(when (kind) { "sites" -> "Sites"; "projets" -> "Projets"; else -> "Agenda" }, onBack)
            }
            if (state.loading) CircularProgressIndicator(Modifier.size(20.dp), color = Oc.Butter, strokeWidth = 2.dp)
            else IconButton(onClick = onRefresh) { Icon(Icons.Filled.Refresh, "Actualiser", tint = Oc.Text) }
        }
        Spacer(Modifier.height(8.dp))
        when (kind) {
            "sites" -> Section("Surveillés toutes les 15 min") { SitesBlock(state, onSettings) }
            "projets" -> Section("Espace client") { EspaceBlock(state.espace, onSettings) }
            else -> Section("Les deux prochaines semaines") { AgendaBlock(state.agenda, onSettings, limit = 30) }
        }
    }
}

internal fun greeting(): String {
    val h = LocalTime.now().hour
    return when {
        h < 5 -> "Encore debout ?"
        h < 12 -> "Bonjour !"
        h < 18 -> "Bon après-midi !"
        else -> "Bonsoir !"
    }
}

internal fun summary(state: TodayState, down: Int, late: Int): String = when {
    down == 1 -> "Un site est en panne, je t’ai mis le détail juste en dessous."
    down > 1 -> "$down sites sont en panne, regarde vite en dessous."
    late == 1 -> "Tous les sites tiennent le coup. Un projet a pris du retard."
    late > 1 -> "Tous les sites tiennent le coup. $late projets ont pris du retard."
    state.sites.isNotEmpty() && state.sites.all { it.status == SiteStatus.OK } -> "Tout roule : les sites répondent bien."
    else -> "Voici l’essentiel de ta journée."
}

@Composable
private fun Section(title: String, content: @Composable () -> Unit) {
    Text(title.uppercase(), color = Oc.Muted, fontSize = 12.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.5.sp)
    Spacer(Modifier.height(8.dp))
    Surface(
        color = Oc.Card,
        shape = RoundedCornerShape(18.dp),
        border = BorderStroke(1.dp, Oc.CardBorder),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(vertical = 6.dp)) { content() }
    }
    Spacer(Modifier.height(20.dp))
}

@Composable
private fun Hint(text: String, action: String? = null, onAction: (() -> Unit)? = null) {
    Column(Modifier.padding(horizontal = 16.dp, vertical = 10.dp)) {
        Text(text, color = Oc.Muted, fontSize = 14.sp)
        if (action != null && onAction != null) {
            TextButton(onClick = onAction, contentPadding = androidx.compose.foundation.layout.PaddingValues(0.dp)) {
                Text(action, color = Oc.Tomato, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

@Composable
private fun Row3(dot: Color, title: String, subtitle: String, trailing: String, trailingColor: Color = Oc.Muted, subtitleColor: Color = Oc.Muted) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(10.dp).background(dot, CircleShape))
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(title, color = Oc.Text, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (subtitle.isNotEmpty()) Text(subtitle, color = subtitleColor, fontSize = 13.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
        Spacer(Modifier.width(8.dp))
        Text(trailing, color = trailingColor, fontSize = 13.sp, fontWeight = FontWeight.Medium)
    }
}

private fun statusColor(s: SiteStatus) = when (s) {
    SiteStatus.OK -> Oc.Ok
    SiteStatus.WARNING -> Oc.Butter
    SiteStatus.DOWN -> Oc.Down
    SiteStatus.UNKNOWN -> Oc.Unknown
}

@Composable
private fun SitesBlock(state: TodayState, onSettings: () -> Unit) {
    if (!state.sitesConfigured && state.sites.isEmpty()) {
        Hint("Donne-moi les adresses de tes sites, je les surveille toutes les 15 minutes.", "Ajouter des sites", onSettings)
        return
    }
    if (state.sites.isEmpty()) {
        Hint(if (state.loading) "Je fais le tour des sites…" else "Pas encore de vérification. Touche le bouton d’actualisation en haut.")
        return
    }
    val now = System.currentTimeMillis()
    state.sites.forEach { c ->
        val reason = c.reason(now)
        Row3(
            dot = statusColor(c.status),
            title = c.name,
            subtitle = reason ?: c.shortHost.takeIf { it != c.name }.orEmpty(),
            subtitleColor = if (c.status == SiteStatus.DOWN) Oc.Down else Oc.Muted,
            trailing = if (c.status == SiteStatus.OK) c.latencyLabel else c.status.label,
            trailingColor = if (c.status == SiteStatus.OK) Oc.Muted else statusColor(c.status),
        )
    }
}

@Composable
private fun EspaceBlock(load: Load<List<EspaceProject>>?, onSettings: () -> Unit) {
    when (load) {
        null -> Hint("Je regarde l’espace client…")
        Load.NotConfigured -> Hint("Connecte l’espace client pour voir où en sont les projets.", "Se connecter", onSettings)
        is Load.Failed -> Hint(load.message, "Voir les connexions", onSettings)
        is Load.Ok -> {
            val active = load.value.filter { !it.isDone }
            if (active.isEmpty()) {
                Hint("Aucun projet en cours. Profites-en !")
            } else {
                active.forEach { p ->
                    val due = p.daysLeft
                    val color = when {
                        p.isLate -> Oc.Down
                        due != null && due <= 3 -> Oc.Tomato
                        due != null && due <= 7 -> Oc.Butter
                        else -> Oc.Ok
                    }
                    Row3(
                        dot = color,
                        title = p.name,
                        subtitle = "${p.kindLabel} · ${p.stepLabel}" + if (p.stepsTotal > 0) " (${p.stepsDone}/${p.stepsTotal})" else "",
                        trailing = if (p.isLate) "en retard · ${p.daysLabel}" else p.daysLabel,
                        trailingColor = if (p.isLate) Oc.Down else Oc.Muted,
                    )
                }
            }
        }
    }
}

@Composable
private fun AgendaBlock(load: Load<List<AgendaEvent>>?, onSettings: () -> Unit, limit: Int = 8) {
    when (load) {
        null -> Hint("Je feuillette l’agenda…")
        Load.NotConfigured -> Hint("Connecte ton agenda pour voir tes prochains rendez-vous.", "Se connecter", onSettings)
        is Load.Failed -> Hint(load.message, "Voir les connexions", onSettings)
        is Load.Ok -> {
            if (load.value.isEmpty()) {
                Hint("Rien de prévu dans les deux semaines. Calme plat !")
            } else {
                val today = LocalDate.now()
                load.value.take(limit).forEach { e ->
                    val day = e.dayLabel(today)
                    Row3(
                        dot = if (day == "aujourd’hui") Oc.Tomato else Oc.Butter,
                        title = e.title,
                        subtitle = listOf(day.replaceFirstChar { it.uppercase() }, e.shortLocation).filter { it.isNotEmpty() }.joinToString(" · "),
                        trailing = e.timeLabel(),
                    )
                }
            }
        }
    }
}
