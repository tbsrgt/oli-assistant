package studio.oculot.oli.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.updateAll
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.layout.height
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import studio.oculot.oli.MainActivity
import studio.oculot.oli.R
import studio.oculot.oli.core.SiteStatus
import studio.oculot.oli.data.MemoryStore
import studio.oculot.oli.data.Repository
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** Ce que montre le widget : lu dans les caches locaux, aucun appel réseau. */
private data class WidgetData(val sitesLine: String, val sitesColor: Color, val nextLine: String)

/** Widget d'écran d'accueil : Oli, l'état des sites et le prochain rendez-vous. Un tap ouvre l'app. */
class OliWidget : GlanceAppWidget() {

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val data = load(context)
        provideContent { Content(data) }
    }

    private fun load(context: Context): WidgetData {
        val checks = runCatching { Repository(context).cachedChecks() }.getOrDefault(emptyList())
        val down = checks.count { it.status == SiteStatus.DOWN }
        val warn = checks.count { it.status == SiteStatus.WARNING }
        val (line, color) = when {
            checks.isEmpty() -> "Aucun site surveillé" to MUTED
            down == 1 -> "1 site en panne" to DOWN
            down > 1 -> "$down sites en panne" to DOWN
            warn > 0 -> "Sites en ligne · $warn à surveiller" to BUTTER
            else -> "Tous les sites répondent" to OK
        }
        val next = MemoryStore(context).nextEvent()
        val nextLine = if (next == null) "Pas de rendez-vous à venir" else {
            val zone = ZoneId.systemDefault()
            val at = Instant.ofEpochMilli(next.second).atZone(zone)
            val today = LocalDate.now(zone)
            val day = when (at.toLocalDate()) {
                today -> "Aujourd’hui"
                today.plusDays(1) -> "Demain"
                else -> DateTimeFormatter.ofPattern("EEE d MMM", Locale.FRANCE).format(at).replaceFirstChar { it.uppercase() }
            }
            "$day ${DateTimeFormatter.ofPattern("HH:mm", Locale.FRANCE).format(at)} · ${next.first}"
        }
        return WidgetData(line, color, nextLine)
    }

    @Composable
    private fun Content(d: WidgetData) {
        Row(
            GlanceModifier.fillMaxSize().background(BG).cornerRadius(22.dp).padding(14.dp)
                .clickable(actionStartActivity<MainActivity>()),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Image(ImageProvider(R.drawable.ic_launcher_foreground), contentDescription = "Oli", modifier = GlanceModifier.size(64.dp))
            Spacer(GlanceModifier.width(8.dp))
            Column {
                Text("Oli", style = TextStyle(color = ColorProvider(TEXT), fontSize = 16.sp, fontWeight = FontWeight.Bold))
                Spacer(GlanceModifier.height(2.dp))
                Text(d.sitesLine, maxLines = 1, style = TextStyle(color = ColorProvider(d.sitesColor), fontSize = 13.sp, fontWeight = FontWeight.Medium))
                Spacer(GlanceModifier.height(2.dp))
                Text(d.nextLine, maxLines = 2, style = TextStyle(color = ColorProvider(MUTED), fontSize = 13.sp))
            }
        }
    }

    companion object {
        private val BG = Color(0xFF17171B)
        private val TEXT = Color(0xFFF5F1EA)
        private val MUTED = Color(0xFF9A968F)
        private val OK = Color(0xFF22C55E)
        private val DOWN = Color(0xFFF4505E)
        private val BUTTER = Color(0xFFFFD65C)

        suspend fun refresh(context: Context) = OliWidget().updateAll(context)
    }
}

class OliWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = OliWidget()
}
