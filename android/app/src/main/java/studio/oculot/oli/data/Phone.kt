package studio.oculot.oli.data

import android.Manifest
import android.app.AppOpsManager
import android.app.KeyguardManager
import android.app.admin.DevicePolicyManager
import android.app.usage.StorageStatsManager
import android.content.ContentUris
import android.content.Context
import android.content.IntentSender
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.storage.StorageManager
import android.provider.MediaStore
import android.provider.Settings
import androidx.core.content.ContextCompat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import studio.oculot.oli.core.AppFact
import studio.oculot.oli.core.FileItem
import studio.oculot.oli.core.Move
import studio.oculot.oli.core.SecurityFacts
import studio.oculot.oli.core.Sensitivity
import studio.oculot.oli.core.Tidy
import java.io.File
import java.security.MessageDigest

/** Accès au téléphone pour l'audit, le nettoyage et le rangement. Aucune suppression sans confirmation. */
object Phone {

    // Audit de sécurité

    @Suppress("DEPRECATION")
    suspend fun securityFacts(context: Context): SecurityFacts = withContext(Dispatchers.IO) {
        val pm = context.packageManager
        val cr = context.contentResolver
        val accessibility = Settings.Secure.getString(cr, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES).orEmpty()
        val listeners = Settings.Secure.getString(cr, "enabled_notification_listeners").orEmpty()
        val admins = runCatching {
            context.getSystemService(DevicePolicyManager::class.java)?.activeAdmins?.map { it.packageName }?.toSet()
        }.getOrNull() ?: emptySet()
        val appOps = context.getSystemService(AppOpsManager::class.java)

        val packages: List<PackageInfo> = runCatching {
            if (Build.VERSION.SDK_INT >= 33) pm.getInstalledPackages(PackageManager.PackageInfoFlags.of(PackageManager.GET_PERMISSIONS.toLong()))
            else pm.getInstalledPackages(PackageManager.GET_PERMISSIONS)
        }.getOrDefault(emptyList())

        val apps = packages.mapNotNull { p ->
            val ai = p.applicationInfo ?: return@mapNotNull null
            if (ai.flags and (ApplicationInfo.FLAG_SYSTEM or ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0) return@mapNotNull null
            val installer = runCatching {
                if (Build.VERSION.SDK_INT >= 30) pm.getInstallSourceInfo(p.packageName).installingPackageName
                else pm.getInstallerPackageName(p.packageName)
            }.getOrNull()
            val granted = HashSet<String>()
            val requested = p.requestedPermissions.orEmpty()
            requested.forEachIndexed { i, perm ->
                val flags = p.requestedPermissionsFlags?.getOrNull(i) ?: 0
                if (flags and PackageInfo.REQUESTED_PERMISSION_GRANTED != 0) granted += perm
            }
            fun opAllowed(op: String) = runCatching {
                val mode = if (Build.VERSION.SDK_INT >= 29) appOps?.unsafeCheckOpNoThrow(op, ai.uid, p.packageName)
                           else appOps?.checkOpNoThrow(op, ai.uid, p.packageName)
                mode == AppOpsManager.MODE_ALLOWED
            }.getOrDefault(false)
            val s = HashSet<Sensitivity>()
            if (granted.any { it in setOf(Manifest.permission.READ_SMS, Manifest.permission.RECEIVE_SMS, Manifest.permission.SEND_SMS) }) s += Sensitivity.SMS
            if (accessibility.contains(p.packageName + "/")) s += Sensitivity.ACCESSIBILITY
            if (p.packageName in admins) s += Sensitivity.DEVICE_ADMIN
            if (listeners.contains(p.packageName + "/")) s += Sensitivity.NOTIFICATIONS
            if (Manifest.permission.ACCESS_BACKGROUND_LOCATION in granted) s += Sensitivity.BACKGROUND_LOCATION
            if (Manifest.permission.SYSTEM_ALERT_WINDOW in requested && opAllowed(AppOpsManager.OPSTR_SYSTEM_ALERT_WINDOW)) s += Sensitivity.OVERLAY
            if (Manifest.permission.REQUEST_INSTALL_PACKAGES in requested && opAllowed("android:request_install_packages")) s += Sensitivity.INSTALL_APPS
            AppFact(p.packageName, ai.loadLabel(pm).toString(), installer, s)
        }.sortedBy { it.label.lowercase() }

        SecurityFacts(
            screenLock = context.getSystemService(KeyguardManager::class.java)?.isDeviceSecure == true,
            securityPatch = Build.VERSION.SECURITY_PATCH,
            developerOptions = Settings.Global.getInt(cr, Settings.Global.DEVELOPMENT_SETTINGS_ENABLED, 0) == 1,
            usbDebugging = Settings.Global.getInt(cr, Settings.Global.ADB_ENABLED, 0) == 1,
            apps = apps,
        )
    }

    // Stockage

    data class Storage(val total: Long, val free: Long) { val used: Long get() = total - free }

    fun storage(context: Context): Storage? = runCatching {
        val ssm = context.getSystemService(StorageStatsManager::class.java)
        Storage(ssm.getTotalBytes(StorageManager.UUID_DEFAULT), ssm.getFreeBytes(StorageManager.UUID_DEFAULT))
    }.getOrNull()

    /** Permissions de lecture des photos et vidéos à demander selon la version d'Android. */
    fun mediaPermissions(): Array<String> = when {
        Build.VERSION.SDK_INT >= 33 -> arrayOf(Manifest.permission.READ_MEDIA_IMAGES, Manifest.permission.READ_MEDIA_VIDEO)
        Build.VERSION.SDK_INT >= 30 -> arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        else -> arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE, Manifest.permission.WRITE_EXTERNAL_STORAGE)
    }

