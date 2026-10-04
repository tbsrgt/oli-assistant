package studio.oculot.oli.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import kotlinx.coroutines.launch
import studio.oculot.oli.core.Game
import studio.oculot.oli.core.GameState
import studio.oculot.oli.core.GameUpdate
import studio.oculot.oli.data.GameStore
import java.time.LocalDate
import kotlin.math.cos
import kotlin.math.sin
import kotlin.random.Random

/** Défis du jour, niveau d'Oli, séries et badges. */
@Composable
fun GameScreen(game: GameState, store: GameStore, onBack: () -> Unit) {
    val scope = rememberCoroutineScope()
    val today = LocalDate.now()
    val level = game.level
    Column(Modifier.fillMaxSize().background(Oc.Bg).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp)) {
        ScreenHeader("Défis", onBack)
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(vertical = 8.dp)) {
            OliMascot(Modifier.size(96.dp))
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text("Oli niveau ${level.level}", color = Oc.Text, fontSize = 22.sp, fontWeight = FontWeight.Black)
                Text("${level.xpInLevel} / ${level.xpForNext} XP avant le niveau ${level.level + 1}", color = Oc.Muted, fontSize = 13.sp)
                LinearProgressIndicator(progress = { level.progress }, color = Oc.Tomato, trackColor = Oc.CardBorder,
                    modifier = Modifier.fillMaxWidth().height(8.dp).padding(top = 6.dp))
                Text("Série : ${game.streak} jour${if (game.streak > 1) "s" else ""} · record ${game.bestStreak}", color = Oc.Butter, fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 6.dp))
            }
        }
        HelpText("La série avance chaque jour où tu lis le briefing, nettoies ou ranges le téléphone.")

        SectionLabel("Défis du jour", Modifier.padding(top = 8.dp))
        Game.challengesFor(today).forEach { c ->
            val ok = Game.challengeSucceeded(c, game)
            Surface(color = Oc.Card, shape = RoundedCornerShape(16.dp), border = BorderStroke(1.dp, if (ok) Oc.Ok.copy(alpha = 0.6f) else Oc.CardBorder),
                modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp)) {
                Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(22.dp).background(if (ok) Oc.Ok else Oc.CardBorder, CircleShape), contentAlignment = Alignment.Center) {
                        if (ok) Text("✓", color = Oc.Bg, fontSize = 13.sp, fontWeight = FontWeight.Black)
                    }
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(c.title, color = Oc.Text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                        Text(if (c.help.isNotBlank()) c.help else "+40 XP", color = Oc.Muted, fontSize = 12.sp)
                    }
                    if (c.manual && !ok) TextButton(onClick = { scope.launch { store.record(manualChallenge = c.id) } }) {
                        Text("C’est fait", color = Oc.Tomato, fontWeight = FontWeight.SemiBold)
                    }
                }
            }
        }

        SectionLabel("Badges · ${game.badges.size}/${Game.badges.size}", Modifier.padding(top = 12.dp))
        Game.badges.chunked(3).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(bottom = 8.dp)) {
                row.forEach { b ->
                    val got = b.id in game.badges
                    Surface(color = if (got) Color(0xFF2A1A12) else Oc.Card, shape = RoundedCornerShape(16.dp),
                        border = BorderStroke(1.dp, if (got) Oc.Tomato.copy(alpha = 0.6f) else Oc.CardBorder), modifier = Modifier.weight(1f).height(118.dp)) {
                        Column(Modifier.padding(10.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                            Box(Modifier.size(34.dp).background(if (got) Oc.Tomato else Oc.CardBorder, CircleShape), contentAlignment = Alignment.Center) {
                                Text(if (got) "★" else "?", color = if (got) Oc.Bg else Oc.Muted, fontSize = 16.sp, fontWeight = FontWeight.Black)
                            }
                            Text(b.title, color = if (got) Oc.Text else Oc.Muted, fontSize = 12.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center,
                                modifier = Modifier.padding(top = 6.dp))
                            Text(b.description, color = Oc.Muted, fontSize = 10.sp, textAlign = TextAlign.Center, lineHeight = 12.sp)
                        }
                    }
                }
                repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
        Spacer(Modifier.height(24.dp))
    }
}

/** Petite fête : confettis et Oli, pour un badge, un niveau ou un défi réussi. */
@Composable
fun Celebration(update: GameUpdate, onDismiss: () -> Unit) {
    val progress = remember { Animatable(0f) }
    LaunchedEffect(update) { progress.snapTo(0f); progress.animateTo(1f, tween(1600, easing = LinearEasing)) }
    val pieces = remember(update) { List(46) { Triple(Random.nextFloat() * 360f, 0.4f + Random.nextFloat() * 0.6f, Random.nextInt(3)) } }
    val title = when {
        update.newBadges.isNotEmpty() -> "Badge débloqué : ${update.newBadges.first().title}"
        update.levelUp -> "Oli passe niveau ${update.state.level.level} !"
        else -> "Défi réussi : ${update.newChallenges.first().title}"
    }
    val subtitle = when {
        update.newBadges.isNotEmpty() -> update.newBadges.first().description
        update.levelUp -> "Merci de prendre soin de lui."
        else -> "+40 XP"
    }
    Dialog(onDismissRequest = onDismiss) {
        Surface(color = Oc.Card, shape = RoundedCornerShape(28.dp)) {
            Box(contentAlignment = Alignment.Center) {
                Canvas(Modifier.fillMaxWidth().height(300.dp)) {
                    val c = Offset(size.width / 2, size.height * 0.36f)
                    val t = progress.value
                    pieces.forEach { (angle, speed, color) ->
                        val a = Math.toRadians(angle.toDouble())
                        val d = t * speed * size.width * 0.55f
                        val p = Offset(c.x + (cos(a) * d).toFloat(), c.y + (sin(a) * d).toFloat() + t * t * 120f)
                        drawCircle(listOf(Oc.Tomato, Oc.Butter, Oc.Ok)[color].copy(alpha = 1f - t * 0.8f), radius = 5.dp.toPx() * (1f - t * 0.4f), center = p)
                    }
                }
                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(24.dp)) {
                    OliMascot(Modifier.size(110.dp))
                    Text(title, color = Oc.Text, fontSize = 19.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
                    Text(subtitle, color = Oc.Muted, fontSize = 14.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 4.dp, bottom = 12.dp))
                    PrimaryButton("Super !", onDismiss)
                }
            }
        }
    }
}
