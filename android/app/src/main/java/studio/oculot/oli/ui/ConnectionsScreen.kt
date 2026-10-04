package studio.oculot.oli.ui

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioButtonDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import com.journeyapps.barcodescanner.ScanContract
import com.journeyapps.barcodescanner.ScanOptions
import kotlinx.coroutines.launch
import studio.oculot.oli.core.AgendaApi
import studio.oculot.oli.core.AgendaLire
import studio.oculot.oli.core.AgendaMember
import studio.oculot.oli.core.MacLink
import studio.oculot.oli.core.MacStatus
import studio.oculot.oli.core.MemberChoice
import studio.oculot.oli.core.Sites
import studio.oculot.oli.data.Repository
import studio.oculot.oli.data.Settings

private enum class Service { ESPACE, AGENDA, SITES, CLAUDE }

/** Réglages → Connexions : une ligne par service, un bouton « Se connecter » ou « Gérer ». */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ConnectionsScreen(
    repo: Repository,
    settings: Settings,
    onChanged: () -> Unit,
    onBack: () -> Unit,
    onAutomations: () -> Unit,
) {
    var open by remember { mutableStateOf<Service?>(null) }
    val espaceSites = remember(settings) { repo.espaceSites() }
    val siteCount = remember(settings, espaceSites) { Sites.targets(settings.sites, espaceSites).size }

    Column(
        Modifier.fillMaxSize().background(Oc.Bg).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp),
    ) {
        ScreenHeader("Réglages", onBack)
        HelpText("Un bouton par service. Oli vérifie que ça marche avant d’enregistrer, et tout reste chiffré sur ce téléphone.",
            Modifier.padding(top = 4.dp, bottom = 8.dp))

        SectionLabel("Connexions", Modifier.padding(top = 8.dp))
        Card {
            ServiceRow("Espace client", if (settings.espaceToken.isNotBlank()) "Connecté ✓" else "Projets et sites livrés",
                settings.espaceToken.isNotBlank()) { open = Service.ESPACE }
            Divider()
            ServiceRow("Agenda",
                when {
                    settings.icsUrl.isBlank() -> "Tes rendez-vous et leurs rappels"
                    settings.agendaMemberName.isNotBlank() -> "Connecté ✓ · ${settings.agendaMemberName}"
                    else -> "Connecté ✓ · lien iCal"
                },
                settings.icsUrl.isNotBlank()) { open = Service.AGENDA }
            Divider()
            ServiceRow("Sites", if (siteCount > 0) "Je surveille $siteCount site${if (siteCount > 1) "s" else ""}" else "Les sites à surveiller",
                siteCount > 0, connectLabel = "Ajouter") { open = Service.SITES }
            Divider()
            ServiceRow("Claude", settings.mac?.let { "Connecté ✓ · ${it.name}" } ?: "Via Oli sur ton Mac",
                settings.mac != null) { open = Service.CLAUDE }
        }

        Spacer(Modifier.height(24.dp))
        SectionLabel("Automatisations")
        Card {
            Row(
                Modifier.fillMaxWidth().clickable(onClick = onAutomations).padding(horizontal = 16.dp, vertical = 16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(Modifier.weight(1f)) {
                    Text("Briefing, rappels, alertes", color = Oc.Text, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                    Text("Ce qu’Oli fait tout seul pour toi", color = Oc.Muted, fontSize = 13.sp)
                }
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = Oc.Muted)
            }
        }
        Spacer(Modifier.height(32.dp))
    }

    val current = open
    if (current != null) {
        val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ModalBottomSheet(
            onDismissRequest = { open = null },
            sheetState = sheetState,
            containerColor = Oc.Card,
            contentColor = Oc.Text,
        ) {
            Column(
                Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp)
                    .padding(bottom = 24.dp).navigationBarsPadding().imePadding(),
            ) {
                val close = { open = null }
                when (current) {
                    Service.ESPACE -> EspaceSheet(repo, onChanged, close)
                    Service.AGENDA -> AgendaSheet(repo, onChanged, close)
                    Service.SITES -> SitesSheet(repo, espaceSites, onChanged, close)
                    Service.CLAUDE -> ClaudeSheet(repo, onChanged, close)
                }
            }
        }
    }
}

@Composable
private fun Card(content: @Composable () -> Unit) {
    Surface(color = Oc.Card, shape = RoundedCornerShape(18.dp), border = BorderStroke(1.dp, Oc.CardBorder), modifier = Modifier.fillMaxWidth()) {
        Column { content() }
    }
}

@Composable
private fun Divider() {
    Box(Modifier.fillMaxWidth().padding(horizontal = 16.dp).height(1.dp).background(Oc.CardBorder))
}

