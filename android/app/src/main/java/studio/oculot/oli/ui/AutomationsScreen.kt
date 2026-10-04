package studio.oculot.oli.ui

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings as AndroidSettings
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import studio.oculot.oli.ShareActivity
import studio.oculot.oli.data.AutomationPrefs
import studio.oculot.oli.work.Alarms
import studio.oculot.oli.overlay.OverlayService

/** Réglages → Automatisations : tout est actif par défaut, chaque interrupteur coupe une fonction. */
@Composable
fun AutomationsScreen(onBack: () -> Unit, onChanged: () -> Unit, onFloatingIntro: () -> Unit = {}) {
    val context = LocalContext.current
    val prefs = remember { AutomationPrefs(context) }
    val states = remember { mutableStateMapOf<AutomationPrefs.Key, Boolean>().apply { AutomationPrefs.Key.entries.forEach { put(it, prefs.isOn(it)) } } }

    Column(Modifier.fillMaxSize().background(Oc.Bg).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp)) {
        ScreenHeader("Automatisations", onBack)
        HelpText("Ce qu’Oli fait tout seul. Rien n’est jamais envoyé à ta place : Oli prévient, tu décides.",
            Modifier.padding(top = 4.dp, bottom = 12.dp))

        Surface(color = Oc.Card, shape = RoundedCornerShape(18.dp), border = BorderStroke(1.dp, Oc.CardBorder), modifier = Modifier.fillMaxWidth()) {
            Column {
                AutomationPrefs.Key.entries.forEachIndexed { i, k ->
                    if (i > 0) Box(Modifier.fillMaxWidth().padding(horizontal = 16.dp).height(1.dp).background(Oc.CardBorder))
                    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(k.title, color = Oc.Text, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                            Text(k.help, color = Oc.Muted, fontSize = 13.sp)
                        }
                        Spacer(Modifier.width(12.dp))
                        Switch(
                            checked = states[k] == true,
                            onCheckedChange = { on ->
                                if (k == AutomationPrefs.Key.FLOATING && on && !OverlayService.canShow(context)) { onFloatingIntro(); return@Switch }
                                states[k] = on
                                prefs.set(k, on)
                                apply(context, k, on)
                                onChanged()
                            },
                            colors = SwitchDefaults.colors(checkedTrackColor = Oc.Tomato, checkedThumbColor = Oc.Bg),
                        )
                    }
                }
            }
        }

        if (!Alarms.canBeExact(context) && Build.VERSION.SDK_INT >= 31) {
            Spacer(Modifier.height(16.dp))
            Text("Pour des rappels pile à l’heure, autorise les alarmes exactes pour Oli.", color = Oc.Butter, fontSize = 14.sp)
            TextButton(onClick = {
                runCatching {
                    context.startActivity(Intent(AndroidSettings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:" + context.packageName)))
                }
            }) { Text("Autoriser", color = Oc.Tomato, fontWeight = FontWeight.SemiBold) }
        }

        Spacer(Modifier.height(20.dp))
        SectionLabel("Widget")
        HelpText("Ajoute le widget Oli depuis ton écran d’accueil (appui long → Widgets → Oli) : l’état des sites et ton prochain rendez-vous, d’un coup d’œil.")
        Spacer(Modifier.height(24.dp))
    }
}

private fun apply(context: Context, k: AutomationPrefs.Key, on: Boolean) {
    when (k) {
        AutomationPrefs.Key.BRIEFING -> Alarms.scheduleBriefing(context)
        AutomationPrefs.Key.EVENING -> Alarms.scheduleEvening(context)
        AutomationPrefs.Key.FLOATING -> if (on) OverlayService.start(context) else OverlayService.stop(context)
        AutomationPrefs.Key.REMINDERS -> if (!on) Alarms.scheduleReminders(context, emptyList())
        AutomationPrefs.Key.SHARE -> context.packageManager.setComponentEnabledSetting(
            ComponentName(context, ShareActivity::class.java),
            if (on) PackageManager.COMPONENT_ENABLED_STATE_DEFAULT else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.DONT_KILL_APP,
        )
        else -> {}
    }
}
