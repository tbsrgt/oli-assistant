package studio.oculot.oli

import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import studio.oculot.oli.ui.Oc
import studio.oculot.oli.ui.OliMascot
import studio.oculot.oli.ui.OliTheme
import studio.oculot.oli.ui.PrimaryButton
import studio.oculot.oli.ui.SecondaryButton

/**
 * Feuille de partage : un fichier ou un lien partagé vers Oli → « Envoyer par mail » (ouvre l'app
 * mail choisie, pièce jointe incluse : c'est toi qui envoies) ou « Demander à Oli » (pré-remplit le chat).
 */
class ShareActivity : ComponentActivity() {

    private data class Shared(val text: String?, val subject: String?, val uris: List<Uri>, val type: String, val names: List<String>)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(statusBarStyle = SystemBarStyle.dark(Oc.Bg.toArgb()), navigationBarStyle = SystemBarStyle.dark(Oc.Bg.toArgb()))
        val shared = read(intent)
        if (shared == null) {
            Toast.makeText(this, "Rien à partager ici.", Toast.LENGTH_SHORT).show()
            finish(); return
        }
        val summary = when {
            shared.names.size == 1 -> shared.names[0]
            shared.names.size > 1 -> "${shared.names.size} fichiers"
            else -> shared.text.orEmpty()
        }
        setContent {
            OliTheme {
                Box(Modifier.fillMaxSize().background(Oc.Bg).safeDrawingPadding().padding(20.dp), contentAlignment = Alignment.Center) {
                    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                        OliMascot(Modifier.size(120.dp))
                        Spacer(Modifier.height(12.dp))
                        Text("Qu’est-ce que j’en fais ?", color = Oc.Text, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                        Text(summary, color = Oc.Muted, fontSize = 14.sp, maxLines = 3, overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.padding(top = 6.dp, bottom = 24.dp))
                        PrimaryButton("Envoyer par mail", onClick = { sendByMail(shared) })
                        Spacer(Modifier.height(10.dp))
                        SecondaryButton("Demander à Oli", onClick = { askOli(shared) })
                        Spacer(Modifier.height(6.dp))
                        TextButton(onClick = { finish() }) { Text("Annuler", color = Oc.Muted) }
                    }
                }
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun read(i: Intent): Shared? {
        val type = i.type ?: "*/*"
        val text = i.getStringExtra(Intent.EXTRA_TEXT)?.trim()?.ifBlank { null }
        val subject = i.getStringExtra(Intent.EXTRA_SUBJECT)
        val uris: List<Uri> = when (i.action) {
            Intent.ACTION_SEND -> listOfNotNull(
                if (Build.VERSION.SDK_INT >= 33) i.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java) else i.getParcelableExtra(Intent.EXTRA_STREAM),
            )
            Intent.ACTION_SEND_MULTIPLE ->
                (if (Build.VERSION.SDK_INT >= 33) i.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java) else i.getParcelableArrayListExtra(Intent.EXTRA_STREAM))
                    .orEmpty()
            else -> emptyList()
        }
        if (text == null && uris.isEmpty()) return null
        return Shared(text, subject, uris, type, uris.map { displayName(it) })
    }

    private fun displayName(uri: Uri): String = runCatching {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) c.getString(0) else null
        }
    }.getOrNull() ?: uri.lastPathSegment ?: "fichier"

    /** Ouvre l'app mail (choix de l'utilisateur) avec la pièce jointe ou le lien. Rien n'est envoyé sans lui. */
    private fun sendByMail(s: Shared) {
        val send = Intent(if (s.uris.size > 1) Intent.ACTION_SEND_MULTIPLE else Intent.ACTION_SEND).apply {
            type = if (s.uris.isEmpty()) "text/plain" else s.type
            s.subject?.let { putExtra(Intent.EXTRA_SUBJECT, it) }
                ?: s.names.singleOrNull()?.let { putExtra(Intent.EXTRA_SUBJECT, it) }
            s.text?.let { putExtra(Intent.EXTRA_TEXT, it) }
            if (s.uris.size == 1) putExtra(Intent.EXTRA_STREAM, s.uris[0])
            if (s.uris.size > 1) putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(s.uris))
            if (s.uris.isNotEmpty()) {
                clipData = ClipData.newRawUri("", s.uris[0]).also { c -> s.uris.drop(1).forEach { c.addItem(ClipData.Item(it)) } }
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        }
        // Le sélecteur « mailto: » limite la liste aux apps de mail.
        val mailOnly = Intent(send).apply { selector = Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:")) }
        try {
            startActivity(Intent.createChooser(mailOnly, "Envoyer par mail"))
        } catch (_: Exception) {
            try { startActivity(Intent.createChooser(send, "Envoyer par mail")) }
            catch (_: Exception) { Toast.makeText(this, "Aucune app de mail trouvée.", Toast.LENGTH_SHORT).show() }
        }
        finish()
    }

    /** Ouvre « Demander à Oli » avec le lien ou une description du fichier, prêt à compléter. */
    private fun askOli(s: Shared) {
        val prompt = buildString {
            if (s.names.isNotEmpty()) {
                append(if (s.names.size == 1) "J’ai un fichier « ${s.names[0]} »" else "J’ai ${s.names.size} fichiers : ${s.names.joinToString(", ") { "« $it »" }}")
                readSmallText(s)?.let { append(". Voici son contenu :\n\n").append(it).append("\n\n") } ?: append(". ")
            }
            s.text?.let { append(it).append("\n\n") }
            append("Qu’en penses-tu ?")
        }
        startActivity(Intent(this, MainActivity::class.java)
            .putExtra(MainActivity.EXTRA_ASK, prompt)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP))
        finish()
    }

    /** Petit fichier texte (≤ 8 000 caractères) : on joint son contenu à la question. */
    private fun readSmallText(s: Shared): String? {
        if (s.uris.size != 1 || !s.type.startsWith("text/")) return null
        return runCatching {
            contentResolver.openInputStream(s.uris[0])?.use { input ->
                val buf = CharArray(8001)
                val n = input.bufferedReader().read(buf)
                if (n in 1..8000) String(buf, 0, n) else null
            }
        }.getOrNull()
    }
}
