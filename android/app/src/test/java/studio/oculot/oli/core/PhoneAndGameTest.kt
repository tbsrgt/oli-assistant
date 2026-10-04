package studio.oculot.oli.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneId

class ClaudeCodeTest {
    private val body = """
        {"sessions":[
           {"id":"s1","project":"oculot","state":"working","activity":"Écrit des tests","updatedAt":1800000000},
           {"id":"s2","project":"martin","state":"done","activity":"Terminé","updatedAt":1800000100},
           {"id":"s3","project":"durand","state":"waiting","activity":"Attend","updatedAt":1799999000}],
         "approvals":[{"id":"a1","project":"durand","tool":"Bash","summary":"npm install","detail":"npm install zod"}]}
    """.trimIndent()

    @Test fun `lecture des sessions`() {
        val b = ClaudeCode.parseBoard(body)!!
        assertEquals(listOf("s3", "s1", "s2"), b.sessions.map { it.id })     // en attente d'abord
        assertEquals("Bash", b.approvals[0].tool)
        assertEquals("Claude attend ton accord", b.shortLine)
        assertEquals(1, b.working)
        assertNull(ClaudeCode.parseBoard("<html>"))
    }

    @Test fun `nouvelles a notifier`() {
        val b = ClaudeCode.parseBoard(body)!!
        val prev = ClaudeCode.decodeStates("s1=working\ns2=working")
        val n = ClaudeCode.news(prev, emptySet(), b)
        assertEquals(listOf("a1"), n.newApprovals.map { it.id })
        assertEquals(listOf("s2"), n.finished.map { it.id })
        val again = ClaudeCode.news(ClaudeCode.decodeStates(ClaudeCode.encodeStates(b)), setOf("a1"), b)
        assertTrue(again.newApprovals.isEmpty() && again.finished.isEmpty())
    }

    @Test fun `reponse d'autorisation`() {
        assertTrue(ClaudeCode.parseApprovalReply(200, """{"ok":true}"""))
        assertFalse(ClaudeCode.parseApprovalReply(404, """{"error":"inconnu"}"""))
        assertEquals("""{"allow":false}""", ClaudeCode.approvalBody(false))
        assertEquals("Option désactivée sur le Mac", ClaudeCode.approvalError(403, """{"error":"Option désactivée sur le Mac"}"""))
        assertEquals("Cette demande n’attend plus de réponse.", ClaudeCode.approvalError(410, ""))
        assertTrue(ClaudeCode.parseBoard(body)!!.approvalsEnabled)
        assertFalse(ClaudeCode.parseBoard("""{"sessions":[],"approvals":[],"approvalsEnabled":false}""")!!.approvalsEnabled)
    }
}

class SecurityTest {
    private val today = LocalDate.of(2026, 10, 5)

    @Test fun `telephone propre`() {
        val f = SecurityFacts(true, "2026-09-05", false, false,
            listOf(AppFact("com.whatsapp", "WhatsApp", "com.android.vending"), AppFact("studio.oculot.oli", "Oli", null)))
        val r = Security.evaluate(f, today, "studio.oculot.oli")
        assertEquals(100, r.score)
        assertEquals("Excellent", r.label)
        assertTrue(r.sideloaded.isEmpty())     // Oli lui-même n'est pas compté
    }

    @Test fun `telephone a risque`() {
        val f = SecurityFacts(false, "2026-01-05", true, true, listOf(
            AppFact("x.y", "Inconnue", null, setOf(Sensitivity.ACCESSIBILITY)),
            AppFact("a.b", "Lampe", "com.android.vending", setOf(Sensitivity.SMS)),
        ))
        val r = Security.evaluate(f, today, "studio.oculot.oli")
        // 30 (verrou) + 25 (correctif > 180 j) + 10 (débogage USB) + 3 (hors magasin) + 4 + 2 = 74
        assertEquals(26, r.score)
        assertEquals("Fragile", r.label)
        assertEquals(SettingsTarget.SECURITY, r.advices.first().target)
        assertEquals(273L, Security.patchAgeDays("2026-01-05", today))
        assertNull(Security.patchAgeDays("", today))
    }
}

class CleanupTest {
    private val now = 1_800_000_000_000L
    private val day = 86_400_000L