@Composable
private fun ServiceRow(name: String, subtitle: String, connected: Boolean, connectLabel: String = "Se connecter", onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(10.dp).background(if (connected) Oc.Ok else Oc.Unknown, CircleShape))
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(name, color = Oc.Text, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
            Text(subtitle, color = if (connected) Oc.Ok else Oc.Muted, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Spacer(Modifier.width(8.dp))
        if (connected) {
            TextButton(onClick = onClick) { Text("Gérer", color = Oc.Tomato, fontWeight = FontWeight.SemiBold) }
        } else {
            Button(onClick = onClick, colors = ButtonDefaults.buttonColors(containerColor = Oc.Tomato, contentColor = Oc.Bg)) {
                Text(connectLabel, fontWeight = FontWeight.Bold)
            }
        }
    }
}

@Composable
private fun SheetTitle(title: String, subtitle: String? = null) {
    Text(title, color = Oc.Text, fontSize = 22.sp, fontWeight = FontWeight.Bold)
    if (subtitle != null) Text(subtitle, color = Oc.Muted, fontSize = 14.sp, modifier = Modifier.padding(top = 4.dp, bottom = 12.dp))
    else Spacer(Modifier.height(12.dp))
}

/** Bloc commun « Connecté ✓ » + Déconnecter + Fermer. */
@Composable
private fun ConnectedBlock(detail: String?, onDisconnect: () -> Unit, onClose: () -> Unit, extra: @Composable () -> Unit = {}) {
    SuccessText("Connecté ✓")
    if (detail != null) Text(detail, color = Oc.Muted, fontSize = 14.sp, modifier = Modifier.padding(bottom = 12.dp))
    extra()
    Spacer(Modifier.height(8.dp))
    PrimaryButton("Fermer", onClose)
    Spacer(Modifier.height(10.dp))
    SecondaryButton("Déconnecter", onDisconnect, danger = true)
}

// Espace client

@Composable
private fun EspaceSheet(repo: Repository, onChanged: () -> Unit, close: () -> Unit) {
    val scope = rememberCoroutineScope()
    var connected by remember { mutableStateOf(repo.settings().espaceToken.isNotBlank()) }
    var editing by remember { mutableStateOf(!connected) }
    var code by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    SheetTitle("Espace client", "Les projets d’espace.oculot.studio et les sites livrés, sur ton téléphone.")
    if (!editing) {
        ConnectedBlock("Oli lit les projets et surveille les sites livrés.", onDisconnect = {
            repo.saveSettings(repo.settings().copy(espaceToken = ""))
            connected = false; editing = true; onChanged()
        }, onClose = close) {
            TextButton(onClick = { editing = true }) { Text("Changer de code", color = Oc.Tomato) }
        }
        return
    }
    OliField(code, { code = it.trim(); error = null }, "Code d’équipe", secret = true)
    HelpText("Le code que l’équipe utilise pour l’espace client.", Modifier.padding(top = 6.dp))
    ErrorText(error)
    PrimaryButton(if (busy) "Je vérifie…" else "Se connecter", busy = busy, enabled = code.isNotBlank(), onClick = {
        busy = true; error = null
        scope.launch {
            val problem = repo.verifyEspace(code)
            busy = false
            if (problem == null) {
                repo.saveSettings(repo.settings().copy(espaceToken = code))
                connected = true; editing = false; code = ""; onChanged()
            } else error = problem
        }
    })
}

// Agenda