    fun hasMedia(context: Context) = mediaPermissions().all { ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED }

    /** « Accès à tous les fichiers » (Android 11+) ; avant, la permission de stockage classique suffit. */
    fun hasAllFiles(context: Context): Boolean =
        if (Build.VERSION.SDK_INT >= 30) Environment.isExternalStorageManager() else hasMedia(context)

    private val downloadsDir: File get() = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)

    /** Photos et vidéos (MediaStore), plus les Téléchargements si l'accès à tous les fichiers est donné. */
    suspend fun scan(context: Context): List<FileItem> = withContext(Dispatchers.IO) {
        val out = ArrayList<FileItem>()
        if (hasMedia(context)) {
            out += queryMedia(context, MediaStore.Images.Media.EXTERNAL_CONTENT_URI, isImage = true)
            out += queryMedia(context, MediaStore.Video.Media.EXTERNAL_CONTENT_URI, isImage = false)
        }
        if (hasAllFiles(context)) {
            downloadsDir.walkTopDown().maxDepth(3).filter { it.isFile && !it.name.startsWith(".") }.forEach { f ->
                if (f.extension.lowercase() in setOf("jpg", "jpeg", "png", "heic", "webp", "gif", "mp4", "mov", "mkv", "webm")) {
                    // déjà vu par MediaStore : on marque seulement l'origine
                    val i = out.indexOfFirst { it.path.endsWith("Download") && it.name == f.name && it.size == f.length() }
                    if (i >= 0) { out[i] = out[i].copy(isDownload = true); return@forEach }
                }
                out += FileItem(f.absolutePath, f.name, f.parentFile?.name ?: "", f.length(), f.lastModified(), isDownload = true)
            }
        }
        out
    }

    private fun queryMedia(context: Context, collection: Uri, isImage: Boolean): List<FileItem> {
        val list = ArrayList<FileItem>()
        val proj = arrayOf(
            MediaStore.MediaColumns._ID, MediaStore.MediaColumns.DISPLAY_NAME, MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.DATE_MODIFIED, MediaStore.MediaColumns.BUCKET_DISPLAY_NAME,
            if (Build.VERSION.SDK_INT >= 29) MediaStore.MediaColumns.RELATIVE_PATH else MediaStore.MediaColumns.DATA,
        )
        runCatching {
            context.contentResolver.query(collection, proj, null, null, null)?.use { c ->
                while (c.moveToNext()) {
                    val id = c.getLong(0)
                    val name = c.getString(1) ?: continue
                    val bucket = c.getString(4).orEmpty()
                    val path = c.getString(5).orEmpty()
                    val shot = bucket.equals("Screenshots", true) || path.contains("Screenshots", true) || name.startsWith("Screenshot", true)
                    list += FileItem(ContentUris.withAppendedId(collection, id).toString(), name, path.trimEnd('/').ifEmpty { bucket },
                        c.getLong(2), c.getLong(3) * 1000, isScreenshot = shot,
                        isDownload = path.contains("Download", true), isImage = isImage)
                }
            }
        }
        return list
    }

    /** Empreinte SHA-256 du contenu (appelée seulement pour des photos de même taille). */
    fun hash(context: Context, item: FileItem): String? = runCatching {
        val md = MessageDigest.getInstance("SHA-256")
        val input = if (item.id.startsWith("content://")) context.contentResolver.openInputStream(Uri.parse(item.id)) else File(item.id).inputStream()
        input?.use { s ->
            val buf = ByteArray(64 * 1024)
            while (true) { val n = s.read(buf); if (n <= 0) break; md.update(buf, 0, n) }
        } ?: return null
        md.digest().joinToString("") { "%02x".format(it) }
    }.getOrNull()

    /**
     * Supprime les fichiers cochés, après la confirmation de l'utilisateur dans l'app.
     * Fichiers ordinaires (Téléchargements) : supprimés ici. Photos / vidéos : sur Android 11+,
     * on renvoie la demande système (createDeleteRequest) que l'écran doit afficher.
     */
    suspend fun delete(context: Context, items: List<FileItem>): Pair<Long, IntentSender?> = withContext(Dispatchers.IO) {
        var freed = 0L
        val (media, files) = items.partition { it.id.startsWith("content://") }
        val scanned = ArrayList<String>()
        for (f in files) {
            val file = File(f.id)
            if (file.exists() && file.delete()) { freed += f.size; scanned += file.absolutePath }
        }
        if (scanned.isNotEmpty()) MediaScannerConnection.scanFile(context, scanned.toTypedArray(), null, null)
        var sender: IntentSender? = null
        if (media.isNotEmpty()) {
            val uris = media.map { Uri.parse(it.id) }
            if (Build.VERSION.SDK_INT >= 30) {
                sender = MediaStore.createDeleteRequest(context.contentResolver, uris).intentSender
            } else {
                for ((i, u) in uris.withIndex()) {
                    if (runCatching { context.contentResolver.delete(u, null, null) }.getOrDefault(0) > 0) freed += media[i].size
                }
            }
        }
        freed to sender
    }

    // Rangement

    data class TidyPlan(val downloads: List<Move>, val screenshots: List<Move>) {
        val all: List<Move> get() = downloads + screenshots
    }

    private fun screenshotDirs(): List<File> = listOf(
        File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), "Screenshots"),
        File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DCIM), "Screenshots"),
    ).filter { it.isDirectory }

    suspend fun tidyPlan(): TidyPlan = withContext(Dispatchers.IO) {
        val dl = downloadsDir
        val rootFiles = dl.listFiles()?.filter { it.isFile }?.map { it.name }.orEmpty()
        val existing = Tidy.folders.flatMap { folder -> File(dl, folder).listFiles()?.map { it.absolutePath }.orEmpty() }.toSet()
        val downloads = Tidy.downloadsPlan(dl.absolutePath, rootFiles, existing)
        val shots = screenshotDirs().flatMap { dir ->
            val files = dir.listFiles()?.filter { it.isFile } .orEmpty()
            Tidy.screenshotPlan(dir.absolutePath, files.map { it.name to it.lastModified() }, files.map { it.absolutePath }.toSet(),
                java.time.ZoneId.systemDefault())
        }
        TidyPlan(downloads, shots)
    }

    /** Applique le plan validé. Renvoie le nombre de fichiers déplacés ou renommés. */
    suspend fun applyTidy(context: Context, moves: List<Move>): Int = withContext(Dispatchers.IO) {
        var n = 0
        val paths = ArrayList<String>()
        for (m in moves) {
            val from = File(m.from)
            val to = File(m.to)
            if (!from.exists() || to.exists()) continue
            to.parentFile?.mkdirs()
            if (from.renameTo(to)) { n++; paths += m.from; paths += m.to }
        }
        if (paths.isNotEmpty()) MediaScannerConnection.scanFile(context, paths.toTypedArray(), null, null)
        n
    }
}
