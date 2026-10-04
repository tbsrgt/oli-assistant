package studio.oculot.oli.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.json.JSONObject
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime

class AgendaApiTest {
    // Réponse d'exemple (forme lue dans app.js), sans vrai mot de passe.
    private val lire = """
        {"equipe":[
           {"id":"m1","nom":"Tobias","role":"admin","couleur":"#FF5B37"},
           {"id":"m2","nom":"Élliott","role":"equipe","couleur":"#FFD65C"},
           {"id":"m3","nom":"Tom","role":"equipe","couleur":"#22C55E"},
           {"id":"c9","nom":"Sarah","role":"closer","couleur":"#8888FF"}
         ],
         "moi":{"role":"equipe","membre":null},
         "rdv":[{"id":"r1","titre":"Point Martin"}]}
    """.trimIndent()

    @Test fun `lecture de lire`() {
        val r = AgendaApi.parseLire(200, lire).getOrThrow()
        assertEquals(listOf("Tobias", "Élliott", "Tom", "Sarah"), r.team.map { it.name })
        assertEquals("equipe", r.myRole)
        assertNull(r.myMemberId)
        assertEquals("#FF5B37", r.team[0].color)
    }

    @Test fun `erreur de mot de passe`() {
        val r = AgendaApi.parseLire(200, """{"erreur":"code invalide"}""")
        assertTrue(r.isFailure)
        assertEquals("Ce mot de passe n’est pas le bon. Vérifie-le et réessaie.", r.exceptionOrNull()!!.message)
        assertTrue(AgendaApi.parseLire(500, "oups").isFailure)
    }

    @Test fun `choix du membre`() {
        val r = AgendaApi.parseLire(200, lire).getOrThrow()
        val pick = AgendaApi.chooseMember(r, "elliott") as MemberChoice.Pick
        assertEquals(listOf("m1", "m2", "m3"), pick.candidates.map { it.id })   // pas de closer
        assertEquals("m2", pick.preselected)                                     // sans accent ni majuscule
        assertEquals("m1", (AgendaApi.chooseMember(r, "Tob") as MemberChoice.Pick).preselected)
        assertNull((AgendaApi.chooseMember(r, "") as MemberChoice.Pick).preselected)
        assertNull((AgendaApi.chooseMember(r, "Zoé") as MemberChoice.Pick).preselected)
    }

    @Test fun `un closer est reconnu directement`() {
        val json = lire.replace("""{"role":"equipe","membre":null}""", """{"role":"closer","membre":"c9"}""")
        val c = AgendaApi.chooseMember(AgendaApi.parseLire(200, json).getOrThrow())
        assertEquals("Sarah", (c as MemberChoice.Fixed).member.name)
    }

    @Test fun `lien ics`() {
        assertEquals("https://agenda.oculot.studio/ics/abc.ics",
            AgendaApi.parseLienIcs(200, """{"url":"https://agenda.oculot.studio/ics/abc.ics","webcal":"webcal://agenda.oculot.studio/ics/abc.ics"}""").getOrThrow())
        assertEquals("https://a.fr/x.ics", AgendaApi.parseLienIcs(200, """{"webcal":"webcal://a.fr/x.ics"}""").getOrThrow())
        assertTrue(AgendaApi.parseLienIcs(200, """{"erreur":"code invalide"}""").isFailure)
        assertTrue(AgendaApi.parseLienIcs(404, "").isFailure)
    }

    @Test fun `corps des requetes`() {
        val b = JSONObject(AgendaApi.lireBody("secret"))
        assertEquals("lire", b.getString("p_action")); assertEquals("secret", b.getString("p_code"))
        assertEquals(0, b.getJSONObject("p_args").length())
        val l = JSONObject(AgendaApi.lienIcsBody("secret", "m2"))
        assertEquals("lien_ics", l.getString("type")); assertEquals("m2", l.getString("membre"))
    }
}

class MacLinkTest {
    @Test fun `lecture du QR de jumelage`() {
        val p = MacLink.parsePairLink("oli://pair?host=192.168.1.24&port=47621&token=ab+c%2Fd_9&name=MacBook%20de%20Tobias").getOrThrow()
        assertEquals("192.168.1.24", p.host)
        assertEquals(47621, p.port)
        assertEquals("ab+c/d_9", p.token)
        assertEquals("MacBook de Tobias", p.name)
        assertEquals("http://192.168.1.24:47621", p.baseUrl)
    }

