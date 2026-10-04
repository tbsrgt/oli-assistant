package studio.oculot.oli.ui

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.compose.foundation.background
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import studio.oculot.oli.data.AutomationPrefs
import studio.oculot.oli.overlay.OverlayService

/** Explique Oli flottant et envoie vers l'autorisation « Afficher par-dessus les autres apps ». */
@Composable
fun FloatingIntroScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    var granted by remember { mutableStateOf(OverlayService.canShow(context)) }
    var on by remember { mutableStateOf(AutomationPrefs(context).isOn(AutomationPrefs.Key.FLOATING)) }
    var requested by remember { mutableStateOf(false) }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(Unit) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            granted = OverlayService.canShow(context)
            if (granted && !on && requested) {
                requested = false
                AutomationPrefs(context).set(AutomationPrefs.Key.FLOATING, true)
                OverlayService.start(context)
                on = true
            }
        }
    }

    Column(Modifier.fillMaxSize().background(Oc.Bg).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp)) {
        ScreenHeader("Oli flottant", onBack)
        Spacer(Modifier.height(16.dp))
        // Aperçu de la pastille.
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            Row(Modifier.background(Color.Black, RoundedCornerShape(22.dp)).padding(horizontal = 12.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically) {
                OliMascot(Modifier.size(28.dp), frameMs = 90)
                Spacer(Modifier.width(6.dp))
                Text("3 sites ok", color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Medium)
            }
        }
        Spacer(Modifier.height(20.dp))
        Text("Comme sur ton Mac, Oli peut vivre en haut de l’écran, par-dessus les autres apps.", color = Oc.Text, fontSize = 16.sp)
        Spacer(Modifier.height(10.dp))
        listOf(
            "Une petite pastille noire sous la barre d’état, avec l’info du moment : sites, Claude, prochain rendez-vous.",
            "Touche-la : elle se déplie avec le résumé du jour et des raccourcis. Touche ailleurs ou glisse vers le haut pour la replier.",
            "Glisse-la à gauche ou à droite si elle te gêne. « Masquer Oli » dans sa notification la fait disparaître.",
            "Android demande l’autorisation « Afficher par-dessus les autres apps » et une notification permanente : c’est la règle pour tout ce qui reste à l’écran.",
        ).forEach { Text("• $it", color = Oc.Muted, fontSize = 14.sp, modifier = Modifier.padding(vertical = 4.dp)) }
        Spacer(Modifier.height(20.dp))
        if (granted && on) {
            SuccessText("Oli flotte ✓")
            SecondaryButton("Masquer Oli", {
                AutomationPrefs(context).set(AutomationPrefs.Key.FLOATING, false)
                OverlayService.stop(context); on = false
            }, danger = true)
        } else if (granted) {
            PrimaryButton("Afficher Oli", {
                AutomationPrefs(context).set(AutomationPrefs.Key.FLOATING, true)
                OverlayService.start(context); on = true
            })
        } else {
            PrimaryButton("Ouvrir le réglage", {
                requested = true
                runCatching {
                    context.startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:" + context.packageName))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                }
            })
            HelpText("Active « Oli » dans la liste, puis reviens ici.", Modifier.padding(top = 8.dp))
        }
        Spacer(Modifier.height(32.dp))
    }
}
