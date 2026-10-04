package studio.oculot.oli.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

class SitesTest {
    private val t = SiteTarget("oculot.studio", "https://oculot.studio")
    private val now = 1_800_000_000_000L
    private val farTls = now + 90L * 86_400_000

    @Test fun `un echec isole ne met pas le site en panne, deux oui`() {
        val ok = Sites.evaluate(null, t, ProbeResult(httpCode = 200, latencyMs = 300, tlsExpiresAtMs = farTls), now)
        assertEquals(SiteStatus.OK, ok.status)
        val once = Sites.evaluate(ok, t, ProbeResult(error = "délai dépassé (15 s)"), now)
        assertEquals(SiteStatus.OK, once.status)
        assertEquals(1, once.consecutiveFailures)
        val twice = Sites.evaluate(once, t, ProbeResult(httpCode = 503), now)
        assertEquals(SiteStatus.DOWN, twice.status)
        assertEquals("HTTP 503", twice.reason(now))
        val back = Sites.evaluate(twice, t, ProbeResult(httpCode = 200, latencyMs = 200), now)
        assertEquals(SiteStatus.OK, back.status)
        assertEquals(0, back.consecutiveFailures)
    }

    @Test fun `hors ligne cote telephone ne compte pas`() {
        val ok = Sites.evaluate(null, t, ProbeResult(httpCode = 200), now)
        val off = Sites.evaluate(ok, t, ProbeResult(offline = true), now)
        assertEquals(ok, off)
    }

    @Test fun `avertissements 404, lenteur, certificat`() {
        assertEquals("HTTP 404", Sites.evaluate(null, t, ProbeResult(httpCode = 404, tlsExpiresAtMs = farTls), now).reason(now))
        val slow = Sites.evaluate(null, t, ProbeResult(httpCode = 200, latencyMs = 5200, tlsExpiresAtMs = farTls), now)
        assertEquals(SiteStatus.WARNING, slow.status)
        assertEquals("lent · 5,2 s", slow.reason(now))
        val tls = Sites.evaluate(null, t, ProbeResult(httpCode = 200, tlsExpiresAtMs = now + 5L * 86_400_000), now)
        assertEquals("certificat expire dans 5 j", tls.reason(now))
        assertEquals(SiteStatus.OK, Sites.evaluate(null, t, ProbeResult(httpCode = 401, tlsExpiresAtMs = farTls), now).status)
    }

    @Test fun `une seule notification par panne`() {
        val down = SiteCheck("a", "https://a.fr", status = SiteStatus.DOWN)
        val (first, mem1) = Sites.outagesToNotify(listOf(down), emptySet())
        assertEquals(1, first.size)
        val (second, mem2) = Sites.outagesToNotify(listOf(down), mem1)
        assertTrue(second.isEmpty())
        val (_, mem3) = Sites.outagesToNotify(listOf(down.copy(status = SiteStatus.OK)), mem2)
        assertTrue(mem3.isEmpty())
        val (again, _) = Sites.outagesToNotify(listOf(down), mem3)
        assertEquals(1, again.size)
    }

    @Test fun `liste des sites`() {
        val list = Sites.targets("oculot.studio\n\n# commentaire\nhttps://www.exemple.fr/\noculot.studio\n",
            espace = listOf("Boulangerie Martin" to "https://boulangerie-martin.fr", "Vide" to ""))
        assertEquals(listOf("Boulangerie Martin", "oculot.studio", "exemple.fr"), list.map { it.name })
        assertEquals("https://oculot.studio", list[1].url)
    }
}

class EspaceTest {
    private val json = """
        {"clients":[
          {"id":"c1","name":"Boulangerie Martin","kind":"refonte","dueAt":"2026-10-01","liveUrl":"https://b.fr",
           "steps":[{"label":"Maquette","state":"done"},{"label":"Contenus","state":"doing"},{"label":"Mise en ligne","state":"todo"}]},
          {"id":"c2","name":"Plombier Durand","kind":"creation","dueAt":"2026-10-10",
           "steps":[{"label":"Brief","state":"todo"}]},
          {"id":"c3","name":"Archivé","archived":true},
          {"id":"c4","name":"Sans date","kind":"autre","dueAt":null,"steps":[]}
        ]}
    """.trimIndent()

