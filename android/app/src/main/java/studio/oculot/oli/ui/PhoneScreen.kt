package studio.oculot.oli.ui

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CheckboxDefaults
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.TabRowDefaults
import androidx.compose.material3.TabRowDefaults.tabIndicatorOffset
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import studio.oculot.oli.core.Advice
import studio.oculot.oli.core.Candidate
import studio.oculot.oli.core.CleanCategory
import studio.oculot.oli.core.Cleanup
import studio.oculot.oli.core.GameEvent
import studio.oculot.oli.core.Move
import studio.oculot.oli.core.Security
import studio.oculot.oli.core.SecurityReport
import studio.oculot.oli.core.SettingsTarget
import studio.oculot.oli.data.AutomationPrefs
import studio.oculot.oli.data.GameStore
import studio.oculot.oli.data.MemoryStore
import studio.oculot.oli.data.Phone
import studio.oculot.oli.work.Alarms
import java.time.LocalDate

/** Ouvre le bon écran des Paramètres Android pour un conseil. */
fun openSettings(context: Context, target: SettingsTarget, pkg: String? = null) {
    val i = when (target) {
        SettingsTarget.SECURITY -> Intent(Settings.ACTION_SECURITY_SETTINGS)
        SettingsTarget.DEVELOPER -> Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS)
        SettingsTarget.SYSTEM_UPDATE -> Intent("android.settings.SYSTEM_UPDATE_SETTINGS")
        SettingsTarget.APP_DETAILS -> Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$pkg"))
        SettingsTarget.ACCESSIBILITY -> Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
        SettingsTarget.NOTIFICATION_LISTENERS -> Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
        SettingsTarget.UNKNOWN_SOURCES -> Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
        SettingsTarget.OVERLAY -> Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, pkg?.let { Uri.parse("package:$it") })
    }.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    try { context.startActivity(i) } catch (_: ActivityNotFoundException) {
        runCatching { context.startActivity(Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
    }
}

/** Play Protect (Google Play Services), sinon les réglages de sécurité. */
fun openPlayProtect(context: Context) {
    val tries = listOf(
        Intent("com.google.android.gms.settings.VERIFY_APPS_SETTINGS"),
        Intent().setClassName("com.google.android.gms", "com.google.android.gms.security.settings.VerifyAppsSettingsActivity"),
        Intent(Settings.ACTION_SECURITY_SETTINGS),
    )
    for (i in tries) {
        try { context.startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); return } catch (_: Exception) {}
    }
}

/** Santé du téléphone : audit de sécurité et nettoyage. */
@Composable
fun PhoneScreen(onBack: () -> Unit, onTidy: () -> Unit) {
    var tab by remember { mutableIntStateOf(0) }
    Column(Modifier.fillMaxSize().background(Oc.Bg)) {
        Box(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) { ScreenHeader("Téléphone", onBack) }
        TabRow(selectedTabIndex = tab, containerColor = Oc.Bg, contentColor = Oc.Text,
            indicator = { pos -> TabRowDefaults.SecondaryIndicator(Modifier.tabIndicatorOffset(pos[tab]), color = Oc.Tomato) }) {
            listOf("Sécurité", "Nettoyage", "Rangement").forEachIndexed { i, t ->
                Tab(selected = tab == i, onClick = { if (i == 2) onTidy() else tab = i },
                    text = { Text(t, fontWeight = if (tab == i) FontWeight.Bold else FontWeight.Normal) })
            }
        }
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 12.dp)) {
            if (tab == 0) SecurityTab() else CleanTab()
            Spacer(Modifier.height(32.dp))
        }
    }
}

