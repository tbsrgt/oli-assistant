package studio.oculot.oli.overlay

import android.annotation.SuppressLint
import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.PixelFormat
import android.os.Build
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleService
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.savedstate.SavedStateRegistry
import androidx.savedstate.SavedStateRegistryController
import androidx.savedstate.SavedStateRegistryOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import studio.oculot.oli.MainActivity
import studio.oculot.oli.R
import studio.oculot.oli.core.SiteStatus
import studio.oculot.oli.data.AutomationPrefs
import studio.oculot.oli.data.MemoryStore
import studio.oculot.oli.data.Repository
import studio.oculot.oli.ui.Oc
import studio.oculot.oli.ui.OliMascot
import studio.oculot.oli.work.Notifier
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.abs

/** Ce que montre la pastille, lu dans les caches locaux (aucun appel réseau depuis la pastille). */
data class PillInfo(val short: String, val lines: List<String>, val worried: Boolean, val claudeWaiting: Boolean)

/**
 * Oli flottant : une pastille noire centrée en haut de l'écran, par-dessus les autres apps
 * (autorisation « Afficher par-dessus les autres apps »). Un tap la déplie, toucher ailleurs ou
 * glisser vers le haut la replie, on la déplace à l'horizontale. Service de premier plan.
 */
class OverlayService : LifecycleService(), SavedStateRegistryOwner {
    private val saved = SavedStateRegistryController.create(this)
    override val savedStateRegistry: SavedStateRegistry get() = saved.savedStateRegistry

    private var root: View? = null
    private lateinit var params: WindowManager.LayoutParams
    private val wm by lazy { getSystemService(WindowManager::class.java) }
    private var expanded by mutableStateOf(false)
    private var info by mutableStateOf(PillInfo("Oli veille", emptyList(), worried = false, claudeWaiting = false))

    override fun onCreate() {
        saved.performAttach()
        saved.performRestore(null)
        super.onCreate()
        Notifier.createChannels(this)
        if (Build.VERSION.SDK_INT >= 34) {
            ServiceCompat.startForeground(this, NOTIF_ID, notification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIF_ID, notification())
        }
        if (!Settings.canDrawOverlays(this)) { stopSelf(); return }
        show()
        lifecycleScope.launch {
            while (true) { info = readInfo(); delay(30_000) }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)
        if (intent?.action == ACTION_HIDE) {
            AutomationPrefs(this).set(AutomationPrefs.Key.FLOATING, false)
            stopSelf()
            return START_NOT_STICKY
        }
        if (intent?.action == ACTION_REFRESH) lifecycleScope.launch { info = readInfo() }
        return START_STICKY
    }

    override fun onDestroy() {
        root?.let { runCatching { wm.removeView(it) } }
        root = null
        super.onDestroy()
    }

    private fun notification(): Notification {
        val hide = PendingIntent.getService(this, 1, Intent(this, OverlayService::class.java).setAction(ACTION_HIDE),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        return NotificationCompat.Builder(this, Notifier.CH_FLOATING)
            .setSmallIcon(R.drawable.ic_notif_oli)
            .setColor(0xFFFF5B37.toInt())
            .setContentTitle("Oli flotte en haut de l’écran")
            .setContentText("Android exige cette notification pour garder la pastille.")
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setContentIntent(Notifier.openApp(this))
            .addAction(0, "Masquer Oli", hide)
            .build()
    }

    private fun statusBarHeight(): Int {
        val id = resources.getIdentifier("status_bar_height", "dimen", "android")
        return if (id > 0) resources.getDimensionPixelSize(id) else (24 * resources.displayMetrics.density).toInt()
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun show() {
        params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            y = statusBarHeight() + (4 * resources.displayMetrics.density).toInt()
        }
        val container = object : FrameLayout(this) {
            override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
                if (ev.action == MotionEvent.ACTION_OUTSIDE) { expanded = false; return true }
                return super.dispatchTouchEvent(ev)
            }
        }
        container.setViewTreeLifecycleOwner(this)
        container.setViewTreeSavedStateRegistryOwner(this)
        container.addView(ComposeView(this).apply { setContent { Pill() } })
        wm.addView(container, params)
        root = container
    }

    private fun moveBy(dx: Float) {
        val max = resources.displayMetrics.widthPixels / 2 - (60 * resources.displayMetrics.density).toInt()
        params.x = (params.x + dx.toInt()).coerceIn(-max, max)
        root?.let { runCatching { wm.updateViewLayout(it, params) } }
    }

    private fun open(screen: String?) {
        expanded = false
        startActivity(Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .apply { if (screen != null) putExtra(MainActivity.EXTRA_SCREEN, screen) })
    }

