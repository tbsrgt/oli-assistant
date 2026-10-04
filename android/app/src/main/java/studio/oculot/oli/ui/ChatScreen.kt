package studio.oculot.oli.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import studio.oculot.oli.core.ChatResult
import studio.oculot.oli.data.ChatMessage
import studio.oculot.oli.data.ChatStore
import studio.oculot.oli.data.Repository

/** « Demander à Oli » : un chat simple avec Claude, via Oli sur le Mac. */
@Composable
fun ChatScreen(
    repo: Repository,
    store: ChatStore,
    paired: Boolean,
    macName: String?,
    prefill: String?,
    onPrefillUsed: () -> Unit,
    onBack: () -> Unit,
    onConnect: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    var messages by remember { mutableStateOf(store.messages()) }
    var session by remember { mutableStateOf(store.session()) }
    var input by remember { mutableStateOf("") }
    var sending by remember { mutableStateOf(false) }
    val list = rememberLazyListState()

    LaunchedEffect(prefill) {
        if (!prefill.isNullOrBlank()) { input = prefill; onPrefillUsed() }
    }
    LaunchedEffect(messages.size, sending) {
        val n = messages.size + if (sending) 1 else 0
        if (n > 0) list.animateScrollToItem(n - 1)
    }

    fun send() {
        val text = input.trim()
        if (text.isEmpty() || sending) return
        input = ""
        messages = messages + ChatMessage(true, text)
        store.save(messages, session)
        sending = true
        scope.launch {
            when (val r = repo.macChat(text, session)) {
                is ChatResult.Ok -> { session = r.session ?: session; messages = messages + ChatMessage(false, r.reply) }
                is ChatResult.Error -> messages = messages + ChatMessage(false, r.message, isError = true)
            }
            sending = false
            store.save(messages, session)
        }
    }

    Column(Modifier.fillMaxSize().background(Oc.Bg).imePadding()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Retour", tint = Oc.Text) }
            Column(Modifier.weight(1f)) {
                Text("Demander à Oli", color = Oc.Text, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                Text(if (paired) "Claude, via ${macName ?: "ton Mac"}" else "Pas encore jumelé", color = Oc.Muted, fontSize = 13.sp)
            }
            if (messages.isNotEmpty()) {
                TextButton(onClick = {
                    messages = emptyList(); session = null; store.clear()
                }, enabled = !sending) { Text("Nouvelle conversation", color = Oc.Tomato, fontSize = 13.sp) }
            }
        }

        Box(Modifier.weight(1f).fillMaxWidth()) {
            if (messages.isEmpty() && !sending) {
                Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                    OliMascot(Modifier.size(130.dp))
                    Spacer(Modifier.size(12.dp))
                    if (paired) {
                        Text("Pose-moi une question, je la passe à Claude sur ton Mac.", color = Oc.Text, fontSize = 16.sp)
                        Text("Ex. : « Rédige une relance gentille pour le devis Martin. »", color = Oc.Muted, fontSize = 14.sp,
                            modifier = Modifier.padding(top = 6.dp))
                    } else {
                        Text("Pour parler à Claude, jumelle d’abord ton Mac.", color = Oc.Text, fontSize = 16.sp)
                        TextButton(onClick = onConnect) { Text("Se connecter à Claude", color = Oc.Tomato, fontWeight = FontWeight.SemiBold) }
                    }
                }
            } else {
                LazyColumn(state = list, modifier = Modifier.fillMaxSize().padding(horizontal = 12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(messages) { m -> Bubble(m) }
                    if (sending) item {
                        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(8.dp)) {
                            CircularProgressIndicator(Modifier.size(16.dp), color = Oc.Butter, strokeWidth = 2.dp)
                            Spacer(Modifier.size(10.dp))
                            Text("Oli réfléchit… (ça peut prendre une minute)", color = Oc.Muted, fontSize = 14.sp)
                        }
                    }
                }
            }
        }

        Row(Modifier.fillMaxWidth().padding(12.dp), verticalAlignment = Alignment.Bottom) {
            OutlinedTextField(
                value = input,
                onValueChange = { input = it },
                placeholder = { Text("Écris à Oli…", color = Oc.Muted.copy(alpha = 0.7f)) },
                maxLines = 6,
                enabled = paired,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = Oc.Tomato, unfocusedBorderColor = Oc.CardBorder, cursorColor = Oc.Tomato,
                    focusedTextColor = Oc.Text, unfocusedTextColor = Oc.Text,
                ),
                shape = RoundedCornerShape(22.dp),
                modifier = Modifier.weight(1f),
            )
            IconButton(onClick = ::send, enabled = paired && input.isNotBlank() && !sending, modifier = Modifier.padding(start = 6.dp)) {
                Icon(Icons.AutoMirrored.Filled.Send, "Envoyer", tint = if (input.isNotBlank() && !sending) Oc.Tomato else Oc.Muted)
            }
        }
    }
}

@Composable
private fun Bubble(m: ChatMessage) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = if (m.fromMe) Arrangement.End else Arrangement.Start) {
        Box(
            Modifier.widthIn(max = 320.dp)
                .background(
                    when { m.fromMe -> Oc.Tomato; m.isError -> Oc.Down.copy(alpha = 0.15f); else -> Oc.Card },
                    RoundedCornerShape(topStart = 18.dp, topEnd = 18.dp, bottomStart = if (m.fromMe) 18.dp else 4.dp, bottomEnd = if (m.fromMe) 4.dp else 18.dp),
                )
                .padding(horizontal = 14.dp, vertical = 10.dp),
        ) {
            SelectionContainer {
                Text(m.text, color = when { m.fromMe -> Oc.Bg; m.isError -> Oc.Down; else -> Oc.Text }, fontSize = 15.sp)
            }
        }
    }
}