@Composable
private fun SecurityTab() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var report by remember { mutableStateOf<SecurityReport?>(null) }
    var busy by remember { mutableStateOf(false) }
    var showApps by remember { mutableStateOf(false) }

    fun run() {
        busy = true
        scope.launch {
            val facts = Phone.securityFacts(context)
            val r = Security.evaluate(facts, LocalDate.now(), context.packageName)
            report = r; busy = false
            MemoryStore(context).saveSecurityScore(r.score)
            GameStore(context).record(GameEvent.SECURITY_CHECK, securityScore = r.score)
        }
    }
    // Relance l'audit au retour des Paramètres, pour voir la note bouger.
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(Unit) { lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) { run() } }

    HelpText("Oli vérifie les réglages et les accès des apps. Ce n’est pas un antivirus : pour chercher des apps malveillantes, utilise Play Protect.")
    val r = report
    if (r == null) { Text(if (busy) "J’inspecte le téléphone…" else "", color = Oc.Muted); return }

    Row(verticalAlignment = Alignment.CenterVertically) {
        ScoreRing(r.score)
        Spacer(Modifier.width(16.dp))
        Column {
            Text(r.label, color = Oc.Text, fontSize = 22.sp, fontWeight = FontWeight.Bold)
            Text(if (r.advices.isEmpty()) "Rien à signaler, bravo." else "${r.advices.size} conseil${if (r.advices.size > 1) "s" else ""} pour faire mieux.",
                color = Oc.Muted, fontSize = 14.sp)
        }
    }
    Spacer(Modifier.height(14.dp))
    PrimaryButton("Vérifier avec Play Protect", { openPlayProtect(context) })
    Spacer(Modifier.height(16.dp))
    r.advices.forEach { a -> AdviceRow(a) { openSettings(context, a.target, a.pkg) } }
    if (r.sideloaded.isNotEmpty() || r.sensitive.isNotEmpty()) {
        TextButton(onClick = { showApps = !showApps }) {
            Text(if (showApps) "Masquer le détail des apps" else "Voir le détail des apps (${(r.sideloaded + r.sensitive).distinctBy { it.pkg }.size})", color = Oc.Tomato)
        }
        if (showApps) (r.sideloaded + r.sensitive).distinctBy { it.pkg }.forEach { a ->
            Column(Modifier.fillMaxWidth().clickable { openSettings(context, SettingsTarget.APP_DETAILS, a.pkg) }.padding(vertical = 6.dp)) {
                Text(a.label, color = Oc.Text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                Text(listOfNotNull(
                    if (a.installer == null || a.installer !in Security.trustedInstallers) "hors magasin d’apps" else null,
                    a.sensitivities.takeIf { it.isNotEmpty() }?.joinToString(", ") { it.label },
                ).joinToString(" · "), color = Oc.Muted, fontSize = 13.sp)
            }
        }
    }
}

@Composable
private fun ScoreRing(score: Int) {
    val p by animateFloatAsState(score / 100f, tween(900), label = "note")
    val color = when { score >= 90 -> Oc.Ok; score >= 75 -> Oc.Ok; score >= 55 -> Oc.Butter; else -> Oc.Down }
    Box(Modifier.size(96.dp), contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val w = 10.dp.toPx()
            drawArc(Oc.CardBorder, 0f, 360f, false, topLeft = Offset(w / 2, w / 2), size = Size(size.width - w, size.height - w), style = Stroke(w))
            drawArc(color, -90f, 360f * p, false, topLeft = Offset(w / 2, w / 2), size = Size(size.width - w, size.height - w), style = Stroke(w, cap = StrokeCap.Round))
        }
        Text("$score", color = Oc.Text, fontSize = 28.sp, fontWeight = FontWeight.Black)
    }
}

