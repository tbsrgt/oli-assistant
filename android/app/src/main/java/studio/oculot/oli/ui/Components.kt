package studio.oculot.oli.ui

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.foundation.BorderStroke
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun ScreenHeader(title: String, onBack: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Retour", tint = Oc.Text) }
        Text(title, color = Oc.Text, fontSize = 22.sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
fun SectionLabel(text: String, modifier: Modifier = Modifier) {
    Text(text.uppercase(), color = Oc.Muted, fontSize = 12.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.5.sp,
        modifier = modifier.padding(bottom = 6.dp))
}

@Composable
fun HelpText(text: String, modifier: Modifier = Modifier) {
    Text(text, color = Oc.Muted, fontSize = 14.sp, modifier = modifier.padding(bottom = 10.dp))
}

@Composable
fun OliField(
    value: String,
    onChange: (String) -> Unit,
    label: String,
    placeholder: String? = null,
    singleLine: Boolean = true,
    secret: Boolean = false,
    keyboard: KeyboardType = KeyboardType.Text,
    minHeight: Int = 0,
    enabled: Boolean = true,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onChange,
        label = { Text(label) },
        placeholder = placeholder?.let { { Text(it, color = Oc.Muted.copy(alpha = 0.6f)) } },
        singleLine = singleLine,
        enabled = enabled,
        visualTransformation = if (secret) PasswordVisualTransformation() else VisualTransformation.None,
        keyboardOptions = KeyboardOptions(
            keyboardType = if (secret) KeyboardType.Password else keyboard,
            autoCorrectEnabled = false,
            imeAction = if (singleLine) ImeAction.Done else ImeAction.Default,
        ),
        colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = Oc.Tomato, unfocusedBorderColor = Oc.CardBorder,
            focusedLabelColor = Oc.Tomato, cursorColor = Oc.Tomato,
            focusedTextColor = Oc.Text, unfocusedTextColor = Oc.Text,
        ),
        modifier = Modifier.fillMaxWidth().heightIn(min = minHeight.dp),
    )
}

/** Gros bouton tomate, avec une roue pendant la vérification. */
@Composable
fun PrimaryButton(text: String, onClick: () -> Unit, busy: Boolean = false, enabled: Boolean = true, modifier: Modifier = Modifier) {
    Button(
        onClick = onClick,
        enabled = enabled && !busy,
        colors = ButtonDefaults.buttonColors(containerColor = Oc.Tomato, contentColor = Oc.Bg,
            disabledContainerColor = Oc.Tomato.copy(alpha = 0.45f), disabledContentColor = Oc.Bg),
        modifier = modifier.fillMaxWidth().height(52.dp),
    ) {
        if (busy) {
            CircularProgressIndicator(Modifier.size(18.dp), color = Oc.Bg, strokeWidth = 2.dp)
            Spacer(Modifier.width(10.dp))
        }
        Text(text, fontWeight = FontWeight.Bold, fontSize = 16.sp)
    }
}

@Composable
fun SecondaryButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, danger: Boolean = false) {
    OutlinedButton(
        onClick = onClick,
        border = BorderStroke(1.dp, if (danger) Oc.Down.copy(alpha = 0.6f) else Oc.CardBorder),
        colors = ButtonDefaults.outlinedButtonColors(contentColor = if (danger) Oc.Down else Oc.Text),
        modifier = modifier.fillMaxWidth().height(48.dp),
    ) { Text(text, fontWeight = FontWeight.SemiBold) }
}

@Composable
fun ErrorText(text: String?) {
    if (text != null) Text(text, color = Oc.Down, fontSize = 14.sp, modifier = Modifier.padding(vertical = 8.dp))
}

@Composable
fun SuccessText(text: String) {
    Text(text, color = Oc.Ok, fontSize = 18.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(vertical = 8.dp))
}
