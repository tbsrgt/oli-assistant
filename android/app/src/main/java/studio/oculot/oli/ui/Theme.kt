package studio.oculot.oli.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

/** Couleurs Oculot. */
object Oc {
    val Tomato = Color(0xFFFF5B37)
    val Butter = Color(0xFFFFD65C)
    val Bg = Color(0xFF0D0D0F)
    val Card = Color(0xFF17171B)
    val CardBorder = Color(0xFF26262C)
    val Text = Color(0xFFF5F1EA)
    val Muted = Color(0xFF9A968F)
    val Ok = Color(0xFF22C55E)
    val Down = Color(0xFFF4505E)
    val Unknown = Color(0xFF8E939C)
}

private val scheme = darkColorScheme(
    primary = Oc.Tomato,
    onPrimary = Color(0xFF1A0B06),
    secondary = Oc.Butter,
    onSecondary = Color(0xFF1A1505),
    background = Oc.Bg,
    onBackground = Oc.Text,
    surface = Oc.Card,
    onSurface = Oc.Text,
    surfaceVariant = Oc.Card,
    onSurfaceVariant = Oc.Muted,
    outline = Oc.CardBorder,
    error = Oc.Down,
)

@Composable
fun OliTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = scheme, content = content)
}
