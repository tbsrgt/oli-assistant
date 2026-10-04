package studio.oculot.oli.ui

import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.translate
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin

/**
 * Silhouette d'Oli (même calcul que `OliShape` côté Mac) : astroïde r = 1 / (|cos|^p + |sin|^p)^(1/p),
 * p = 0,70, rayon lissé sur ±12°, normalisé pour que les pointes valent 1.
 */
object OliShape {
    private const val P = 0.70
    private const val SMOOTH_DEG = 12.0
    private const val SAMPLES = 360

    val radii: DoubleArray by lazy {
        val raw = DoubleArray(SAMPLES) { i ->
            val t = i.toDouble() / SAMPLES * 2 * PI
            1.0 / (abs(cos(t)).pow(P) + abs(sin(t)).pow(P)).pow(1 / P)
        }
        val k = (SMOOTH_DEG / 360 * SAMPLES).toInt()
        val out = DoubleArray(SAMPLES) { i ->
            var s = 0.0
            for (j in -k..k) s += raw[(i + j + SAMPLES) % SAMPLES]
            s / (2 * k + 1)
        }
        val m = out.max()
        DoubleArray(SAMPLES) { out[it] / m }
    }

    fun radius(t: Double): Double {
        var a = t % (2 * PI); if (a < 0) a += 2 * PI
        val f = a / (2 * PI) * SAMPLES
        val i = f.toInt() % SAMPLES
        val j = (i + 1) % SAMPLES
        val u = f - f.toInt()
        return radii[i] * (1 - u) + radii[j] * u
    }

    fun path(r: Float, cx: Float, cy: Float, points: Int = 180): Path = Path().apply {
        for (i in 0..points) {
            val a = i.toDouble() / points * 2 * PI
            val rr = radius(a) * r
            val x = cx + (rr * cos(a)).toFloat()
            val y = cy + (rr * sin(a)).toFloat()
            if (i == 0) moveTo(x, y) else lineTo(x, y)
        }
        close()
    }
}

private val BodyTop = Color(0xFFFF8A52)
private val BodyBottom = Color(0xFFE8431A)
private val VisorTop = Color(0xFF2A2420)
private val VisorBottom = Color(0xFF0E0C0A)
private val EyeLight = Color(0xFFFFF3E0)
private val Satellite = Color(0xFFFF7A45)

/** Oli qui flotte doucement et cligne des yeux. */
@Composable
fun OliMascot(modifier: Modifier = Modifier, worried: Boolean = false) {
    var t by remember { mutableFloatStateOf(0f) }
    LaunchedEffect(Unit) {
        val start = withFrameMillis { it }
        while (true) {
            withFrameMillis { t = (it - start) / 1000f }
        }
    }
    Canvas(modifier) { drawOli(t, worried) }
}

/** Ouverture des yeux : un clignement court toutes les ~4 s, parfois doublé. */
internal fun eyeOpenness(t: Float): Float {
    val period = 4.2f
    val phase = t % period
    fun blink(at: Float): Float {
        val d = abs(phase - at)
        return if (d < 0.09f) d / 0.09f else 1f
    }
    val second = if ((t / period).toInt() % 3 == 2) blink(3.75f) else 1f
    return minOf(blink(3.45f), second).coerceIn(0.08f, 1f)
}

private fun DrawScope.drawOli(t: Float, worried: Boolean) {
    val s = minOf(size.width, size.height)
    val r = s * 0.34f
    val bob = sin(t * 1.3f) * r * 0.07f
    val tilt = sin(t * 0.7f) * 3f
    val cx = size.width / 2
    val cy = size.height / 2 + bob

    // Ombre douce au sol, qui respire avec le flottement.
    val shadowW = r * (1.25f - 0.12f * (bob / (r * 0.07f)))
    drawOval(
        Brush.radialGradient(listOf(Color.Black.copy(alpha = 0.45f), Color.Transparent),
            center = Offset(cx, size.height / 2 + r * 1.22f), radius = shadowW),
        topLeft = Offset(cx - shadowW, size.height / 2 + r * 1.22f - r * 0.12f),
        size = Size(shadowW * 2, r * 0.24f),
    )

    rotate(tilt, pivot = Offset(cx, cy)) {
        // Halo tomate derrière le corps.
        drawCircle(
            Brush.radialGradient(listOf(BodyTop.copy(alpha = 0.22f), Color.Transparent), center = Offset(cx, cy), radius = r * 1.6f),
            radius = r * 1.6f, center = Offset(cx, cy),
        )
        val body = OliShape.path(r, cx, cy)
        drawPath(body, Brush.verticalGradient(listOf(BodyTop, BodyBottom), startY = cy - r, endY = cy + r))

        clipPath(body) {
            // Visière sombre et brillante.
            val lookX = sin(t * 0.45f) * r * 0.06f
            val vw = r * 1.05f
            val vh = r * 0.62f
            val vcx = cx + lookX
            val vcy = cy + r * 0.06f
            drawRoundRect(
                Brush.verticalGradient(listOf(VisorTop, VisorBottom), startY = vcy - vh / 2, endY = vcy + vh / 2),
                topLeft = Offset(vcx - vw / 2, vcy - vh / 2), size = Size(vw, vh), cornerRadius = CornerRadius(vh / 2),
            )
            drawOval(
                Color.White.copy(alpha = 0.10f),
                topLeft = Offset(vcx - vw * 0.42f, vcy - vh * 0.48f), size = Size(vw * 0.84f, vh * 0.34f),
            )

            // Yeux pilules lumineux.
            val open = eyeOpenness(t)
            val ew = r * 0.14f
            val eh = maxOf(r * 0.34f * open * (if (worried) 0.8f else 1f), ew * 0.3f)
            for (sd in listOf(-1f, 1f)) {
                val ex = vcx + sd * r * 0.22f + lookX * 0.5f
                translate(ex, vcy) {
                    // lueur
                    drawRoundRect(
                        EyeLight.copy(alpha = 0.18f),
                        topLeft = Offset(-ew * 0.95f, -eh / 2 - ew * 0.45f), size = Size(ew * 1.9f, eh + ew * 0.9f),
                        cornerRadius = CornerRadius(ew),
                    )
                    drawRoundRect(
                        EyeLight,
                        topLeft = Offset(-ew / 2, -eh / 2), size = Size(ew, eh),
                        cornerRadius = CornerRadius(minOf(ew, eh) / 2),
                    )
                }
            }
        }
    }

    // Satellite : petit point orange en haut à droite, qui flotte à son rythme.
    val ang = -0.76f
    val dist = r * 1.40f
    val sb = sin(t * 1.6f) * r * 0.04f
    val pulse = if (worried) 1f + 0.25f * sin(t * 7f) else 1f
    val rad = r * 0.10f * pulse
    val sat = Offset(cx + cos(ang) * dist, cy + sin(ang) * dist + sb)
    val satColor = if (worried) Color(0xFFF4505E) else Satellite
    drawCircle(Brush.radialGradient(listOf(satColor.copy(alpha = 0.35f), Color.Transparent), center = sat, radius = rad * 2.4f),
        radius = rad * 2.4f, center = sat)
    drawCircle(satColor, radius = rad, center = sat)
}
