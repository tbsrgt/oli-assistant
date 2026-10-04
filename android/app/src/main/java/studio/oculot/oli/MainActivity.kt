package studio.oculot.oli

import android.Manifest
import android.animation.AnimatorSet
import android.animation.ObjectAnimator
import android.app.KeyguardManager
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.view.View
import android.view.animation.AccelerateInterpolator
import androidx.activity.SystemBarStyle
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_WEAK
import androidx.biometric.BiometricManager.Authenticators.DEVICE_CREDENTIAL
import androidx.biometric.BiometricPrompt
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.toArgb
import androidx.core.content.ContextCompat
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.fragment.app.FragmentActivity
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import studio.oculot.oli.core.Automations
import studio.oculot.oli.core.GameEvent
import studio.oculot.oli.core.GameState
import studio.oculot.oli.core.GameUpdate
import studio.oculot.oli.core.Sites
import studio.oculot.oli.data.AutomationPrefs
import studio.oculot.oli.data.ChatStore
import studio.oculot.oli.data.GameStore
import studio.oculot.oli.data.MemoryStore
import studio.oculot.oli.data.Phone
import studio.oculot.oli.data.Repository
import studio.oculot.oli.data.Settings
import studio.oculot.oli.overlay.OverlayService
import studio.oculot.oli.ui.AutomationsScreen
import studio.oculot.oli.ui.Celebration
import studio.oculot.oli.ui.ChatScreen
import studio.oculot.oli.ui.ClaudeCodeScreen
import studio.oculot.oli.ui.ConnectionsScreen
import studio.oculot.oli.ui.DetailScreen
import studio.oculot.oli.ui.FloatingIntroScreen
import studio.oculot.oli.ui.GameScreen
import studio.oculot.oli.ui.HomeExtras
import studio.oculot.oli.ui.HomeScreen
import studio.oculot.oli.ui.LockScreen
import studio.oculot.oli.ui.Oc
import studio.oculot.oli.ui.OliTheme
import studio.oculot.oli.ui.PhoneScreen
import studio.oculot.oli.ui.TidyScreen
import studio.oculot.oli.ui.TodayState
import studio.oculot.oli.work.Alarms
import studio.oculot.oli.work.Automator
import studio.oculot.oli.work.Notifier
import studio.oculot.oli.work.SiteWatchWorker

// FragmentActivity (et non ComponentActivity) : BiometricPrompt en a besoin.
class MainActivity : FragmentActivity() {

    private val askNotifications = registerForActivityResult(ActivityResultContracts.RequestPermission()) { }
    private var credentialCallback: ((Boolean) -> Unit)? = null
    private val confirmCredential = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { r ->
        prompting = false
        val cb = credentialCallback; credentialCallback = null
        cb?.invoke(r.resultCode == RESULT_OK)
    }

    private var locked by mutableStateOf(true)
    private var lockMessage by mutableStateOf<String?>(null)
    private var noLockWarning by mutableStateOf(false)
    private var askPrefill by mutableStateOf<String?>(null)
    private var screen by mutableStateOf("home")
    /** Confirmation simple quand le téléphone n'a aucun verrouillage (pour « Autoriser » dans Claude Code). */
    private var plainConfirm by mutableStateOf<Pair<String, () -> Unit>?>(null)
    private var prompting = false
    private var splashDone = false
    private val createdAt = SystemClock.uptimeMillis()

