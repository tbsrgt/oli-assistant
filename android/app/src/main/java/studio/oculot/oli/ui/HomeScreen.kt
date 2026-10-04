package studio.oculot.oli.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
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
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import studio.oculot.oli.core.Game
import studio.oculot.oli.core.GameState
import studio.oculot.oli.core.SiteStatus
import studio.oculot.oli.data.Load
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

/** Ce que l'accueil affiche en plus de l'état du jour. */
data class HomeExtras(
    val game: GameState = GameState(),
    val claudeLine: String? = null,
    val claudeWaiting: Int = 0,
    val paired: Boolean = false,
    val securityScore: Int = -1,
    val freeBytes: Long? = null,
    val missingConnections: Int = 0,
    val noLockWarning: Boolean = false,
)

/** Accueil en « bento » : une grande tuile Oli et des tuiles de tailles variées, chacune ouvre son écran. */
@Composable
fun HomeScreen(state: TodayState, extras: HomeExtras, onRefresh: () -> Unit, onOpen: (String) -> Unit) {
    val down = state.sites.count { it.status == SiteStatus.DOWN }
    val projects = (state.espace as? Load.Ok)?.value?.filter { !it.isDone }.orEmpty()
    val late = projects.count { it.isLate }
    val level = extras.game.level
    val challenges = Game.challengesFor(LocalDate.now())
    val doneChallenges = challenges.count { Game.challengeSucceeded(it, extras.game) }

    Column(
        Modifier.fillMaxSize().background(Oc.Bg).verticalScroll(rememberScrollState()).padding(horizontal = 14.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("Oli", color = Oc.Text, fontSize = 22.sp, fontWeight = FontWeight.Black)
            Text(".", color = Oc.Tomato, fontSize = 22.sp, fontWeight = FontWeight.Black)
            Spacer(Modifier.weight(1f))
            if (state.loading) {
                CircularProgressIndicator(Modifier.size(20.dp), color = Oc.Butter, strokeWidth = 2.dp)
                Spacer(Modifier.width(12.dp))
            } else IconButton(onClick = onRefresh) { Icon(Icons.Filled.Refresh, "Actualiser", tint = Oc.Text) }
            IconButton(onClick = { onOpen("connexions") }) { Icon(Icons.Filled.Settings, "Réglages", tint = Oc.Text) }
        }

        if (extras.noLockWarning) {
            Surface(color = Oc.Butter.copy(alpha = 0.12f), shape = RoundedCornerShape(14.dp), modifier = Modifier.fillMaxWidth()) {
                Text("Ton téléphone n’a pas de verrouillage. Active un code, un schéma ou l’empreinte dans les réglages Android pour protéger Oli.",
                    color = Oc.Butter, fontSize = 13.sp, modifier = Modifier.padding(12.dp))
            }
        }

        // Grande tuile : Oli, son humeur, son niveau et le résumé du jour.
        Tile(index = 0, height = 210.dp, modifier = Modifier.fillMaxWidth(), onClick = { onOpen("defis") },
            brush = Brush.linearGradient(listOf(Color(0xFF241510), Oc.Card))) {
            Row(Modifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
                OliMascot(Modifier.size(130.dp), worried = down > 0)
                Spacer(Modifier.width(8.dp))
                Column(Modifier.weight(1f)) {
                    Text(greeting(), color = Oc.Text, fontSize = 24.sp, fontWeight = FontWeight.Bold)
                    Text(DateTimeFormatter.ofPattern("EEEE d MMMM", Locale.FRANCE).format(LocalDate.now()).replaceFirstChar { it.uppercase() },
                        color = Oc.Muted, fontSize = 13.sp)
                    Spacer(Modifier.height(6.dp))
                    Text(Game.mood(down, extras.claudeWaiting, late, extras.game.streak), color = Oc.Butter, fontSize = 13.sp, fontWeight = FontWeight.Medium)
                    Spacer(Modifier.height(6.dp))
                    Text(summary(state, down, late), color = if (down > 0) Oc.Down else Oc.Text, fontSize = 14.sp, maxLines = 3, overflow = TextOverflow.Ellipsis)
                    Spacer(Modifier.height(8.dp))
                    Text("Oli niveau ${level.level}", color = Oc.Tomato, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                    LinearProgressIndicator(progress = { level.progress }, color = Oc.Tomato, trackColor = Oc.CardBorder,
                        modifier = Modifier.fillMaxWidth().height(5.dp).padding(top = 2.dp))
                }
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            val ok = state.sites.count { it.status == SiteStatus.OK || it.status == SiteStatus.WARNING }
            Tile(1, 150.dp, Modifier.weight(1f), onClick = { onOpen("sites") }) {
                TileTitle("Sites")
                if (state.sites.isEmpty()) TileBody("Ajoute tes sites, je les surveille.")
                else {
                    BigNumber("$ok/${state.sites.size}", if (down > 0) Oc.Down else Oc.Ok)
                    TileBody(if (down > 0) "$down en panne" else "en ligne")
                }
            }
            Tile(2, 150.dp, Modifier.weight(1f), onClick = { onOpen("projets") }) {
                TileTitle("Projets")
                when (state.espace) {
                    is Load.Ok -> {
                        BigNumber("${projects.size}", if (late > 0) Oc.Down else Oc.Text)
                        TileBody(if (late > 0) "en cours · $late en retard" else "en cours")
                    }
                    Load.NotConfigured -> TileBody("Connecte l’espace client.")
                    else -> TileBody("…")
                }
            }
        }

        Tile(3, 118.dp, Modifier.fillMaxWidth(), onClick = { onOpen("agenda") }) {
            TileTitle("Agenda")
            when (val a = state.agenda) {
                is Load.Ok -> {
                    val upcoming = a.value.take(2)
                    if (upcoming.isEmpty()) TileBody("Rien de prévu. Calme plat !")
                    upcoming.forEach { e ->
                        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 4.dp)) {
                            Text("${e.dayLabel()} ${e.timeLabel()}".replaceFirstChar { it.uppercase() }, color = Oc.Tomato, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                            Spacer(Modifier.width(8.dp))
                            Text(e.title, color = Oc.Text, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
                Load.NotConfigured -> TileBody("Connecte ton agenda pour voir tes rendez-vous.")
                is Load.Failed -> TileBody(a.message)
                null -> TileBody("Je feuillette l’agenda…")
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Tile(4, 140.dp, Modifier.weight(1.25f), onClick = { onOpen("claude") },
                brush = if (extras.claudeWaiting > 0) Brush.linearGradient(listOf(Color(0xFF3A1C12), Oc.Card)) else null) {
                TileTitle("Claude Code")
                if (!extras.paired) TileBody("Jumelle ton Mac pour suivre Claude d’ici.")
                else {
                    if (extras.claudeWaiting > 0) BigNumber("${extras.claudeWaiting}", Oc.Tomato)
                    TileBody(extras.claudeLine ?: "Touche pour voir les sessions.")
                }
            }
            Tile(5, 140.dp, Modifier.weight(1f), onClick = { onOpen("telephone") }) {
                TileTitle("Téléphone")
                if (extras.securityScore >= 0) BigNumber("${extras.securityScore}", if (extras.securityScore >= 75) Oc.Ok else Oc.Butter)
                TileBody(listOfNotNull(
                    if (extras.securityScore < 0) "Lance l’audit" else "sur 100",
                    extras.freeBytes?.let { studio.oculot.oli.core.Cleanup.human(it) + " libres" },
                ).joinToString(" · "))
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Tile(6, 130.dp, Modifier.weight(1f), onClick = { onOpen("rangement") }) {
                TileTitle("Rangement")
                TileBody("Téléchargements triés, captures renommées.")
                if (extras.game.streak > 0) Text("Série : ${extras.game.streak} j", color = Oc.Butter, fontSize = 12.sp, fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(top = 4.dp))
            }
            Tile(7, 130.dp, Modifier.weight(1.3f), onClick = { onOpen("defis") }) {
                TileTitle("Défis du jour")
                BigNumber("$doneChallenges/${challenges.size}", if (doneChallenges == challenges.size) Oc.Ok else Oc.Text)
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    challenges.forEach { c ->
                        Box(Modifier.size(8.dp).background(if (Game.challengeSucceeded(c, extras.game)) Oc.Ok else Oc.CardBorder, CircleShape))
                    }
                }
            }
        }

        if (extras.missingConnections > 0) {
            Tile(8, 86.dp, Modifier.fillMaxWidth(), onClick = { onOpen("toutconnecter") },
                brush = Brush.horizontalGradient(listOf(Oc.Tomato, Color(0xFFFF8A52)))) {
                Row(Modifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text("Tout connecter", color = Oc.Bg, fontSize = 18.sp, fontWeight = FontWeight.Black)
                        Text("Encore ${extras.missingConnections} service${if (extras.missingConnections > 1) "s" else ""} à brancher, une étape à la fois.",
                            color = Oc.Bg.copy(alpha = 0.8f), fontSize = 13.sp)
                    }
                    Text("→", color = Oc.Bg, fontSize = 24.sp, fontWeight = FontWeight.Black)
                }
            }
        }

        Tile(9, 76.dp, Modifier.fillMaxWidth(), onClick = { onOpen("chat") }) {
            Row(Modifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("Demander à Oli", color = Oc.Text, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                    Text("Une question, un mail à rédiger ? Claude répond via ton Mac.", color = Oc.Muted, fontSize = 13.sp)
                }
                Text("→", color = Oc.Tomato, fontSize = 20.sp, fontWeight = FontWeight.Bold)
            }
        }
        Spacer(Modifier.height(16.dp))
    }
}

/** Une tuile : entrée en douceur (décalée selon sa place), léger enfoncement au toucher. */
@Composable
private fun Tile(
    index: Int,
    height: Dp,
    modifier: Modifier = Modifier,
    brush: Brush? = null,
    onClick: () -> Unit,
    content: @Composable () -> Unit,
) {
    val appear = remember { Animatable(0f) }
    LaunchedEffect(Unit) {
        delay(40L * index)
        appear.animateTo(1f, spring(dampingRatio = 0.8f, stiffness = Spring.StiffnessLow))
    }
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed) 0.97f else 1f, tween(120), label = "appui")
    Surface(
        color = Oc.Card,
        shape = RoundedCornerShape(22.dp),
        border = BorderStroke(1.dp, Oc.CardBorder),
        modifier = modifier.height(height).graphicsLayer {
            alpha = appear.value
            translationY = (1f - appear.value) * 40f
            scaleX = scale; scaleY = scale
        }.clickable(interactionSource = interaction, indication = null, onClick = onClick),
    ) {
        Box(Modifier.fillMaxSize().let { if (brush != null) it.background(brush) else it }.padding(14.dp)) {
            Column(Modifier.fillMaxHeight()) { content() }
        }
    }
}

@Composable
private fun TileTitle(text: String) {
    Text(text.uppercase(), color = Oc.Muted, fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.4.sp)
}

@Composable
private fun TileBody(text: String) {
    Text(text, color = Oc.Muted, fontSize = 13.sp, maxLines = 3, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 4.dp))
}

@Composable
private fun BigNumber(text: String, color: Color) {
    Text(text, color = color, fontSize = 34.sp, fontWeight = FontWeight.Black, modifier = Modifier.padding(top = 6.dp))
}