    @Test fun `liens refuses`() {
        assertTrue(MacLink.parsePairLink("https://oculot.studio").isFailure)
        assertTrue(MacLink.parsePairLink("oli://pair?host=192.168.1.2&token=x").isFailure)          // pas de port
        assertTrue(MacLink.parsePairLink("oli://pair?host=8.8.8.8&port=80&token=x").isFailure)      // pas local
        assertEquals("ton Mac", MacLink.parsePairLink("oli://pair?host=10.0.0.5&port=80&token=x").getOrThrow().name)
    }

    @Test fun `adresses locales`() {
        listOf("10.1.2.3", "172.16.0.1", "172.31.255.1", "192.168.0.10", "169.254.3.4", "mac-de-tobias.local", "fe80::1")
            .forEach { assertTrue(it, MacLink.isLocalHost(it)) }
        listOf("172.32.0.1", "8.8.8.8", "oculot.studio", "192.169.0.1", "")
            .forEach { assertFalse(it, MacLink.isLocalHost(it)) }
    }

    @Test fun `reponse du chat`() {
        val ok = MacLink.parseChat(200, """{"reply":"Bonjour !","session":"s-1"}""") as ChatResult.Ok
        assertEquals("Bonjour !", ok.reply); assertEquals("s-1", ok.session)
        assertEquals("Claude est occupé", (MacLink.parseChat(503, """{"error":"Claude est occupé"}""") as ChatResult.Error).message)
        assertTrue((MacLink.parseChat(401, "") as ChatResult.Error).message.contains("jumelage"))
        assertTrue(MacLink.parseChat(200, "pas du json") is ChatResult.Error)
        val body = JSONObject(MacLink.chatBody("Salut", null))
        assertTrue(body.isNull("session")); assertEquals("Salut", body.getString("message"))
    }

    @Test fun `statut du mac`() {
        val s = MacLink.parseStatus("""{"name":"MacBook","claude":true,"model":"sonnet"}""")!!
        assertEquals("MacBook", s.name); assertTrue(s.claude); assertEquals("sonnet", s.model)
        assertNull(MacLink.parseStatus("<html>"))
    }
}

class AutomationsTest {
    private val paris = ZoneId.of("Europe/Paris")

    @Test fun `heure du briefing`() {
        val before = ZonedDateTime.of(2026, 10, 5, 7, 0, 0, 0, paris)
        assertEquals(ZonedDateTime.of(2026, 10, 5, 8, 30, 0, 0, paris), Automations.nextBriefing(before))
        val after = ZonedDateTime.of(2026, 10, 5, 8, 30, 0, 0, paris)
        assertEquals(ZonedDateTime.of(2026, 10, 6, 8, 30, 0, 0, paris), Automations.nextBriefing(after))
        // Passage à l'heure d'hiver (25 oct. 2026) : toujours 8 h 30 heure locale.
        val dst = Automations.nextBriefing(ZonedDateTime.of(2026, 10, 24, 22, 0, 0, 0, paris))
        assertEquals(LocalTime.of(8, 30), dst.toLocalTime())
        assertEquals(LocalDate.of(2026, 10, 25), dst.toLocalDate())
    }

    private fun ev(id: String, start: String, location: String = "", description: String = "", allDay: Boolean = false) =
        AgendaEvent(id, "RDV $id", Instant.parse(start), Instant.parse(start).plusSeconds(3600), allDay, location, description)