    override fun onCreate(savedInstanceState: Bundle?) {
        // Écran de lancement : Oli descend comme une vague et cligne des yeux (icône animée, Android 12+).
        val splash = installSplashScreen()
        super.onCreate(savedInstanceState)
        // Pas d'attente artificielle : on garde l'écran seulement le temps que l'animation se lise (≤ 850 ms).
        splash.setKeepOnScreenCondition {
            Build.VERSION.SDK_INT >= 31 && savedInstanceState == null && SystemClock.uptimeMillis() - createdAt < SPLASH_MIN_MS
        }
        splash.setOnExitAnimationListener { provider ->
            val v = provider.view
            AnimatorSet().apply {
                playTogether(
                    ObjectAnimator.ofFloat(v, View.ALPHA, 1f, 0f),
                    ObjectAnimator.ofFloat(v, View.TRANSLATION_Y, 0f, -v.height * 0.08f),
                )
                duration = 260
                interpolator = AccelerateInterpolator()
                doOnEndCompat { provider.remove(); onSplashGone() }
                start()
            }
        }
        if (savedInstanceState != null || Build.VERSION.SDK_INT < 31) window.decorView.post { onSplashGone() }

        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(Oc.Bg.toArgb()),
            navigationBarStyle = SystemBarStyle.dark(Oc.Bg.toArgb()),
        )
        Notifier.createChannels(this)
        SiteWatchWorker.schedule(this)
        Alarms.scheduleBriefing(this)
        Alarms.scheduleEvening(this)
        if (AutomationPrefs(this).isOn(AutomationPrefs.Key.FLOATING)) OverlayService.start(this)
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            askNotifications.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
        locked = Automations.needsUnlock(lastBackgroundAtMs, System.currentTimeMillis(), unlockedOnce)
        handleIntent(intent)

        val repo = Repository(applicationContext)
        val chatStore = ChatStore(applicationContext)
        val game = GameStore(applicationContext)
        val memory = MemoryStore(applicationContext)

