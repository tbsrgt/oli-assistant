package studio.oculot.oli.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import studio.oculot.oli.core.Espace
import studio.oculot.oli.data.Settings

@Composable
fun SettingsScreen(initial: Settings, onSave: (Settings) -> Unit, onBack: () -> Unit) {
    var token by remember { mutableStateOf(initial.espaceToken) }
    var url by remember { mutableStateOf(initial.espaceUrl) }
    var sites by remember { mutableStateOf(initial.sites) }
    var ics by remember { mutableStateOf(initial.icsUrl) }
    var showToken by remember { mutableStateOf(false) }

    Column(
        Modifier
            .fillMaxSize()
            .background(Oc.Bg)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Retour", tint = Oc.Text) }
            Text("Réglages", color = Oc.Text, fontSize = 22.sp, fontWeight = FontWeight.Bold)
        }
        Text(
            "Tout reste sur ce téléphone, chiffré. Oli ne l’envoie qu’à l’espace client et à ton agenda.",
            color = Oc.Muted, fontSize = 14.sp, modifier = Modifier.padding(top = 4.dp, bottom = 16.dp),
        )

        Label("Espace client")
        Field(
            value = token, onChange = { token = it.trim() }, label = "Jeton de l’équipe",
            transformation = if (showToken) VisualTransformation.None else PasswordVisualTransformation(),
            keyboard = KeyboardType.Password,
        )
        TextButton(onClick = { showToken = !showToken }) {
            Text(if (showToken) "Masquer le jeton" else "Afficher le jeton", color = Oc.Tomato)
        }
        Field(value = url, onChange = { url = it }, label = "Adresse de l’espace (facultatif)",
            placeholder = Espace.DEFAULT_BASE_URL, keyboard = KeyboardType.Uri)
        Spacer(Modifier.height(20.dp))

        Label("Sites à surveiller")
        Help("Une adresse par ligne. Les sites livrés de l’espace client sont ajoutés tout seuls.")
        Field(value = sites, onChange = { sites = it }, label = "Sites", placeholder = "oculot.studio\nexemple.fr",
            singleLine = false, keyboard = KeyboardType.Uri, minHeight = 140)
        Spacer(Modifier.height(20.dp))

        Label("Agenda")
        Help("Le lien iCal secret de ton agenda (Google Agenda : Paramètres → Adresse secrète au format iCal).")
        Field(value = ics, onChange = { ics = it.trim() }, label = "Lien iCal", placeholder = "https://…/basic.ics",
            keyboard = KeyboardType.Uri)
        Spacer(Modifier.height(28.dp))

        Button(
            onClick = { onSave(Settings(token, url, sites, ics)) },
            colors = ButtonDefaults.buttonColors(containerColor = Oc.Tomato, contentColor = Oc.Bg),
            modifier = Modifier.fillMaxWidth().height(52.dp),
        ) { Text("Enregistrer", fontWeight = FontWeight.Bold, fontSize = 16.sp) }
        Spacer(Modifier.height(32.dp))
    }
}

@Composable
private fun Label(text: String) {
    Text(text.uppercase(), color = Oc.Muted, fontSize = 12.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.5.sp,
        modifier = Modifier.padding(bottom = 6.dp))
}

@Composable
private fun Help(text: String) {
    Text(text, color = Oc.Muted, fontSize = 13.sp, modifier = Modifier.padding(bottom = 8.dp))
}

@Composable
private fun Field(
    value: String,
    onChange: (String) -> Unit,
    label: String,
    placeholder: String? = null,
    singleLine: Boolean = true,
    transformation: VisualTransformation = VisualTransformation.None,
    keyboard: KeyboardType = KeyboardType.Text,
    minHeight: Int = 0,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onChange,
        label = { Text(label) },
        placeholder = placeholder?.let { { Text(it, color = Oc.Muted.copy(alpha = 0.6f)) } },
        singleLine = singleLine,
        visualTransformation = transformation,
        keyboardOptions = KeyboardOptions(keyboardType = keyboard, autoCorrectEnabled = false),
        colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = Oc.Tomato, unfocusedBorderColor = Oc.CardBorder,
            focusedLabelColor = Oc.Tomato, cursorColor = Oc.Tomato,
            focusedTextColor = Oc.Text, unfocusedTextColor = Oc.Text,
        ),
        modifier = Modifier.fillMaxWidth().heightIn(min = minHeight.dp),
    )
}
