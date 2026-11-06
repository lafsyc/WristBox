package org.zxor.oronbox

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.InputStream
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Selected-file or authorized log-folder access. No log cache or upload. */
class WristLogImport(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "wristbox/log_import")
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val prefs = activity.getSharedPreferences("wristbox_log_import", 0)
    private var pending: MethodChannel.Result? = null
    @Volatile private var stream: InputStream? = null
    @Volatile private var closed = false
    private class UserError(val code: String, message: String) : Exception(message)
    private data class Source(val name: String, val size: Long, val modified: Long, val uri: Uri? = null, val file: File? = null)
    companion object { const val REQUEST = 0x5A35; const val FOLDER_REQUEST = 0x5A36 }

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "openHealth" -> try {
                    val intent = listOf("com.mi.health", "com.xiaomi.wearable")
                        .firstNotNullOfOrNull { activity.packageManager.getLaunchIntentForPackage(it) }
                    if (intent == null) result.error("HEALTH", "未找到小米运动健康，请从手机桌面手动打开", null)
                    else { activity.startActivity(intent); result.success(null) }
                } catch (_: Exception) { result.error("HEALTH", "无法打开运动健康，请从桌面手动打开", null) }
                "scanLatest" -> work(result) { cancelled -> latest(call.argument<Number>("notBefore")?.toLong() ?: 0L, cancelled) }
                "pick", "grantFolder" -> {
                    if (pending != null) result.error("BUSY", "请先完成当前日志操作", null)
                    else try {
                        pending = result
                        val folder = call.method == "grantFolder"
                        val intent = Intent(if (folder) Intent.ACTION_OPEN_DOCUMENT_TREE else Intent.ACTION_OPEN_DOCUMENT).apply {
                            putExtra(Intent.EXTRA_LOCAL_ONLY, true)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            if (folder) {
                                addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                                putExtra(DocumentsContract.EXTRA_INITIAL_URI, Uri.parse("content://com.android.externalstorage.documents/document/primary%3ADownload%2Fwearablelog"))
                            } else { type = "*/*"; addCategory(Intent.CATEGORY_OPENABLE) }
                        }
                        activity.startActivityForResult(intent, if (folder) FOLDER_REQUEST else REQUEST)
                    } catch (_: Exception) { pending = null; result.error("PICK", "无法打开系统文件选择器", null) }
                }
                "forgetFolder" -> {
                    if (pending != null) result.error("BUSY", "请先完成当前日志操作", null)
                    else {
                        prefs.getString("folder", null)?.let { release(Uri.parse(it)) }
                        prefs.edit().remove("folder").apply(); result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun release(uri: Uri) { try { activity.contentResolver.releasePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) } catch (_: Exception) {} }
    fun onActivityResult(request: Int, code: Int, data: Intent?): Boolean {
        if (request != REQUEST && request != FOLDER_REQUEST) return false
        val result = pending ?: return true
        pending = null
        val uri = data?.data
        if (code != Activity.RESULT_OK || uri == null) { result.success(if (request == FOLDER_REQUEST) false else null); return true }
        if (request == FOLDER_REQUEST) {
            try {
                val name = DocumentsContract.getTreeDocumentId(uri).substringAfterLast('/').lowercase()
                if (uri.authority != "com.android.externalstorage.documents" || name !in listOf("wearablelog", "researchlog"))
                    throw UserError("FOLDER", "请选择手机 Download 下的 wearablelog 或 ResearchLog 文件夹；先导出一次日志，再授权文件夹")
                activity.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                val old = prefs.getString("folder", null)
                prefs.edit().putString("folder", uri.toString()).apply()
                if (old != null && old != uri.toString()) release(Uri.parse(old))
                result.success(true)
            } catch (e: Exception) { result.error("FOLDER", if (e is UserError) e.message else "无法保存日志文件夹权限，请重新授权", null) }
        } else work(result) { _ ->
            if (uri.scheme != "content") throw UserError("FILE", "请选择本地日志文件")
            var name = ""; var size = -1L
            activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use {
                if (it.moveToFirst()) { name = it.getString(0) ?: ""; if (!it.isNull(1)) size = it.getLong(1) }
            }
            if (!name.endsWith(".zip", true) && !name.endsWith(".log", true) && !name.endsWith(".txt", true) && !WristLogLocator.supported(name))
                throw UserError("FILE", "请选择运动健康日志 ZIP、LOG 或 TXT 文件")
            Source(name, size, 0, uri = uri)
        }
        return true
    }

    private fun latest(notBefore: Long, cancelled: AtomicBoolean): Source {
        val saved = prefs.getString("folder", null)
        if (saved != null) {
            try { return latestInTree(Uri.parse(saved), notBefore, cancelled) }
            catch (_: SecurityException) { throw UserError("LOG_FOLDER_REQUIRED", "日志文件夹授权已失效，请重新授权") }
        }
        if (Build.VERSION.SDK_INT >= 30 && Environment.isExternalStorageManager()) {
            val downloads = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            val file = WristLogLocator.latest(arrayOf(File(downloads, "wearablelog"), File(downloads, "ResearchLog")), notBefore)
                ?: throw missing(notBefore)
            return Source(file.name, file.length(), file.lastModified(), file = file)
        }
        throw UserError("LOG_FOLDER_REQUIRED", "首次自动读取需要授权日志文件夹，授权后无需逐个选择日志")
    }
    private fun missing(notBefore: Long) = UserError("NO_LOG", if (notBefore > 0) "未发现本次新导出的日志，请完成导出后点击“自动读取最新日志”" else "未找到日志，请先在运动健康导出，并确认授权的日志文件夹是否正确")

    private fun latestInTree(tree: Uri, notBefore: Long, cancelled: AtomicBoolean): Source {
        val queue = ArrayDeque<Pair<String, Int>>()
        queue.add(DocumentsContract.getTreeDocumentId(tree) to 0)
        val seen = mutableSetOf<String>()
        var count = 0; var newest: Source? = null
        while (queue.isNotEmpty()) {
            if (closed || cancelled.get()) throw UserError("CANCELLED", "读取已取消")
            val (parent, depth) = queue.removeFirst()
            if (!seen.add(parent)) continue
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parent)
            val columns = arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE, DocumentsContract.Document.COLUMN_SIZE, DocumentsContract.Document.COLUMN_LAST_MODIFIED)
            activity.contentResolver.query(children, columns, null, null, null)?.use { cursor ->
                while (cursor.moveToNext()) {
                    if (closed || cancelled.get()) throw UserError("CANCELLED", "读取已取消")
                    if (++count > 2048) throw UserError("LIMIT", "日志文件过多，请整理日志文件夹后重试")
                    val id = cursor.getString(0) ?: continue
                    if (cursor.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) {
                        if (depth < 3) queue.add(id to depth + 1)
                        continue
                    }
                    val name = cursor.getString(1) ?: continue
                    val size = if (cursor.isNull(3)) -1L else cursor.getLong(3)
                    val modified = if (cursor.isNull(4)) 0L else cursor.getLong(4)
                    if (!WristLogLocator.supported(name) || size == 0L || modified < notBefore) continue
                    val previous = newest
                    if (previous == null || modified > previous.modified || (modified == previous.modified && name > previous.name))
                        newest = Source(name, size, modified, uri = DocumentsContract.buildDocumentUriUsingTree(tree, id))
                }
            }
        }
        return newest ?: throw missing(notBefore)
    }

    private fun work(result: MethodChannel.Result, locate: (AtomicBoolean) -> Source) {
        if (pending != null) { result.error("BUSY", "请先完成当前日志操作", null); return }
        pending = result
        val cancelled = AtomicBoolean(false)
        main.postDelayed({
            if (!closed && pending === result) {
                cancelled.set(true); pending = null
                try { stream?.close() } catch (_: Exception) {}
                result.error("TIMEOUT", "日志读取超时，请选择较小的本地日志", null)
            }
        }, 35_000)
        executor.execute {
            try {
                val source = locate(cancelled)
                if (closed || cancelled.get()) throw UserError("CANCELLED", "读取已取消")
                if (source.size > 32L * 1024 * 1024) throw UserError("SIZE", "最新日志超过 32 MB，请重新导出较小日志或手动选择其他日志")
                val input = source.file?.inputStream() ?: activity.contentResolver.openInputStream(source.uri!!)
                    ?: throw UserError("FILE", "无法读取日志，请重新授权或手动选择日志")
                val rows = input.use {
                    stream = it
                    if (closed || cancelled.get()) throw UserError("CANCELLED", "读取已取消")
                    WristLogReader().read(it, source.name.endsWith(".zip", true))
                }
                main.post { if (!closed && pending === result) { pending = null; result.success(mapOf("name" to source.name.take(120), "modified" to source.modified, "records" to rows)) } }
            } catch (e: Exception) {
                val message = if (e is WristLogReader.LogReadException || e is UserError) e.message else "日志读取失败，请重新授权文件夹或手动选择日志"
                main.post { if (!closed && pending === result) { pending = null; result.error(if (e is UserError) e.code else "LOG_IMPORT", message, null) } }
            } finally { stream = null }
        }
    }
    fun close() {
        closed = true
        try { stream?.close() } catch (_: Exception) {}
        pending?.error("CLOSED", "日志读取已取消", null); pending = null
        channel.setMethodCallHandler(null); executor.shutdownNow()
    }
}