    @Test fun `rappels 10 min avant`() {
        val now = Instant.parse("2026-10-05T08:00:00Z")
        val events = listOf(
            ev("a", "2026-10-05T08:05:00Z"),                                   // trop tard pour le rappel
            ev("b", "2026-10-05T09:00:00Z", location = "https://meet.google.com/abc-defg-hij"),
            ev("c", "2026-10-05T10:00:00Z", location = "12 rue de la Paix, Marseille"),
            ev("d", "2026-10-06T00:00:00Z", allDay = true),
            ev("e", "2026-10-05T11:00:00Z", location = "Visio", description = "Rejoindre : https://us02web.zoom.us/j/123?pwd=x."),
        )
        val r = Automations.reminders(events, now)
        assertEquals(listOf("b", "c", "e"), r.map { it.id })
        assertEquals(Instant.parse("2026-10-05T08:50:00Z"), r[0].triggerAt)
        assertEquals("https://meet.google.com/abc-defg-hij", r[0].joinUrl); assertNull(r[0].address)
        assertNull(r[1].joinUrl); assertEquals("12 rue de la Paix, Marseille", r[1].address)
        assertEquals("https://us02web.zoom.us/j/123?pwd=x", r[2].joinUrl); assertNull(r[2].address)
    }

    @Test fun `texte du briefing`() {
        val now = Instant.parse("2026-10-05T06:30:00Z")
        val events = listOf(ev("a", "2026-10-05T08:00:00Z"), ev("b", "2026-10-06T08:00:00Z"))
        val projects = listOf(
            EspaceProject("p1", "Martin", "refonte", "2026-10-03", -2, "Contenus", 1, 3, ""),
            EspaceProject("p2", "Durand", "creation", "2026-10-07", 2, "Maquette", 0, 3, ""),
            EspaceProject("p3", "Loin", "creation", "2026-11-07", 33, "Brief", 0, 3, ""),
        )
        val sites = listOf(SiteCheck("b.fr", "https://b.fr", status = SiteStatus.DOWN))
        val b = Automations.briefing(events, projects, sites, now, paris)
        assertEquals("Bonjour ! Un œil sur les sites ce matin", b.title)
        assertEquals("1 rendez-vous : 10:00 RDV a\nProjets : Martin en retard (J+2), Durand à J-2\nSite en panne : b.fr", b.body)
        val calm = Automations.briefing(emptyList(), emptyList(), emptyList(), now, paris)
        assertEquals("Bonjour ! Journée calme", calm.title)
    }

    @Test fun `veille de mise en ligne, une seule fois`() {
        val p = EspaceProject("p1", "Martin", "refonte", "2026-10-06", 1, "Recette", 2, 3, "")
        val (early, m0) = Automations.deadlinesToNotify(listOf(p), emptySet(), 7)
        assertTrue(early.isEmpty())
        val (first, m1) = Automations.deadlinesToNotify(listOf(p), m0, 10)
        assertEquals(listOf("p1"), first.map { it.id })
        val (again, m2) = Automations.deadlinesToNotify(listOf(p), m1, 15)
        assertTrue(again.isEmpty())
        val (_, m3) = Automations.deadlinesToNotify(listOf(p.copy(daysLeft = 0)), m2, 9)
        assertTrue(m3.isEmpty())
        val done = p.copy(stepsDone = 3)
        assertTrue(Automations.deadlinesToNotify(listOf(done), emptySet(), 10).first.isEmpty())
    }

    @Test fun `regle des 5 minutes pour le verrou`() {
        val t = 1_000_000_000L
        assertTrue(Automations.needsUnlock(null, t, unlockedOnce = false))                // démarrage à froid
        assertFalse(Automations.needsUnlock(null, t, unlockedOnce = true))                // jamais parti
        assertFalse(Automations.needsUnlock(t, t + 4 * 60_000, unlockedOnce = true))      // 4 min
        assertFalse(Automations.needsUnlock(t, t + 5 * 60_000, unlockedOnce = true))      // pile 5 min
        assertTrue(Automations.needsUnlock(t, t + 5 * 60_000 + 1, unlockedOnce = true))   // plus de 5 min
    }

    @Test fun `retour en ligne d'un site`() {
        val ok = SiteCheck("a", "https://a.fr", status = SiteStatus.OK)
        val down = SiteCheck("b", "https://b.fr", status = SiteStatus.DOWN)
        assertEquals(listOf("https://a.fr"), Sites.recoveries(listOf(ok, down), setOf("https://a.fr", "https://b.fr")).map { it.url })
        assertTrue(Sites.recoveries(listOf(ok), emptySet()).isEmpty())
    }
}