    @Test fun `categories de nettoyage`() {
        val items = listOf(
            FileItem("1", "IMG_1.jpg", "DCIM", 2_000_000, now - 10 * day, isImage = true),
            FileItem("2", "IMG_1 (1).jpg", "DCIM", 2_000_000, now - 2 * day, isImage = true),
            FileItem("3", "IMG_2.jpg", "DCIM", 2_000_000, now - 1 * day, isImage = true),   // même taille, autre contenu
            FileItem("4", "film.mp4", "Movies", 300L * 1024 * 1024, now),
            FileItem("5", "devis.pdf", "Download", 10_000, now - 120 * day, isDownload = true),
            FileItem("6", "Screenshot_1.png", "Screenshots", 500_000, now - 200 * day, isScreenshot = true, isImage = true),
            FileItem("7", "app.apk", "Download", 20_000_000, now - 200 * day, isDownload = true),
            FileItem("8", "recent.pdf", "Download", 10_000, now - day, isDownload = true),
        )
        val hashes = mapOf("1" to "A", "2" to "A", "3" to "B")
        val c = Cleanup.classify(items, now) { hashes[it.id] }
        assertEquals(listOf("2"), c[CleanCategory.DUPLICATES]!!.map { it.item.id })
        assertEquals("copie de IMG_1.jpg", c[CleanCategory.DUPLICATES]!![0].note)
        assertEquals(listOf("4"), c[CleanCategory.LARGE]!!.map { it.item.id })
        assertEquals(listOf("5"), c[CleanCategory.OLD_DOWNLOADS]!!.map { it.item.id })
        assertEquals(listOf("6"), c[CleanCategory.OLD_SCREENSHOTS]!!.map { it.item.id })
        assertEquals(listOf("7"), c[CleanCategory.APKS]!!.map { it.item.id })
        assertEquals("300 Mo", Cleanup.human(300L * 1024 * 1024))
    }

    @Test fun `rangement des telechargements`() {
        val plan = Tidy.downloadsPlan("/sd/Download", listOf("devis.pdf", "photo.JPG", "app.apk", "x.crdownload", "inconnu.xyz", "a.zip"),
            existing = setOf("/sd/Download/Documents/devis.pdf"))
        assertEquals(listOf(
            "/sd/Download/a.zip" to "/sd/Download/Archives/a.zip",
            "/sd/Download/app.apk" to "/sd/Download/APK/app.apk",
            "/sd/Download/devis.pdf" to "/sd/Download/Documents/devis (2).pdf",
            "/sd/Download/photo.JPG" to "/sd/Download/Images/photo.JPG",
        ), plan.map { it.from to it.to })
    }

    @Test fun `captures renommees par date`() {
        val paris = ZoneId.of("Europe/Paris")
        val t = java.time.ZonedDateTime.of(2026, 10, 4, 10, 11, 12, 0, paris).toInstant().toEpochMilli()
        val plan = Tidy.screenshotPlan("/sd/Pictures/Screenshots", listOf("Screenshot_x.png" to t, "Screenshot_y.png" to t, "Capture déjà.png" to t), emptySet(), paris)
        assertEquals(listOf("/sd/Pictures/Screenshots/Capture 2026-10-04 à 10.11.12.png", "/sd/Pictures/Screenshots/Capture 2026-10-04 à 10.11.12 (2).png"),
            plan.map { it.to })
    }
}

class GameTest {
    private val d = LocalDate.of(2026, 10, 5)

    @Test fun `niveaux`() {
        assertEquals(1, Game.levelFor(0).level)
        assertEquals(2, Game.levelFor(100).level)
        assertEquals(4, Game.levelFor(650).level)
        assertEquals(50, Game.levelFor(650).xpInLevel)
        assertEquals(400, Game.levelFor(650).xpForNext)
    }

    @Test fun `series de jours`() {
        assertEquals(1, Game.nextStreak(null, 0, d))
        assertEquals(3, Game.nextStreak(d.minusDays(1), 2, d))
        assertEquals(2, Game.nextStreak(d, 2, d))
        assertEquals(1, Game.nextStreak(d.minusDays(3), 5, d))
    }

    @Test fun `defis du jour stables et varies`() {
        val a = Game.challengesFor(d)
        assertEquals(a, Game.challengesFor(d))
        assertEquals(3, a.map { it.id }.toSet().size)
        assertEquals(1, a.count { it.manual })
    }

    @Test fun `actions, defis et badges`() {
        var s = GameState()
        val u1 = Game.apply(s, d, GameEvent.BRIEFING_READ)
        s = u1.state
        assertEquals(1, s.streak)
        assertTrue(u1.newBadges.any { it.id == "premier_pas" })
        val u2 = Game.apply(s, d.plusDays(1), GameEvent.PHONE_CLEANED, freed = 2L shl 30)
        assertEquals(2, u2.state.streak)
        assertTrue(u2.newBadges.any { it.id == "giga" })
        // Un défi coché à la main rapporte 40 XP une seule fois.
        val manual = Game.challengesFor(d.plusDays(1)).first { it.manual }
        val u3 = Game.apply(u2.state, d.plusDays(1), manualChallenge = manual.id)
        assertEquals(u2.state.xp + 40, u3.state.xp)
        assertEquals(u3.state.xp, Game.apply(u3.state, d.plusDays(1), manualChallenge = manual.id).state.xp)
        assertTrue(Game.challengeSucceeded(manual, u3.state))
        // Persistance.
        assertEquals(u3.state, GameState.fromJson(u3.state.toJson()))
        assertNotNull(GameState.fromJson("oups"))
    }
}