    @Composable
    private fun Pill() {
        val shape = RoundedCornerShape(if (expanded) 28.dp else 22.dp)
        var dragY by remember { mutableStateOf(0f) }
        Column(
            Modifier
                .padding(4.dp)
                .clip(shape)
                .background(Color(0xF2000000))
                .animateContentSize(spring(dampingRatio = 0.78f, stiffness = Spring.StiffnessMediumLow))
                .pointerInput(Unit) {
                    detectDragGestures(
                        onDragStart = { dragY = 0f },
                        onDrag = { change, amount ->
                            change.consume()
                            if (abs(amount.x) > abs(amount.y)) moveBy(amount.x)
                            dragY += amount.y
                            if (dragY < -40f && expanded) expanded = false
                            if (dragY > 40f && !expanded) expanded = true
                        },
                    )
                }
                .clickable(remember { MutableInteractionSource() }, indication = null) { expanded = !expanded }
                .widthIn(min = 120.dp, max = if (expanded) 360.dp else 260.dp),
        ) {
            Row(Modifier.padding(horizontal = 10.dp, vertical = 5.dp), verticalAlignment = Alignment.CenterVertically) {
                OliMascot(Modifier.size(if (expanded) 44.dp else 26.dp), worried = info.worried, frameMs = 90)
                Spacer(Modifier.width(6.dp))
                Text(if (expanded) "Oli" else info.short, color = Color.White, fontSize = if (expanded) 17.sp else 13.sp,
                    fontWeight = if (expanded) FontWeight.Bold else FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (!expanded) Spacer(Modifier.width(6.dp))
            }
            AnimatedVisibility(
                visible = expanded,
                enter = expandVertically(spring(dampingRatio = 0.75f, stiffness = Spring.StiffnessLow), expandFrom = Alignment.Top) + fadeIn(tween(220, 60)),
                exit = shrinkVertically(tween(220), shrinkTowards = Alignment.Top) + fadeOut(tween(120)),
            ) {
                Column(Modifier.width(340.dp).padding(start = 16.dp, end = 16.dp, bottom = 14.dp)) {
                    info.lines.forEach { l ->
                        Text("• $l", color = Color(0xFFE8E4DD), fontSize = 14.sp, modifier = Modifier.padding(vertical = 3.dp))
                    }
                    Spacer(Modifier.height(10.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                        Action("Ouvrir l’app", primary = true, modifier = Modifier.weight(1f)) { open(null) }
                        Action("Demander", modifier = Modifier.weight(1f)) { open("chat") }
                        Action(if (info.claudeWaiting) "Claude ⚑" else "Claude", modifier = Modifier.weight(1f)) { open("claude") }
                    }
                }
            }
        }
        LaunchedEffect(expanded) { if (expanded) info = readInfo() }
    }

    @Composable
    private fun Action(text: String, primary: Boolean = false, modifier: Modifier = Modifier, onClick: () -> Unit) {
        Box(
            modifier.clip(RoundedCornerShape(14.dp)).background(if (primary) Oc.Tomato else Color(0xFF26262C))
                .clickable(onClick = onClick).padding(vertical = 10.dp),
            contentAlignment = Alignment.Center,
        ) { Text(text, color = if (primary) Oc.Bg else Color.White, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1) }
    }

    private fun readInfo(): PillInfo {
        val checks = runCatching { Repository(this).cachedChecks() }.getOrDefault(emptyList())
        val memory = MemoryStore(this)
        val down = checks.count { it.status == SiteStatus.DOWN }
        val waiting = memory.claudeWaiting()
        val claude = memory.claudeLine()
        val next = memory.nextEvent()?.takeIf { it.second > System.currentTimeMillis() - 3_600_000 }
        val zone = ZoneId.systemDefault()
        val nextLabel = next?.let { (title, at) ->
            val z = Instant.ofEpochMilli(at).atZone(zone)
            val day = if (z.toLocalDate() == LocalDate.now(zone)) "" else DateTimeFormatter.ofPattern("EEE ", Locale.FRANCE).format(z)
            "$day${DateTimeFormatter.ofPattern("HH:mm", Locale.FRANCE).format(z)} $title"
        }
        val sitesLine = when {
            checks.isEmpty() -> null
            down == 0 -> "${checks.size} site${if (checks.size > 1) "s" else ""} ok"
            down == 1 -> "1 site en panne"
            else -> "$down sites en panne"
        }
        val soon = next != null && next.second - System.currentTimeMillis() < 2 * 3_600_000
        val short = when {
            waiting > 0 -> "Claude attend"
            down > 0 -> sitesLine!!
            soon -> nextLabel!!
            sitesLine != null -> sitesLine
            nextLabel != null -> nextLabel
            else -> "Oli veille"
        }
        val lines = listOfNotNull(
            sitesLine?.let { "Sites : $it" },
            nextLabel?.let { "Prochain rendez-vous : $it" } ?: "Pas de rendez-vous à venir",
            claude?.let { "Claude Code : ${it.replaceFirstChar { c -> c.lowercase() }}" },
        )
        return PillInfo(short, lines, worried = down > 0, claudeWaiting = waiting > 0)
    }

    companion object {
        private const val NOTIF_ID = 4242
        const val ACTION_HIDE = "studio.oculot.oli.MASQUER_PASTILLE"
        const val ACTION_REFRESH = "studio.oculot.oli.RAFRAICHIR_PASTILLE"

        fun canShow(context: Context) = Settings.canDrawOverlays(context)

        fun start(context: Context) {
            if (!canShow(context)) return
            runCatching { ContextCompat.startForegroundService(context, Intent(context, OverlayService::class.java)) }
        }

        fun stop(context: Context) { context.stopService(Intent(context, OverlayService::class.java)) }

        /** Rafraîchit la pastille si elle est affichée (sans la démarrer). */
        fun refresh(context: Context) {
            if (!AutomationPrefs(context).isOn(AutomationPrefs.Key.FLOATING) || !canShow(context)) return
            runCatching { context.startService(Intent(context, OverlayService::class.java).setAction(ACTION_REFRESH)) }
        }
    }
}