@Composable
private fun AdviceRow(a: Advice, onClick: () -> Unit) {
    Surface(color = Oc.Card, shape = RoundedCornerShape(16.dp), border = BorderStroke(1.dp, Oc.CardBorder),
        modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp).clickable(onClick = onClick)) {
        Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(a.title, color = Oc.Text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                Text(a.detail, color = Oc.Muted, fontSize = 13.sp)
            }
            Spacer(Modifier.width(8.dp))
            Text("−${a.points}", color = if (a.points >= 10) Oc.Down else Oc.Butter, fontSize = 13.sp, fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
private fun AllFilesCard(reason: String) {
    val context = LocalContext.current
    Surface(color = Oc.Card, shape = RoundedCornerShape(16.dp), border = BorderStroke(1.dp, Oc.Butter.copy(alpha = 0.5f)), modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(14.dp)) {
            Text("Accès à tous les fichiers", color = Oc.Text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
            Text("$reason C’est un accès large : Oli ne s’en sert que pour lister ce que tu choisis, et ne supprime ou ne déplace rien sans ta confirmation. " +
                "Le Play Store le réserve à peu d’apps ; Oli est installé hors Play Store, Android te le demande donc directement.",
                color = Oc.Muted, fontSize = 13.sp, modifier = Modifier.padding(top = 4.dp, bottom = 8.dp))
            SecondaryButton("Autoriser dans les Paramètres", {
                runCatching {
                    context.startActivity(Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, Uri.parse("package:" + context.packageName))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                }
            })
        }
    }
}

@Composable
private fun CleanTab() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var hasMedia by remember { mutableStateOf(Phone.hasMedia(context)) }
    var hasAll by remember { mutableStateOf(Phone.hasAllFiles(context)) }
    var storage by remember { mutableStateOf(Phone.storage(context)) }
    var result by remember { mutableStateOf<Map<CleanCategory, List<Candidate>>?>(null) }
    var scanning by remember { mutableStateOf(false) }
    var checked by remember { mutableStateOf(setOf<String>()) }
    var open by remember { mutableStateOf(setOf<CleanCategory>()) }
    var confirm by remember { mutableStateOf(false) }
    var pendingMediaBytes by remember { mutableStateOf(0L) }
    var done by remember { mutableStateOf<String?>(null) }

    fun scan() {
        scanning = true
        scope.launch {
            val items = Phone.scan(context)
            val r = withContext(Dispatchers.IO) { Cleanup.classify(items, System.currentTimeMillis()) { Phone.hash(context, it) } }
            result = r; checked = emptySet(); scanning = false
            storage = Phone.storage(context)
        }
    }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(Unit) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            hasMedia = Phone.hasMedia(context); hasAll = Phone.hasAllFiles(context)
        }
    }
    val askMedia = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        hasMedia = Phone.hasMedia(context); if (hasMedia) scan()
    }
    val deleteMedia = rememberLauncherForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) { r ->
        if (r.resultCode == Activity.RESULT_OK && pendingMediaBytes > 0) {
            val freed = pendingMediaBytes
            scope.launch { GameStore(context).record(GameEvent.PHONE_CLEANED, freed = freed) }
            done = "${Cleanup.human(freed)} libérés de plus. Merci !"
        }
        pendingMediaBytes = 0
        scan()
    }

    storage?.let { s ->
        Text("Stockage", color = Oc.Text, fontSize = 17.sp, fontWeight = FontWeight.Bold)
        LinearProgressIndicator(progress = { s.used.toFloat() / s.total.coerceAtLeast(1) }, color = Oc.Tomato, trackColor = Oc.CardBorder,
            modifier = Modifier.fillMaxWidth().height(8.dp).padding(top = 6.dp))
        Text("${Cleanup.human(s.free)} libres sur ${Cleanup.human(s.total)}", color = Oc.Muted, fontSize = 13.sp, modifier = Modifier.padding(top = 4.dp))
    }
    TextButton(onClick = { runCatching { context.startActivity(Intent(Settings.ACTION_INTERNAL_STORAGE_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) } }) {
        Text("Vider le cache des apps (réglages de stockage)", color = Oc.Tomato)
    }
    HelpText("Android ne permet pas à une app de vider le cache des autres : le réglage est à un tap.")
    done?.let { Text(it, color = Oc.Ok, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(vertical = 6.dp)) }

    if (!hasMedia) {
        HelpText("Pour trouver les doublons, les vieilles captures et les gros fichiers, Oli doit lire tes photos et vidéos (sans rien envoyer nulle part).")
        PrimaryButton("Autoriser l’accès aux photos", { askMedia.launch(Phone.mediaPermissions()) })
        return
    }
    if (!hasAll && Build.VERSION.SDK_INT >= 30) {
        AllFilesCard("Pour les vieux téléchargements et les APK oubliés, Android demande cet accès.")
        Spacer(Modifier.height(12.dp))
    }
    PrimaryButton(if (scanning) "J’analyse…" else if (result == null) "Analyser le téléphone" else "Analyser à nouveau", ::scan, busy = scanning)
    Spacer(Modifier.height(12.dp))

    val r = result ?: return
    if (r.isEmpty()) { Text("Rien à nettoyer, tout est propre !", color = Oc.Ok, fontSize = 15.sp); return }
    r.forEach { (cat, list) ->
        val total = list.sumOf { it.item.size }
        Surface(color = Oc.Card, shape = RoundedCornerShape(16.dp), border = BorderStroke(1.dp, Oc.CardBorder),
            modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp).animateContentSize()) {
            Column(Modifier.padding(12.dp)) {
                Row(Modifier.fillMaxWidth().clickable { open = if (cat in open) open - cat else open + cat }, verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text("${cat.title} · ${list.size}", color = Oc.Text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                        Text("${Cleanup.human(total)} · ${cat.help}", color = Oc.Muted, fontSize = 12.sp)
                    }
                    val all = list.all { it.item.id in checked }
                    TextButton(onClick = { checked = if (all) checked - list.map { it.item.id }.toSet() else checked + list.map { it.item.id } }) {
                        Text(if (all) "Tout décocher" else "Tout cocher", color = Oc.Tomato, fontSize = 13.sp)
                    }
                }
                if (cat in open) list.take(200).forEach { c ->
                    Row(Modifier.fillMaxWidth().clickable { checked = if (c.item.id in checked) checked - c.item.id else checked + c.item.id },
                        verticalAlignment = Alignment.CenterVertically) {
                        Checkbox(checked = c.item.id in checked, onCheckedChange = { on -> checked = if (on) checked + c.item.id else checked - c.item.id },
                            colors = CheckboxDefaults.colors(checkedColor = Oc.Tomato, checkmarkColor = Oc.Bg, uncheckedColor = Oc.Muted))
                        Column(Modifier.weight(1f)) {
                            Text(c.item.name, color = Oc.Text, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(listOf(Cleanup.human(c.item.size), c.item.path, c.note).filter { it.isNotBlank() }.joinToString(" · "),
                                color = Oc.Muted, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
            }
        }
    }
    val selected = r.values.flatten().filter { it.item.id in checked }
    if (selected.isNotEmpty()) {
        Spacer(Modifier.height(8.dp))
        PrimaryButton("Supprimer ${selected.size} fichier${if (selected.size > 1) "s" else ""} (${Cleanup.human(selected.sumOf { it.item.size })})", { confirm = true })
    }
    if (confirm) {
        AlertDialog(
            onDismissRequest = { confirm = false },
            containerColor = Oc.Card,
            title = { Text("Supprimer ${selected.size} fichier${if (selected.size > 1) "s" else ""} ?", color = Oc.Text) },
            text = { Text("C’est définitif. Pour les photos et vidéos, Android te demandera aussi de confirmer.", color = Oc.Muted) },
            confirmButton = {
                TextButton(onClick = {
                    confirm = false
                    scope.launch {
                        val items = selected.map { it.item }
                        val (freed, sender) = Phone.delete(context, items)
                        if (freed > 0) {
                            GameStore(context).record(GameEvent.PHONE_CLEANED, freed = freed)
                            done = "${Cleanup.human(freed)} libérés. Bien joué !"
                        }
                        if (sender != null) {
                            pendingMediaBytes = items.filter { it.id.startsWith("content://") }.sumOf { it.size }
                            deleteMedia.launch(IntentSenderRequest.Builder(sender).build())
                        } else scan()
                    }
                }) { Text("Supprimer", color = Oc.Down, fontWeight = FontWeight.Bold) }
            },
            dismissButton = { TextButton(onClick = { confirm = false }) { Text("Annuler", color = Oc.Text) } },
        )
    }
}

/** Rangement : Téléchargements triés par type, captures renommées par date, rappel « mode avion du soir ». */
@Composable
fun TidyScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var hasAll by remember { mutableStateOf(Phone.hasAllFiles(context)) }
    var plan by remember { mutableStateOf<Phone.TidyPlan?>(null) }
    var confirm by remember { mutableStateOf(false) }
    var done by remember { mutableStateOf<String?>(null) }
    var evening by remember { mutableStateOf(AutomationPrefs(context).isOn(AutomationPrefs.Key.EVENING)) }
    val askLegacy = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { hasAll = Phone.hasAllFiles(context) }

    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(Unit) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            hasAll = Phone.hasAllFiles(context)
            if (hasAll) plan = Phone.tidyPlan()
        }
    }

    Column(Modifier.fillMaxSize().background(Oc.Bg).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp)) {
        ScreenHeader("Rangement", onBack)
        HelpText("Je te montre l’avant / après, tu valides, je range. Rien n’est supprimé.", Modifier.padding(top = 4.dp))
        done?.let { Text(it, color = Oc.Ok, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(bottom = 8.dp)) }

        if (!hasAll) {
            if (Build.VERSION.SDK_INT >= 30) AllFilesCard("Pour déplacer les fichiers de Téléchargements dans des sous-dossiers, Android exige cet accès.")
            else PrimaryButton("Autoriser l’accès au stockage", { askLegacy.launch(Phone.mediaPermissions()) })
        } else {
            val p = plan
            when {
                p == null -> Text("Je regarde tes dossiers…", color = Oc.Muted)
                p.all.isEmpty() -> Text("Tout est déjà rangé. Impeccable !", color = Oc.Ok, fontSize = 15.sp)
                else -> {
                    MovesBlock("Téléchargements → sous-dossiers", p.downloads)
                    MovesBlock("Captures d’écran renommées par date", p.screenshots)
                    Spacer(Modifier.height(8.dp))
                    PrimaryButton("Ranger ${p.all.size} fichier${if (p.all.size > 1) "s" else ""}", { confirm = true })
                }
            }
        }

        Spacer(Modifier.height(24.dp))
        SectionLabel("Mode avion du soir")
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Un rappel à 22 h pour couper le téléphone. Android ne laisse aucune app activer le mode avion elle-même : la notification ouvre le réglage.",
                color = Oc.Muted, fontSize = 13.sp, modifier = Modifier.weight(1f))
            Spacer(Modifier.width(12.dp))
            Switch(checked = evening, onCheckedChange = {
                evening = it
                AutomationPrefs(context).set(AutomationPrefs.Key.EVENING, it)
                Alarms.scheduleEvening(context)
            }, colors = SwitchDefaults.colors(checkedTrackColor = Oc.Tomato, checkedThumbColor = Oc.Bg))
        }
        Spacer(Modifier.height(32.dp))
    }

    val p = plan
    if (confirm && p != null) {
        AlertDialog(
            onDismissRequest = { confirm = false },
            containerColor = Oc.Card,
            title = { Text("Ranger ${p.all.size} fichier${if (p.all.size > 1) "s" else ""} ?", color = Oc.Text) },
            text = { Text("Les fichiers sont déplacés ou renommés comme dans l’aperçu. Aucun n’est supprimé.", color = Oc.Muted) },
            confirmButton = {
                TextButton(onClick = {
                    confirm = false
                    scope.launch {
                        val n = Phone.applyTidy(context, p.all)
                        done = "$n fichier${if (n > 1) "s" else ""} rangé${if (n > 1) "s" else ""}."
                        if (n > 0) GameStore(context).record(GameEvent.PHONE_TIDIED)
                        plan = Phone.tidyPlan()
                    }
                }) { Text("Ranger", color = Oc.Tomato, fontWeight = FontWeight.Bold) }
            },
            dismissButton = { TextButton(onClick = { confirm = false }) { Text("Annuler", color = Oc.Text) } },
        )
    }
}

@Composable
private fun MovesBlock(title: String, moves: List<Move>) {
    if (moves.isEmpty()) return
    SectionLabel("$title · ${moves.size}", Modifier.padding(top = 10.dp))
    Surface(color = Oc.Card, shape = RoundedCornerShape(16.dp), border = BorderStroke(1.dp, Oc.CardBorder), modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp)) {
            moves.take(40).forEach { m ->
                Text(m.from.substringAfterLast('/'), color = Oc.Muted, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text("→ " + m.to.substringAfterLast('/').let { if (m.label == "Captures") it else "${m.label}/$it" },
                    color = Oc.Text, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(bottom = 6.dp))
            }
            if (moves.size > 40) Text("… et ${moves.size - 40} autres", color = Oc.Muted, fontSize = 12.sp)
        }
    }
}
