package studio.oculot.oli

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
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
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import studio.oculot.oli.core.Sites
import studio.oculot.oli.data.Repository
import studio.oculot.oli.ui.Oc
import studio.oculot.oli.ui.OliTheme
import studio.oculot.oli.ui.SettingsScreen
import studio.oculot.oli.ui.TodayScreen
import studio.oculot.oli.ui.TodayState
import studio.oculot.oli.work.SiteWatchWorker

class MainActivity : ComponentActivity() {

    private val askNotifications = registerForActivityResult(ActivityResultContracts.RequestPermission()) { }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(Oc.Bg.toArgb()),
            navigationBarStyle = SystemBarStyle.dark(Oc.Bg.toArgb()),
        )
        SiteWatchWorker.createChannel(this)
        SiteWatchWorker.schedule(this)
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            askNotifications.launch(Manifest.permission.POST_NOTIFICATIONS)
        }

        val repo = Repository(applicationContext)

        setContent {
            OliTheme {
                var screen by remember { mutableStateOf("today") }
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
                        val (checks, outages) = repo.checkSites()
                        outages.forEach { SiteWatchWorker.notifyOutage(applicationContext, it) }
                        state = state.copy(sites = checks, agenda = agenda.await(),
                            sitesConfigured = settings.sites.isNotBlank() || checks.isNotEmpty())
                    }
                    state = state.copy(loading = false)
                }

                LaunchedEffect(Unit) { refresh() }

                Box(Modifier.fillMaxSize().background(Oc.Bg).safeDrawingPadding()) {
                    when (screen) {
                        "settings" -> {
                            BackHandler { screen = "today" }
                            SettingsScreen(
                                initial = settings,
                                onSave = { s ->
                                    repo.saveSettings(s)
                                    settings = repo.settings()
                                    val n = Sites.targets(settings.sites).size
                                    Toast.makeText(this@MainActivity,
                                        if (n > 0) "C’est noté ! Je surveille $n site${if (n > 1) "s" else ""}." else "C’est noté !",
                                        Toast.LENGTH_SHORT).show()
                                    screen = "today"
                                    scope.launch { refresh() }
                                },
                                onBack = { screen = "today" },
                            )
                        }
                        else -> TodayScreen(
                            state = state,
                            onRefresh = { if (!state.loading) scope.launch { refresh() } },
                            onSettings = { screen = "settings" },
                        )
                    }
                }
            }
        }
    }
}

