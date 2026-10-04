package studio.oculot.oli.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.BorderStroke
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
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import studio.oculot.oli.core.ClaudeApproval
import studio.oculot.oli.core.ClaudeBoard
import studio.oculot.oli.core.ClaudeSession
import studio.oculot.oli.data.Load
import studio.oculot.oli.data.Repository
import studio.oculot.oli.work.Automator

/**
 * Claude Code sur le Mac : sessions en cours et demandes d'autorisation. Vérifié toutes les 15 s tant
 * que l'écran est ouvert. « Autoriser » passe d'abord par l'empreinte, le visage ou le code du téléphone.
 */
@Composable
fun ClaudeCodeScreen(
    repo: Repository,
    paired: Boolean,
    onBack: () -> Unit,
    onConnect: () -> Unit,
    confirm: (reason: String, onOk: () -> Unit) -> Unit,
    onDecided: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var board by remember { mutableStateOf<Load<ClaudeBoard>?>(null) }
    var busy by remember { mutableStateOf<String?>(null) }
    var message by remember { mutableStateOf<String?>(null) }
    var tick by remember { mutableStateOf(0) }

    LaunchedEffect(paired, tick) {
        if (!paired) return@LaunchedEffect
        while (true) {
            board = Automator.claudeCheck(context, quick = false, notify = false)
            delay(15_000)
        }
    }

    fun decide(a: ClaudeApproval, allow: Boolean) {
        val run = {
            busy = a.id; message = null
            scope.launch {
                val err = repo.claudeDecide(a.id, allow)
                busy = null
                if (err == null) {
                    message = if (allow) "C’est autorisé, Claude continue." else "Refusé. Claude a été prévenu."
                    onDecided()
                    tick++
                } else message = err
            }
            Unit
        }
        if (allow) confirm("Autoriser « ${a.tool.ifBlank { "l’action" }} » sur ${a.project}", run) else run()
    }

    Column(Modifier.fillMaxSize().background(Oc.Bg).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp)) {
        ScreenHeader("Claude Code", onBack)
        HelpText("Ce que Claude fait sur ton Mac, en direct. Je vérifie toutes les 15 secondes tant que cet écran est ouvert.",
            Modifier.padding(top = 4.dp))

        if (!paired) {
            Text("Jumelle d’abord ton Mac pour suivre Claude d’ici.", color = Oc.Text, fontSize = 15.sp)
            Spacer(Modifier.height(12.dp))
            PrimaryButton("Se connecter à Claude", onConnect)
            return@Column
        }
        message?.let { Text(it, color = Oc.Butter, fontSize = 14.sp, modifier = Modifier.padding(bottom = 8.dp)) }

        when (val b = board) {
            null -> Text("Je contacte ton Mac…", color = Oc.Muted, fontSize = 14.sp)
            Load.NotConfigured -> PrimaryButton("Se connecter à Claude", onConnect)
            is Load.Failed -> {
                Text(b.message, color = Oc.Down, fontSize = 14.sp)
                TextButton(onClick = { tick++ }) { Text("Réessayer", color = Oc.Tomato) }
            }
            is Load.Ok -> {
                if (!b.value.approvalsEnabled) {
                    Surface(color = Oc.Card, shape = RoundedCornerShape(16.dp), border = BorderStroke(1.dp, Oc.Butter.copy(alpha = 0.5f)),
                        modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
                        Text("Pour répondre aux autorisations depuis ton téléphone, active-le sur le Mac : Oli → Réglages → Connexions → Téléphone.",
                            color = Oc.Butter, fontSize = 14.sp, modifier = Modifier.padding(14.dp))
                    }
                }
                if (b.value.approvals.isNotEmpty()) {
                    SectionLabel("Attend ton accord", Modifier.padding(top = 8.dp))
                    b.value.approvals.forEach { a ->
                        AnimatedVisibility(true, enter = fadeIn(), exit = shrinkVertically() + fadeOut()) {
                            ApprovalCard(a, busy == a.id, onAllow = { decide(a, true) }, onDeny = { decide(a, false) })
                        }
                        Spacer(Modifier.height(10.dp))
                    }
                }
                SectionLabel("Sessions", Modifier.padding(top = 8.dp))
                if (b.value.sessions.isEmpty()) Text("Aucune session Claude Code ouverte sur ton Mac.", color = Oc.Muted, fontSize = 14.sp)
                b.value.sessions.forEach { SessionRow(it) }
            }
        }
        Spacer(Modifier.height(24.dp))
    }
}

@Composable
private fun ApprovalCard(a: ClaudeApproval, busy: Boolean, onAllow: () -> Unit, onDeny: () -> Unit) {
    Surface(color = Oc.Card, shape = RoundedCornerShape(18.dp), border = BorderStroke(1.dp, Oc.Tomato.copy(alpha = 0.6f)), modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp)) {
            Text(a.project, color = Oc.Muted, fontSize = 12.sp, fontWeight = FontWeight.Bold)
            Text(listOf(a.tool, a.summary).filter { it.isNotBlank() }.joinToString(" · "), color = Oc.Text, fontSize = 16.sp, fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(top = 2.dp))
            if (a.detail.isNotBlank()) {
                Box(Modifier.padding(top = 8.dp).fillMaxWidth().background(Oc.Bg, RoundedCornerShape(10.dp)).padding(10.dp)) {
                    Text(a.detail.take(600), color = Oc.Text, fontSize = 13.sp, fontFamily = FontFamily.Monospace)
                }
            }
            Spacer(Modifier.height(12.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedButton(onClick = onDeny, enabled = !busy, border = BorderStroke(1.dp, Oc.CardBorder),
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = Oc.Text), modifier = Modifier.weight(1f)) { Text("Refuser") }
                Button(onClick = onAllow, enabled = !busy, colors = ButtonDefaults.buttonColors(containerColor = Oc.Tomato, contentColor = Oc.Bg),
                    modifier = Modifier.weight(1f)) { Text(if (busy) "…" else "Autoriser", fontWeight = FontWeight.Bold) }
            }
        }
    }
}

@Composable
private fun SessionRow(s: ClaudeSession) {
    val color = when (s.state) { "working" -> Oc.Butter; "waiting" -> Oc.Tomato; "done" -> Oc.Ok; else -> Oc.Unknown }
    Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(10.dp).background(color, CircleShape))
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(s.project, color = Oc.Text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
            Text(listOf(s.stateLabel, s.activity).filter { it.isNotBlank() }.joinToString(" · "), color = Oc.Muted, fontSize = 13.sp, maxLines = 2)
        }
        if (s.updatedAt > 0) Text(ago(s.updatedAt), color = Oc.Muted, fontSize = 12.sp)
    }
}

private fun ago(epochSeconds: Long): String {
    val m = (System.currentTimeMillis() / 1000 - epochSeconds) / 60
    return when {
        m < 1 -> "à l’instant"
        m < 60 -> "il y a $m min"
        m < 24 * 60 -> "il y a ${m / 60} h"
        else -> "il y a ${m / 1440} j"
    }
}
