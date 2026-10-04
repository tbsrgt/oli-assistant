package studio.oculot.oli.core

import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

// Nettoyage et rangement : règles pures. Rien n'est supprimé ni déplacé ici, on ne fait que proposer.

/** Un fichier vu par le scan. `id` : URI MediaStore ou chemin absolu. */
data class FileItem(
    val id: String,
    val name: String,
    val path: String,
    val size: Long,
    val modifiedMs: Long,
    val isScreenshot: Boolean = false,
    val isDownload: Boolean = false,
    val isImage: Boolean = false,
)

enum class CleanCategory(val title: String, val help: String) {
    DUPLICATES("Photos en double", "Même taille, même contenu : je garde la plus ancienne."),
    LARGE("Gros fichiers", "Plus de 100 Mo chacun."),
    OLD_DOWNLOADS("Vieux téléchargements", "Pas touchés depuis plus de 90 jours."),
    OLD_SCREENSHOTS("Vieilles captures d’écran", "Plus de 90 jours."),
    APKS("APK oubliés", "Fichiers d’installation d’apps, inutiles une fois l’app installée."),
}

data class Candidate(val item: FileItem, val category: CleanCategory, val note: String = "")

object Cleanup {
    const val LARGE_BYTES = 100L * 1024 * 1024
    const val OLD_DAYS = 90L
    private const val DAY_MS = 86_400_000L

    /**
     * Range les fichiers par catégorie. Un fichier n'apparaît qu'une fois (première catégorie qui
     * s'applique, dans l'ordre de l'énumération). `hash` n'est appelé que pour les photos de même taille.
     */
    fun classify(items: List<FileItem>, nowMs: Long, hash: (FileItem) -> String?): Map<CleanCategory, List<Candidate>> {
        val out = LinkedHashMap<CleanCategory, MutableList<Candidate>>()
        val taken = HashSet<String>()
        fun add(c: Candidate) { if (taken.add(c.item.id)) out.getOrPut(c.category) { mutableListOf() } += c }

        duplicates(items.filter { it.isImage }, hash).forEach { add(it) }
        items.filter { it.size >= LARGE_BYTES }.sortedByDescending { it.size }.forEach { add(Candidate(it, CleanCategory.LARGE)) }
        val old = nowMs - OLD_DAYS * DAY_MS
        items.filter { it.isDownload && it.modifiedMs in 1 until old && !it.name.endsWith(".apk", true) }
            .sortedBy { it.modifiedMs }.forEach { add(Candidate(it, CleanCategory.OLD_DOWNLOADS)) }
        items.filter { it.isScreenshot && it.modifiedMs in 1 until old }.sortedBy { it.modifiedMs }
            .forEach { add(Candidate(it, CleanCategory.OLD_SCREENSHOTS)) }
        items.filter { it.name.endsWith(".apk", true) }.forEach { add(Candidate(it, CleanCategory.APKS)) }
        return out
    }

    /** Doublons : même taille puis même empreinte. Le plus ancien est gardé, les autres proposés. */
    fun duplicates(images: List<FileItem>, hash: (FileItem) -> String?): List<Candidate> {
        val out = ArrayList<Candidate>()
        for (sameSize in images.filter { it.size > 0 }.groupBy { it.size }.values) {
            if (sameSize.size < 2) continue
            val byHash = sameSize.mapNotNull { f -> hash(f)?.let { it to f } }.groupBy({ it.first }, { it.second })
            for (group in byHash.values) {
                if (group.size < 2) continue
                val sorted = group.sortedWith(compareBy<FileItem> { it.modifiedMs }.thenBy { it.name })
                val keep = sorted.first()
                sorted.drop(1).forEach { out += Candidate(it, CleanCategory.DUPLICATES, "copie de ${keep.name}") }
            }
        }
        return out
    }

    fun human(bytes: Long): String = when {
        bytes >= 1L shl 30 -> String.format(java.util.Locale.FRANCE, "%.1f Go", bytes / (1L shl 30).toDouble())
        bytes >= 1L shl 20 -> String.format(java.util.Locale.FRANCE, "%.0f Mo", bytes / (1L shl 20).toDouble())
        bytes >= 1L shl 10 -> String.format(java.util.Locale.FRANCE, "%.0f Ko", bytes / (1L shl 10).toDouble())
        else -> "$bytes o"
    }
}

/** Un déplacement ou un renommage proposé : avant → après. */
data class Move(val from: String, val to: String, val label: String)

object Tidy {
    private val types = linkedMapOf(
        "Documents" to setOf("pdf", "doc", "docx", "odt", "rtf", "txt", "xls", "xlsx", "ods", "csv", "ppt", "pptx", "odp", "key", "pages", "numbers", "md", "epub"),
        "Images" to setOf("jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "svg", "bmp", "avif", "tif", "tiff"),
        "Vidéos" to setOf("mp4", "mov", "mkv", "webm", "avi", "m4v", "3gp"),
        "Archives" to setOf("zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz"),
        "APK" to setOf("apk", "apks", "xapk"),
    )
    val folders: List<String> get() = types.keys.toList()
    private val partial = setOf("crdownload", "part", "tmp", "download", "partial")

    fun folderFor(name: String): String? {
        val ext = name.substringAfterLast('.', "").lowercase()
        if (ext.isEmpty() || ext in partial || name.startsWith(".")) return null
        return types.entries.firstOrNull { ext in it.value }?.key
    }

    /**
     * Range les fichiers posés à la racine de Téléchargements dans des sous-dossiers par type.
     * `existing` : chemins déjà présents (pour éviter d'écraser un fichier du même nom).
     */
    fun downloadsPlan(downloadsDir: String, fileNames: List<String>, existing: Set<String>): List<Move> {
        val dir = downloadsDir.trimEnd('/')
        val used = HashSet(existing)
        val out = ArrayList<Move>()
        for (name in fileNames.sorted()) {
            val folder = folderFor(name) ?: continue
            val target = unique("$dir/$folder", name, used)
            used += target
            out += Move("$dir/$name", target, folder)
        }
        return out
    }

    private val screenshotFmt = DateTimeFormatter.ofPattern("yyyy-MM-dd 'à' HH.mm.ss")

    /** Renomme les captures d'écran par date : « Capture 2026-10-04 à 10.11.12.png ». */
    fun screenshotPlan(dir: String, files: List<Pair<String, Long>>, existing: Set<String>, zone: ZoneId): List<Move> {
        val d = dir.trimEnd('/')
        val used = HashSet(existing)
        val out = ArrayList<Move>()
        for ((name, modified) in files.sortedBy { it.second }) {
            if (name.startsWith("Capture ") || modified <= 0) continue
            val ext = name.substringAfterLast('.', "png")
            val base = "Capture " + screenshotFmt.format(Instant.ofEpochMilli(modified).atZone(zone)) + ".$ext"
            val target = unique(d, base, used)
            used += target
            out += Move("$d/$name", target, "Captures")
        }
        return out
    }

    /** « dossier/nom.ext », ou « nom (2).ext » si déjà pris. */
    fun unique(dir: String, name: String, used: Set<String>): String {
        var candidate = "$dir/$name"
        if (candidate !in used) return candidate
        val stem = name.substringBeforeLast('.', name)
        val ext = name.substringAfterLast('.', "").let { if (it.isEmpty() || it == name) "" else ".$it" }
        var i = 2
        while (true) {
            candidate = "$dir/$stem ($i)$ext"
            if (candidate !in used) return candidate
            i++
        }
    }
}