        setContent {
            OliTheme {
                var settings by remember { mutableStateOf(repo.settings()) }
                var state by remember { mutableStateOf(TodayState(sites = repo.cachedChecks(), sitesConfigured = settings.sites.isNotBlank())) }
                var claudeLine by remember { mutableStateOf(memory.claudeLine()) }
                var claudeWaiting by remember { mutableStateOf(memory.claudeWaiting()) }
                var securityScore by remember { mutableStateOf(memory.securityScore()) }
                val gameState by game.state.collectAsState(initial = GameState())
                var celebration by remember { mutableStateOf<GameUpdate?>(null) }
                val scope = rememberCoroutineScope()

                suspend fun refresh() {
                    state = state.copy(loading = true, sitesConfigured = settings.sites.isNotBlank())
                    coroutineScope {
                        val espace = async { repo.loadEspace() }
                        val agenda = async { repo.loadAgenda() }
                        val claude = async { if (settings.mac != null) Automator.claudeCheck(applicationContext, notify = false) else null }
                        state = state.copy(espace = espace.await())
                        // Les sites livrés de l'espace client rejoignent la surveillance : on attend l'espace.
                        val run = repo.checkSites()
                        state = state.copy(sites = run.checks, agenda = agenda.await(),
                            sitesConfigured = settings.sites.isNotBlank() || run.checks.isNotEmpty())
                        claude.await()
                        claudeLine = if (settings.mac != null) memory.claudeLine() else null
                        claudeWaiting = if (settings.mac != null) memory.claudeWaiting() else 0
                        Automator.afterRefresh(applicationContext, state.espace, state.agenda, run)
                        OverlayService.refresh(applicationContext)
                    }
                    state = state.copy(loading = false)
                }

                fun changed() {
                    val before = connectedCount(settings)
                    settings = repo.settings()
                    val after = connectedCount(settings)
                    if (after > before) scope.launch { game.record(GameEvent.CONNECTED, allConnected = after == 4) }
                    scope.launch { refresh() }
                }

                LaunchedEffect(Unit) { refresh() }
                LaunchedEffect(Unit) { GameStore.celebrationsFlow.collect { celebration = it } }
                LaunchedEffect(screen) {
                    if (screen == "briefing") { screen = "home"; game.record(GameEvent.BRIEFING_READ) }
                    if (screen == "home") securityScore = memory.securityScore()
                }

                // Transition d'entrée (une demi-seconde) entre l'écran de lancement et l'accueil.
                val enter = remember { Animatable(if (savedInstanceState == null) 0f else 1f) }
                LaunchedEffect(Unit) { enter.animateTo(1f, tween(520)) }

                Box(
                    Modifier.fillMaxSize().background(Oc.Bg).safeDrawingPadding()
                        .graphicsLayer { alpha = enter.value; scaleX = 0.96f + 0.04f * enter.value; scaleY = scaleX },
                ) {
                    if (locked) {
                        LockScreen(lockMessage, onRetry = { authenticate() })
                        return@Box
                    }
                    val home = { screen = "home" }
                    AnimatedContent(targetState = screen, transitionSpec = { fadeIn(tween(180)) togetherWith fadeOut(tween(120)) }, label = "écran") { s ->
                        when (s) {
                            "connexions", "toutconnecter" -> {
                                BackHandler(onBack = home)
                                ConnectionsScreen(repo, settings, onChanged = ::changed, onBack = home,
                                    onAutomations = { screen = "automatisations" }, wizard = s == "toutconnecter")
                            }
                            "automatisations" -> {
                                BackHandler { screen = "connexions" }
                                AutomationsScreen(onBack = { screen = "connexions" }, onChanged = ::changed,
                                    onFloatingIntro = { screen = "flottant" })
                            }
                            "flottant" -> {
                                BackHandler { screen = "automatisations" }
                                FloatingIntroScreen(onBack = { screen = "automatisations" })
                            }
                            "chat" -> {
                                BackHandler(onBack = home)
                                ChatScreen(repo, chatStore, paired = settings.mac != null, macName = settings.mac?.name,
                                    prefill = askPrefill, onPrefillUsed = { askPrefill = null },
                                    onBack = home, onConnect = { screen = "connexions" },
                                    onAsked = { scope.launch { game.record(GameEvent.ASKED_OLI) } })
                            }
                            "claude" -> {
                                BackHandler(onBack = home)
                                ClaudeCodeScreen(repo, paired = settings.mac != null, onBack = home, onConnect = { screen = "connexions" },
                                    confirm = ::confirmSensitive,
                                    onDecided = { scope.launch { game.record(GameEvent.CLAUDE_DECISION) } })
                            }
                            "sites", "projets", "agenda" -> {
                                BackHandler(onBack = home)
                                DetailScreen(s, state, onBack = home, onRefresh = { if (!state.loading) scope.launch { refresh() } },
                                    onSettings = { screen = "connexions" })
                            }
                            "telephone" -> {
                                BackHandler(onBack = home)
                                PhoneScreen(onBack = home, onTidy = { screen = "rangement" })
                            }
                            "rangement" -> {
                                BackHandler(onBack = home)
                                TidyScreen(onBack = home)
                            }
                            "defis" -> {
                                BackHandler(onBack = home)
                                GameScreen(gameState, game, onBack = home)
                            }
                            else -> HomeScreen(
                                state = state,
                                extras = HomeExtras(
                                    game = gameState,
                                    claudeLine = claudeLine,
                                    claudeWaiting = claudeWaiting,
                                    paired = settings.mac != null,
                                    securityScore = securityScore,
                                    freeBytes = remember { Phone.storage(applicationContext)?.free },
                                    missingConnections = 4 - connectedCount(settings),
                                    noLockWarning = noLockWarning,
                                ),
                                onRefresh = { if (!state.loading) scope.launch { refresh() } },
                                onOpen = { screen = it },
                            )
                        }
                    }
                    celebration?.let { Celebration(it, onDismiss = { celebration = null }) }
                    plainConfirm?.let { (reason, ok) ->
                        AlertDialog(
                            onDismissRequest = { plainConfirm = null },
                            containerColor = Oc.Card,
                            title = { Text("Tu confirmes ?", color = Oc.Text) },
                            text = { Text("$reason. (Ton téléphone n’a pas de verrouillage : je ne peux pas demander ton empreinte.)", color = Oc.Muted) },
                            confirmButton = { TextButton(onClick = { plainConfirm = null; ok() }) { Text("Autoriser", color = Oc.Tomato) } },
                            dismissButton = { TextButton(onClick = { plainConfirm = null }) { Text("Annuler", color = Oc.Text) } },
                        )
                    }
                }
            }
        }
    }

    private fun connectedCount(s: Settings): Int = listOf(
        s.espaceToken.isNotBlank(), s.icsUrl.isNotBlank(),
        Sites.targets(s.sites, Repository(applicationContext).espaceSites()).isNotEmpty(), s.mac != null,
    ).count { it }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(i: Intent?) {
        if (i == null) return
        i.getStringExtra(EXTRA_ASK)?.let { askPrefill = it; screen = "chat"; i.removeExtra(EXTRA_ASK) }
        i.getStringExtra(EXTRA_SCREEN)?.let { screen = it; i.removeExtra(EXTRA_SCREEN) }
    }

    private fun onSplashGone() {
        if (splashDone) return
        splashDone = true
        // L'animation passe d'abord, le verrou ensuite.
        if (locked && !prompting) authenticate()
    }

    override fun onStart() {
        super.onStart()
        if (Automations.needsUnlock(lastBackgroundAtMs, System.currentTimeMillis(), unlockedOnce)) locked = true
    }

    override fun onResume() {
        super.onResume()
        if (locked && !prompting && splashDone) authenticate()
    }

    override fun onStop() {
        super.onStop()
        // Pendant la saisie du code (activité système sur les anciens Android), on ne compte pas.
        if (!prompting) lastBackgroundAtMs = System.currentTimeMillis()
    }

    private fun unlock() {
        unlockedOnce = true
        lastBackgroundAtMs = null
        locked = false
        lockMessage = null
    }

    /** Empreinte, visage ou code du téléphone. Sans verrouillage configuré : on laisse entrer avec un conseil. */
    private fun authenticate() {
        if (prompting) return
        if (getSystemService(KeyguardManager::class.java)?.isDeviceSecure != true) {
            noLockWarning = true
            unlock(); return
        }
        noLockWarning = false
        prompt("Déverrouiller Oli", "Empreinte, visage ou code du téléphone") { ok, message ->
            if (ok) unlock() else lockMessage = message
        }
    }

    /** Confirmation avant une action sensible (autoriser Claude Code) : biométrie ou code du téléphone. */
    private fun confirmSensitive(reason: String, onOk: () -> Unit) {
        if (getSystemService(KeyguardManager::class.java)?.isDeviceSecure != true) { plainConfirm = reason to onOk; return }
        prompt("Autoriser Claude ?", reason) { ok, _ -> if (ok) onOk() }
    }

    private fun prompt(title: String, subtitle: String, done: (Boolean, String?) -> Unit) {
        if (prompting) return
        if (Build.VERSION.SDK_INT < 28) {
            // Android 8 : la fenêtre d'empreinte de la bibliothèque exige un thème AppCompat ;
            // on passe par l'écran de confirmation du système (code, schéma ou empreinte).
            @Suppress("DEPRECATION")
            val i = getSystemService(KeyguardManager::class.java)?.createConfirmDeviceCredentialIntent(title, subtitle)
            if (i == null) { done(true, null); return }
            prompting = true
            credentialCallback = { ok -> done(ok, if (ok) null else "Touche « Réessayer » quand tu veux entrer.") }
            confirmCredential.launch(i)
            return
        }
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .setSubtitle(subtitle)
            .setAllowedAuthenticators(BIOMETRIC_WEAK or DEVICE_CREDENTIAL)
            .build()
        val p = BiometricPrompt(this, ContextCompat.getMainExecutor(this), object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                prompting = false
                done(true, null)
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                prompting = false
                done(false, when (errorCode) {
                    BiometricPrompt.ERROR_USER_CANCELED, BiometricPrompt.ERROR_NEGATIVE_BUTTON, BiometricPrompt.ERROR_CANCELED ->
                        "Touche « Réessayer » quand tu veux entrer."
                    BiometricPrompt.ERROR_LOCKOUT, BiometricPrompt.ERROR_LOCKOUT_PERMANENT ->
                        "Trop d’essais. Patiente un peu, puis réessaie avec le code du téléphone."
                    else -> errString.toString()
                })
            }
        })
        prompting = true
        try {
            p.authenticate(info)
        } catch (e: Exception) {
            prompting = false
            done(false, "Impossible d’afficher le déverrouillage. Touche « Réessayer ».")
        }
    }

    companion object {
        const val EXTRA_ASK = "studio.oculot.oli.DEMANDER"
        const val EXTRA_SCREEN = "studio.oculot.oli.ECRAN"
        private const val SPLASH_MIN_MS = 850L

        // Vivent avec le processus : un démarrage à froid repart verrouillé, une rotation non.
        private var unlockedOnce = false
        private var lastBackgroundAtMs: Long? = null
    }
}

private fun AnimatorSet.doOnEndCompat(block: () -> Unit) {
    addListener(object : android.animation.AnimatorListenerAdapter() {
        override fun onAnimationEnd(animation: android.animation.Animator) = block()
    })
}