    @Test fun `lecture du resume`() {
        val p = Espace.parseSummary(json, today = LocalDate.of(2026, 10, 4))
        assertEquals(listOf("Boulangerie Martin", "Plombier Durand", "Sans date"), p.map { it.name })
        val late = p[0]
        assertEquals(-3L, late.daysLeft)
        assertTrue(late.isLate)
        assertEquals("Contenus", late.stepLabel)
        assertEquals(1, late.stepsDone); assertEquals(3, late.stepsTotal)
        assertEquals("J+3", late.daysLabel)
        assertEquals("J-6", p[1].daysLabel)
        assertEquals("Création", p[1].kindLabel)
        assertNull(p[2].daysLeft)
        assertEquals("sans date", p[2].daysLabel)
        assertEquals("Pas d’étape", p[2].stepLabel)
    }

    @Test fun `adresse de l'espace`() {
        assertEquals("https://espace.oculot.studio/api/espace/summary", Espace.summaryUrl(""))
        assertEquals("https://test.example/api/espace/summary", Espace.summaryUrl(" test.example/ "))
    }
}

class IcsTest {
    private val paris = ZoneId.of("Europe/Paris")
    private val ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:a
        DTSTART:20261005T080000Z
        DTEND:20261005T090000Z
        SUMMARY:Point client\, Martin
        LOCATION:12 rue de la Paix\, Marseille
        END:VEVENT
        BEGIN:VEVENT
        UID:b
        DTSTART;TZID=Europe/Paris:20261006T140000
        DURATION:PT30M
        SUMMARY:Appel
         Durand
        RRULE:FREQ=DAILY;COUNT=3
        EXDATE;TZID=Europe/Paris:20261007T140000
        BEGIN:VALARM
        SUMMARY:ne pas lire
        END:VALARM
        END:VEVENT
        BEGIN:VEVENT
        UID:c
        DTSTART;VALUE=DATE:20261009
        SUMMARY:Salon
        END:VEVENT
        BEGIN:VEVENT
        UID:d
        STATUS:CANCELLED
        DTSTART:20261005T100000Z
        SUMMARY:Annulé
        END:VEVENT
        BEGIN:VEVENT
        UID:e
        DTSTART:20260101T100000Z
        SUMMARY:Passé
        END:VEVENT
        END:VCALENDAR
    """.trimIndent().replace("\n", "\r\n")

    @Test fun `lecture ical simple`() {
        val now = Instant.parse("2026-10-04T12:00:00Z")
        val ev = Ics.parse(ics, now = now, zone = paris)
        assertEquals(listOf("Point client, Martin", "AppelDurand", "AppelDurand", "Salon"), ev.map { it.title })
        assertEquals("12 rue de la Paix", ev[0].shortLocation)
        assertEquals("10:00", ev[0].timeLabel(paris))
        assertEquals(Instant.parse("2026-10-06T12:00:00Z"), ev[1].start)
        assertEquals(Instant.parse("2026-10-08T12:00:00Z"), ev[2].start)   // le 7 est exclu (EXDATE)
        assertEquals(30L, java.time.Duration.between(ev[1].start, ev[1].end).toMinutes())
        assertTrue(ev[3].isAllDay)
        assertEquals("Journée", ev[3].timeLabel(paris))
        assertEquals("demain", ev[0].dayLabel(LocalDate.of(2026, 10, 4), paris))
    }

    @Test fun `duree iso`() {
        assertEquals(5400L, Ics.parseDuration("PT1H30M")!!.seconds)
        assertEquals(86400L + 7200, Ics.parseDuration("P1DT2H")!!.seconds)
    }
}
