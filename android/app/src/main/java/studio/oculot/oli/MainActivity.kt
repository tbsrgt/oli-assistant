package studio.oculot.oli

import android.Manifest
import android.app.KeyguardManager
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.SystemBarStyle
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_WEAK
import androidx.biometric.BiometricManager.Authenticators.DEVICE_CREDENTIAL
import androidx.biometric.BiometricPrompt
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.toArgb
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import studio.oculot.oli.core.Automations
import studio.oculot.oli.data.ChatStore
import studio.oculot.oli.data.Repository
import studio.oculot.oli.ui.AutomationsScreen
import studio.oculot.oli.ui.ChatScreen
import studio.oculot.oli.ui.ConnectionsScreen
import studio.oculot.oli.ui.LockScreen
import studio.oculot.oli.ui.Oc
import studio.oculot.oli.ui.OliTheme
import studio.oculot.oli.ui.TodayScreen
import studio.oculot.oli.ui.TodayState
import studio.oculot.oli.work.Alarms
import studio.oculot.oli.work.Automator
import studio.oculot.oli.work.Notifier
import studio.oculot.oli.work.SiteWatchWorker

// FragmentActivity (et non ComponentActivity) : BiometricPrompt en a besoin.
class MainActivity : FragmentActivity() {

    private val askNotifications = registerForActivityResult(ActivityResultContracts.RequestPermission()) { }
    private val confirmCredential = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { r ->
        prompting = false
        if (r.resultCode == RESULT_OK) unlock() else lockMessage = "Touche « Réessayer » quand tu veux entrer."
    }

    private var locked by mutableStateOf(true)
    private var lockMessage by mutableStateOf<String?>(null)
    private var noLockWarning by mutableStateOf(false)
    private var askPrefill by mutableStateOf<String?>(null)
    private var screen by mutableStateOf("today")
    private var prompting = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(Oc.Bg.toArgb()),
            navigationBarStyle = SystemBarStyle.dark(Oc.Bg.toArgb()),
        )
        Notifier.createChannels(this)
        SiteWatchWorker.schedule(this)
        Alarms.scheduleBriefing(this)
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            askNotifications.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
        locked = Automations.needsUnlock(lastBackgroundAtMs, System.currentTimeMillis(), unlockedOnce)
        handleIntent(intent)

        val repo = Repository(applicationContext)
        val chatStore = ChatStore(applicationContext)

        setContent {
            OliTheme {
                var settings by remember { mutableStateOf(repo.settings()) }
                var state by remember { mutableStateOf(TodayState(sites = repo.cachedChecks(), sitesConfigured = settings.sites.isNotBlank())) }
                val scope = rememberCoroutineScope()

                suspend fun refresh() {
                    state = state.copy(loading = true, sitesConfigured = settings.sites.isNotBlank())
                    coroutineScope {
                        val espace = async { repo.loadEspace() }
                        val agenda = async { repo.loadAgenda() }
                        state = state.copy(espace = espace.await())
                        // Les sites livrés de l'espace client rejoignent la surveillance : on attend l'espace.
                        val run = repo.checkSites()
                        state = state.copy(sites = run.checks, agenda = agenda.await(),
                            sitesConfigured = settings.sites.isNotBlank() || run.checks.isNotEmpty())
                        Automator.afterRefresh(applicationContext, state.espace, state.agenda, run)
                    }
                    state = state.copy(loading = false)
                }

                fun changed() {
                    settings = repo.settings()
                    scope.launch { refresh() }
                }

                LaunchedEffect(Unit) { refresh() }

                Box(Modifier.fillMaxSize().background(Oc.Bg).safeDrawingPadding()) {
                    if (locked) {
                        LockScreen(lockMessage, onRetry = { authenticate() })
                        return@Box
                    }
                    when (screen) {
                        "connexions" -> {
                            BackHandler { screen = "today" }
                            ConnectionsScreen(repo, settings, onChanged = ::changed, onBack = { screen = "today" },
                                onAutomations = { screen = "automatisations" })
                        }
                        "automatisations" -> {
                            BackHandler { screen = "connexions" }
                            AutomationsScreen(onBack = { screen = "connexions" }, onChanged = ::changed)
                        }
                        "chat" -> {
                            BackHandler { screen = "today" }
                            ChatScreen(repo, chatStore, paired = settings.mac != null, macName = settings.mac?.name,
                                prefill = askPrefill, onPrefillUsed = { askPrefill = null },
                                onBack = { screen = "today" }, onConnect = { screen = "connexions" })
                        }
                        else -> TodayScreen(
                            state = state,
                            onRefresh = { if (!state.loading) scope.launch { refresh() } },
                            onSettings = { screen = "connexions" },
                            onChat = { screen = "chat" },
                            noLockWarning = noLockWarning,
                        )
                    }
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(i: Intent?) {
        val ask = i?.getStringExtra(EXTRA_ASK) ?: return
        askPrefill = ask
        screen = "chat"
        i.removeExtra(EXTRA_ASK)
    }

    override fun onStart() {
        super.onStart()
        if (Automations.needsUnlock(lastBackgroundAtMs, System.currentTimeMillis(), unlockedOnce)) locked = true
    }

    override fun onResume() {
        super.onResume()
        if (locked && !prompting) authenticate()
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
        val keyguard = getSystemService(KeyguardManager::class.java)
        if (keyguard?.isDeviceSecure != true) {
            noLockWarning = true
            unlock(); return
        }
        noLockWarning = false
        if (Build.VERSION.SDK_INT < 28) {
            // Android 8 : la fenêtre d'empreinte de la bibliothèque exige un thème AppCompat ;
            // on passe par l'écran de confirmation du système (code, schéma ou empreinte).
            @Suppress("DEPRECATION")
            val i = keyguard.createConfirmDeviceCredentialIntent("Déverrouiller Oli", "Empreinte, visage ou code du téléphone")
            if (i == null) { unlock(); return }
            prompting = true
            confirmCredential.launch(i)
            return
        }
        val authenticators = BIOMETRIC_WEAK or DEVICE_CREDENTIAL
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle("Déverrouiller Oli")
            .setSubtitle("Empreinte, visage ou code du téléphone")
            .setAllowedAuthenticators(authenticators)
            .build()
        val prompt = BiometricPrompt(this, ContextCompat.getMainExecutor(this), object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                prompting = false
                unlock()
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                prompting = false
                lockMessage = when (errorCode) {
                    BiometricPrompt.ERROR_USER_CANCELED, BiometricPrompt.ERROR_NEGATIVE_BUTTON, BiometricPrompt.ERROR_CANCELED ->
                        "Touche « Réessayer » quand tu veux entrer."
                    BiometricPrompt.ERROR_LOCKOUT, BiometricPrompt.ERROR_LOCKOUT_PERMANENT ->
                        "Trop d’essais. Patiente un peu, puis réessaie avec le code du téléphone."
                    else -> errString.toString()
                }
            }
        })
        prompting = true
        try {
            prompt.authenticate(info)
        } catch (e: Exception) {
            prompting = false
            lockMessage = "Impossible d’afficher le déverrouillage. Touche « Réessayer »."
        }
    }

    companion object {
        const val EXTRA_ASK = "studio.oculot.oli.DEMANDER"

        // Vivent avec le processus : un démarrage à froid repart verrouillé, une rotation non.
        private var unlockedOnce = false
        private var lastBackgroundAtMs: Long? = null
    }
}