@Composable
private fun AgendaSheet(repo: Repository, onChanged: () -> Unit, close: () -> Unit) {
    val scope = rememberCoroutineScope()
    val saved = remember { repo.settings() }
    var connectedName by remember { mutableStateOf(if (saved.icsUrl.isNotBlank()) saved.agendaMemberName.ifBlank { "lien iCal" } else null) }
    var editing by remember { mutableStateOf(connectedName == null) }
    var code by remember { mutableStateOf("") }
    var firstName by remember { mutableStateOf("") }
    var lire by remember { mutableStateOf<AgendaLire?>(null) }
    var candidates by remember { mutableStateOf<List<AgendaMember>>(emptyList()) }
    var picked by remember { mutableStateOf<String?>(null) }
    var showIcs by remember { mutableStateOf(false) }
    var ics by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    fun finish(member: AgendaMember) {
        busy = true; error = null
        scope.launch {
            val link = repo.agendaLink(code, member.id)
            busy = false
            link.onSuccess { url ->
                repo.saveSettings(repo.settings().copy(icsUrl = url, agendaCode = code.trim(),
                    agendaMemberId = member.id, agendaMemberName = member.name))
                connectedName = member.name; editing = false; lire = null; code = ""; onChanged()
            }.onFailure { error = it.message }
        }
    }

    SheetTitle("Agenda", "Tes rendez-vous d’agenda.oculot.studio, avec un rappel 10 min avant.")

    if (!editing) {
        ConnectedBlock(connectedName?.let { if (it == "lien iCal") "Agenda relié par un lien iCal." else "Agenda de $it." },
            onDisconnect = {
                repo.saveSettings(repo.settings().copy(icsUrl = "", agendaCode = "", agendaMemberId = "", agendaMemberName = ""))
                connectedName = null; editing = true; onChanged()
            }, onClose = close) {
            TextButton(onClick = { editing = true; firstName = saved.agendaMemberName }) { Text("Changer de prénom ou de mot de passe", color = Oc.Tomato) }
        }
        return
    }

    val team = lire
    if (team == null) {
        OliField(code, { code = it; error = null }, "Mot de passe de l’agenda", secret = true)
        Spacer(Modifier.height(8.dp))
        OliField(firstName, { firstName = it }, "Ton prénom (facultatif)")
        ErrorText(error)
        Spacer(Modifier.height(8.dp))
        PrimaryButton(if (busy) "Je vérifie…" else "Continuer", busy = busy, enabled = code.isNotBlank(), onClick = {
            busy = true; error = null
            scope.launch {
                val r = repo.agendaLire(code)
                busy = false
                r.onSuccess { l ->
                    when (val c = AgendaApi.chooseMember(l, firstName)) {
                        is MemberChoice.Fixed -> finish(c.member)
                        is MemberChoice.Pick -> {
                            if (c.candidates.isEmpty()) error = "Personne à choisir dans l’équipe de l’agenda."
                            else { candidates = c.candidates; picked = c.preselected; lire = l }
                        }
                    }
                }.onFailure { error = it.message }
            }
        })
    } else {
        Text("Qui es-tu ?", color = Oc.Text, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(bottom = 4.dp))
        candidates.forEach { m ->
            Row(
                Modifier.fillMaxWidth().clickable { picked = m.id }.padding(vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                RadioButton(selected = picked == m.id, onClick = { picked = m.id },
                    colors = RadioButtonDefaults.colors(selectedColor = Oc.Tomato, unselectedColor = Oc.Muted))
                Box(Modifier.size(10.dp).background(parseColor(m.color) ?: Oc.Butter, CircleShape))
                Spacer(Modifier.width(10.dp))
                Text(m.name, color = Oc.Text, fontSize = 16.sp)
            }
        }
        ErrorText(error)
        Spacer(Modifier.height(8.dp))
        PrimaryButton(if (busy) "Je relie ton agenda…" else "C’est moi", busy = busy, enabled = picked != null, onClick = {
            candidates.firstOrNull { it.id == picked }?.let { finish(it) }
        })
        TextButton(onClick = { lire = null; error = null }) { Text("Revenir au mot de passe", color = Oc.Muted) }
    }

    Spacer(Modifier.height(16.dp))
    TextButton(onClick = { showIcs = !showIcs }) {
        Text(if (showIcs) "Masquer le lien iCal" else "Autre agenda ? Coller un lien iCal", color = Oc.Muted)
    }
    if (showIcs) {
        OliField(ics, { ics = it.trim(); error = null }, "Lien iCal", placeholder = "https://…/basic.ics", keyboard = KeyboardType.Uri)
        Spacer(Modifier.height(8.dp))
        SecondaryButton("Vérifier et enregistrer", onClick = {
            if (ics.isBlank() || busy) return@SecondaryButton
            busy = true; error = null
            scope.launch {
                val problem = repo.verifyIcs(ics)
                busy = false
                if (problem == null) {
                    repo.saveSettings(repo.settings().copy(icsUrl = ics, agendaCode = "", agendaMemberId = "", agendaMemberName = ""))
                    connectedName = "lien iCal"; editing = false; ics = ""; onChanged()
                } else error = problem
            }
        })
    }
}

private fun parseColor(hex: String): Color? = try {
    val h = hex.trim().removePrefix("#")
    if (h.length == 6) Color(("FF$h").toLong(16)) else null
} catch (_: Exception) { null }

// Sites

@Composable
private fun SitesSheet(repo: Repository, espaceSites: List<Pair<String, String>>, onChanged: () -> Unit, close: () -> Unit) {
    var text by remember { mutableStateOf(repo.settings().sites) }
    SheetTitle("Sites", "Une adresse par ligne. Je les vérifie toutes les 15 minutes et je te préviens en cas de panne.")
    OliField(text, { text = it }, "Sites à surveiller", placeholder = "oculot.studio\nexemple.fr", singleLine = false,
        keyboard = KeyboardType.Uri, minHeight = 150)
    if (espaceSites.isNotEmpty()) {
        Spacer(Modifier.height(14.dp))
        SectionLabel("Déjà suivis via l’espace client")
        espaceSites.forEach { (name, url) ->
            Text("• $name · ${Sites.host(url)}", color = Oc.Muted, fontSize = 14.sp, modifier = Modifier.padding(vertical = 2.dp))
        }
    }
    Spacer(Modifier.height(16.dp))
    PrimaryButton("Enregistrer", onClick = {
        repo.saveSettings(repo.settings().copy(sites = text))
        onChanged(); close()
    })
}

// Claude (jumelage avec le Mac)

@Composable
private fun ClaudeSheet(repo: Repository, onChanged: () -> Unit, close: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var pairing by remember { mutableStateOf(repo.settings().mac) }
    var editing by remember { mutableStateOf(pairing == null) }
    var status by remember { mutableStateOf<MacStatus?>(null) }
    var showPaste by remember { mutableStateOf(false) }
    var link by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    fun tryLink(raw: String) {
        val parsed = MacLink.parsePairLink(raw)
        val p = parsed.getOrElse { error = it.message; return }
        busy = true; error = null
        scope.launch {
            val r = repo.macStatus(p)
            busy = false
            r.onSuccess { st ->
                val name = st.name.ifBlank { p.name }
                repo.saveSettings(repo.settings().copy(macHost = p.host, macPort = p.port, macToken = p.token, macName = name))
                pairing = p.copy(name = name); status = st; editing = false; link = ""; onChanged()
            }.onFailure { error = it.message }
        }
    }

    val scan = rememberLauncherForActivityResult(ScanContract()) { result ->
        result.contents?.let { tryLink(it) }
    }
    fun launchScan() = scan.launch(ScanOptions().apply {
        setDesiredBarcodeFormats(ScanOptions.QR_CODE)
        setPrompt("Vise le QR code affiché sur ton Mac")
        setBeepEnabled(false)
        setOrientationLocked(false)
    })
    val askCamera = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) launchScan() else error = "Sans la caméra, colle le lien affiché sous le QR code."
    }

    SheetTitle("Claude", "Oli sur ton Mac fait tourner Claude avec ton abonnement. Ton téléphone lui pose les questions.")

    if (!editing) {
        val st = status
        ConnectedBlock(
            pairing?.name?.let { "Jumelé avec $it." },
            onDisconnect = {
                repo.saveSettings(repo.settings().copy(macHost = "", macPort = 0, macToken = "", macName = ""))
                pairing = null; status = null; editing = true; onChanged()
            },
            onClose = close,
        ) {
            if (st != null) {
                Text(
                    if (st.claude) "Claude est prêt" + (st.model.takeIf { it.isNotBlank() }?.let { " (modèle $it)" } ?: "") + "."
                    else "Oli répond, mais Claude n’est pas prêt sur ton Mac pour l’instant.",
                    color = if (st.claude) Oc.Ok else Oc.Butter, fontSize = 14.sp, modifier = Modifier.padding(bottom = 8.dp),
                )
            }
            ErrorText(error)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TextButton(onClick = {
                    val p = pairing ?: return@TextButton
                    busy = true; error = null
                    scope.launch {
                        repo.macStatus(p).onSuccess { status = it }.onFailure { error = it.message }
                        busy = false
                    }
                }) { Text(if (busy) "Je teste…" else "Tester", color = Oc.Tomato) }
                TextButton(onClick = { editing = true; error = null }) { Text("Rejumeler", color = Oc.Tomato) }
            }
        }
        return
    }

    Text("Sur ton Mac : Oli → Réglages → Connexions → Téléphone. Un QR code s’affiche, scanne-le.",
        color = Oc.Text, fontSize = 15.sp, modifier = Modifier.padding(bottom = 14.dp))
    ErrorText(error)
    PrimaryButton(if (busy) "Je contacte ton Mac…" else "Scanner le QR code", busy = busy, onClick = {
        error = null
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) launchScan()
        else askCamera.launch(Manifest.permission.CAMERA)
    })
    Spacer(Modifier.height(8.dp))
    TextButton(onClick = { showPaste = !showPaste }) {
        Text(if (showPaste) "Masquer" else "Pas de caméra ? Coller le lien", color = Oc.Muted)
    }
    if (showPaste) {
        OliField(link, { link = it.trim(); error = null }, "Lien de jumelage", placeholder = "oli://pair?…", keyboard = KeyboardType.Uri)
        Spacer(Modifier.height(8.dp))
        SecondaryButton("Se connecter", onClick = { if (link.isNotBlank() && !busy) tryLink(link) })
    }
    Text("Ton téléphone et ton Mac doivent être sur le même Wi-Fi.", color = Oc.Muted, fontSize = 13.sp, modifier = Modifier.padding(top = 12.dp))
}
