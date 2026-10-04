package studio.oculot.oli.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import studio.oculot.oli.core.Game
import studio.oculot.oli.core.GameEvent
import studio.oculot.oli.core.GameState
import studio.oculot.oli.core.GameUpdate
import java.time.LocalDate

private val Context.gameData: DataStore<Preferences> by preferencesDataStore(name = "oli_jeu")

/** Expérience, séries, défis et badges d'Oli (DataStore, local au téléphone). */
class GameStore(private val context: Context) {
    private val key = stringPreferencesKey("etat")

    val state: Flow<GameState> = context.gameData.data.map { Game.rollDay(GameState.fromJson(it[key]), LocalDate.now()) }

    suspend fun current(): GameState = state.first()

    /** Applique une action et annonce les badges, défis ou niveaux gagnés. */
    suspend fun record(
        event: GameEvent? = null,
        freed: Long = 0,
        securityScore: Int? = null,
        manualChallenge: String? = null,
        allConnected: Boolean? = null,
        outageToday: Boolean = false,
    ): GameUpdate {
        var result: GameUpdate? = null
        val sitesWatched = runCatching { Repository(context).cachedChecks().isNotEmpty() }.getOrDefault(false)
        context.gameData.edit { prefs ->
            val u = Game.apply(GameState.fromJson(prefs[key]), LocalDate.now(), event, freed, securityScore, manualChallenge,
                allConnected, outageToday, sitesWatched)
            prefs[key] = u.state.toJson()
            result = u
        }
        val u = result!!
        if (u.newBadges.isNotEmpty() || u.levelUp || u.newChallenges.isNotEmpty()) celebrations.tryEmit(u)
        return u
    }

    companion object {
        /** Les écrans écoutent ce flux pour afficher la petite fête. */
        val celebrations = MutableSharedFlow<GameUpdate>(extraBufferCapacity = 4)
        val celebrationsFlow: SharedFlow<GameUpdate> get() = celebrations
    }
}
