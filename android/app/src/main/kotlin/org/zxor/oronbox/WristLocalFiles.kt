package org.zxor.oronbox

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

/** Enumerates metadata locally. Reads file content only when preparing an explicit install. */
class WristLocalFiles(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "wristbox/local_files")
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val prefs = activity.getSharedPreferences("wristbox_local_files", 0)
    private val sources = mutableMapOf<String, Source>()
    private var pendingFolder: MethodChannel.Result? = null
    private data class Source(val name: String, val file: File? = null, val uri: Uri? = null)
    companion object { const val FOLDER_REQUEST = 0x5A31; const val MAX_BYTES = 64L * 1024 * 1024 }

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(status())
                "grantAllFiles" -> try {
                    if (Build.VERSION.SDK_INT < 30) error("请使用添加文件夹授权")
                    try {
                        activity.startActivity(Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                            Uri.parse("package:${activity.packageName}")))
                    } catch (_: Exception) {
                        activity.startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
                    }
                    result.success(null)
                } catch (_: Exception) { result.error("ACCESS", "无法打开文件访问设置，请使用添加文件夹或系统选择文件", null) }
                "addFolder" -> {
                    if (pendingFolder != null) result.error("BUSY", "请先完成当前文件夹选择", null)
                    else try {
                        pendingFolder = result
                        activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                        }, FOLDER_REQUEST)
                    } catch (_: Exception) {
                        pendingFolder = null
                        result.error("FOLDER", "无法打开系统文件夹选择器", null)
                    }
                }
                "forgetFolders" -> {
                    for (value in folders()) try {
                        activity.contentResolver.releasePersistableUriPermission(Uri.parse(value), Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    } catch (_: Exception) {}
                    prefs.edit().remove("folders").apply()
                    result.success(null)
                }
                "scan" -> work(result) { scan(call.argument<Boolean>("foldersOnly") == true) }
                "prepare" -> work(result) { prepare(call.argument<String>("id") ?: "") }
                else -> result.notImplemented()
            }
        }
    }
    private fun folders() = prefs.getStringSet("folders", emptySet())!!.toSet()
    private fun allAccess() = Build.VERSION.SDK_INT >= 30 && Environment.isExternalStorageManager()
    private fun status(): Map<String, Any> = mapOf("allFiles" to allAccess(), "canAllFiles" to (Build.VERSION.SDK_INT >= 30), "folders" to folders().size)
    private fun work(result: MethodChannel.Result, action: () -> Any) {
        executor.execute {
            try { val value = action(); main.post { result.success(value) } }
            catch (e: Exception) { main.post { result.error("LOCAL_FILES", e.message ?: "本地文件读取失败，请刷新或重新授权", null) } }
        }
    }
    fun onActivityResult(request: Int, code: Int, data: Intent?): Boolean {
        if (request != FOLDER_REQUEST) return false
        val result = pendingFolder ?: return true
        pendingFolder = null
        val uri = data?.data
        if (code != Activity.RESULT_OK || uri == null) { result.success(false); return true }
        try {
            activity.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            prefs.edit().putStringSet("folders", folders() + uri.toString()).apply()
            result.success(true)
        } catch (_: Exception) { result.error("ACCESS", "此文件夹无法保持访问权限，请重新选择本地文件夹", null) }
        return true
    }
    private fun supported(name: String) = name.endsWith(".rpk", true) || name.endsWith(".bin", true)
    private fun scan(foldersOnly: Boolean): Map<String, Any> {
        val found = mutableListOf<Map<String, Any>>()
        val fresh = mutableMapOf<String, Source>()
        var visited = 0
        var limited = false
        var inaccessible = 0
        val deadline = System.currentTimeMillis() + 30_000
        fun stop(): Boolean {
            if (Thread.currentThread().isInterrupted || visited >= 100_000 || found.size >= 2000 || System.currentTimeMillis() > deadline) {
                limited = true; return true
            }
            return false
        }
        fun add(id: String, source: Source, directory: String, size: Long, modified: Long) {
            if (!supported(source.name) || fresh.containsKey(id)) return
            fresh[id] = source
            found.add(mapOf("id" to id, "name" to source.name, "directory" to directory,
                "size" to size.coerceAtLeast(0), "modified" to modified.coerceAtLeast(0)))
        }
        if (allAccess() && !foldersOnly) {
            val root = Environment.getExternalStorageDirectory().canonicalFile
            val stack = ArrayDeque<Pair<File, Int>>()
            stack.add(root to 0)
            while (stack.isNotEmpty() && !stop()) {
                val (directory, depth) = stack.removeLast()
                val children = directory.listFiles()
                if (children == null) { inaccessible++; continue }
                for (child in children.sortedBy { if (it.name.equals("Download", true) || it.name.equals("Downloads", true)) 1 else 0 }) {
                    visited++
                    if (stop()) break
                    if (child.name.startsWith(".")) continue
                    val canonical = try { child.canonicalFile } catch (_: Exception) { continue }
                    if (canonical.path != child.absolutePath || !canonical.path.startsWith(root.path + File.separator)) continue
                    val relative = canonical.relativeTo(root).invariantSeparatorsPath
                    if (relative == "Android/data" || relative == "Android/obb") continue
                    if (canonical.isDirectory && depth < 32) stack.add(canonical to depth + 1)
                    else if (canonical.isFile) add("file:${canonical.path}", Source(child.name, file = canonical),
                        canonical.parentFile!!.relativeTo(root).path.ifEmpty { "手机存储" }, canonical.length(), canonical.lastModified())
                }
            }
        } else {
            for (saved in folders()) {
                val tree = Uri.parse(saved)
                val stack = ArrayDeque<Triple<String, String, Int>>()
                try {
                    val treeId = DocumentsContract.getTreeDocumentId(tree)
                    var label = "已授权文件夹"
                    activity.contentResolver.query(DocumentsContract.buildDocumentUriUsingTree(tree, treeId),
                        arrayOf("_display_name"), null, null, null)?.use { cursor ->
                        if (cursor.moveToFirst()) label = cursor.getString(0) ?: label
                    }
                    stack.add(Triple(treeId, label, 0))
                }
                catch (_: Exception) { inaccessible++; continue }
                val seen = mutableSetOf<String>()
                while (stack.isNotEmpty() && !stop()) {
                    val (parentId, directory, depth) = stack.removeLast()
                    if (!seen.add(parentId)) continue
                    try {
                        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parentId)
                        val cols = arrayOf("document_id", "_display_name", "mime_type", "_size", "last_modified")
                        activity.contentResolver.query(childrenUri, cols, null, null, null)?.use { cursor ->
                            while (cursor.moveToNext() && !stop()) {
                                visited++
                                val id = cursor.getString(0)
                                val name = cursor.getString(1) ?: continue
                                if (cursor.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) {
                                    if (depth < 32) stack.add(Triple(id, "$directory/$name", depth + 1))
                                } else {
                                    val uri = DocumentsContract.buildDocumentUriUsingTree(tree, id)
                                    add(uri.toString(), Source(name, uri = uri), directory, cursor.getLong(3), cursor.getLong(4))
                                }
                            }
                        }
                    } catch (_: Exception) { inaccessible++ }
                }
            }
        }
        sources.clear(); sources.putAll(fresh)
        return status() + mapOf("files" to found.sortedByDescending { it["modified"] as Long },
            "limited" to limited, "inaccessible" to inaccessible)
    }
    private fun prepare(id: String): String {
        val source = sources[id] ?: error("文件列表已变化，请刷新后重新选择")
        if (!supported(source.name)) error("仅支持 RPK 和 BIN 文件")
        val cacheRoot = File(activity.cacheDir, "local-install").apply { mkdirs() }
        // Only stale copies in this private staging folder are removed; never the original download.
        cacheRoot.listFiles()?.filter { it.lastModified() < System.currentTimeMillis() - 7L * 86400_000 }?.forEach { it.deleteRecursively() }
        val directory = File(cacheRoot, UUID.randomUUID().toString()).apply { mkdirs() }
        val name = File(source.name).name.replace(Regex("[^\\p{L}\\p{N}._ -]"), "_")
        val ext = name.substringAfterLast('.').lowercase()
        val output = File(directory, name.substringBeforeLast('.').take(120) + ".$ext")
        try {
            val input = if (source.file != null) {
                if (!allAccess()) error("文件访问权限已关闭，请重新授权")
                if (source.file.canonicalPath != source.file.absolutePath) error("文件位置已变化，请刷新")
                source.file.inputStream()
            } else activity.contentResolver.openInputStream(source.uri!!) ?: error("文件已移动或无法读取")
            input.use { stream -> output.outputStream().use { dest ->
                val buffer = ByteArray(64 * 1024)
                var total = 0L
                while (true) {
                    val count = stream.read(buffer)
                    if (count < 0) break
                    total += count
                    if (total > MAX_BYTES) error("安装包不能超过 64 MB")
                    dest.write(buffer, 0, count)
                }
                if (total == 0L) error("文件为空，请重新下载完整安装包")
            } }
            return output.absolutePath
        } catch (_: java.io.FileNotFoundException) {
            directory.deleteRecursively(); error("文件已移动、删除或无访问权限，请刷新列表")
        } catch (e: Exception) {
            directory.deleteRecursively(); throw e
        }
    }
    fun close() { channel.setMethodCallHandler(null); pendingFolder?.error("CLOSED", "页面已关闭，请重新选择", null); pendingFolder = null; executor.shutdownNow() }
}
