package studio.oculot.oli.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Écran verrouillé : Oli et « Réessayer ». Aucun contenu tant que le téléphone n'a pas validé. */
@Composable
fun LockScreen(message: String?, onRetry: () -> Unit) {
    Column(
        Modifier.fillMaxSize().background(Oc.Bg).padding(32.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        OliMascot(Modifier.size(170.dp))
        Spacer(Modifier.height(16.dp))
        Text("Oli est verrouillé", color = Oc.Text, fontSize = 24.sp, fontWeight = FontWeight.Bold)
        Text(message ?: "Empreinte, visage ou code du téléphone pour entrer.", color = Oc.Muted, fontSize = 15.sp,
            textAlign = TextAlign.Center, modifier = Modifier.padding(top = 8.dp, bottom = 28.dp))
        PrimaryButton("Réessayer", onRetry)
    }
}
