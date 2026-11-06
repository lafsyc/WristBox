package org.zxor.oronbox

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/** Read only the image explicitly chosen by the user; no library-wide permission. */
class WristAvatarPicker(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "wristbox/avatar_picker")
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null
    private var closed = false
    companion object { const val REQUEST = 0x5A32; const val MAX_BYTES = 20 * 1024 * 1024 }

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "pick") result.notImplemented()
            else if (pending != null) result.error("BUSY", "请先完成当前图片选择", null)
            else {
                pending = result
                try {
                    val intent = if (Build.VERSION.SDK_INT >= 33) {
                        Intent(MediaStore.ACTION_PICK_IMAGES).apply { type = "image/*" }
                    } else {
                        Intent(Intent.ACTION_GET_CONTENT).apply { type = "image/*"; addCategory(Intent.CATEGORY_OPENABLE) }
                    }
                    try { activity.startActivityForResult(intent, REQUEST) }
                    catch (_: android.content.ActivityNotFoundException) {
                        activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            type = "image/*"; addCategory(Intent.CATEGORY_OPENABLE)
                        }, REQUEST)
                    }
                } catch (_: Exception) {
                    pending = null
                    result.error("PICKER", "无法打开相册，请改用从文件选择", null)
                }
            }
        }
    }

    fun onActivityResult(request: Int, resultCode: Int, data: Intent?): Boolean {
        if (request != REQUEST) return false
        val result = pending ?: return true
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            pending = null; result.success(null); return true
        }
        val uri = data.data!!
        worker.execute {
            try {
                require(uri.scheme == "content")
                val bytes = activity.contentResolver.openInputStream(uri)?.use { input ->
                    val output = ByteArrayOutputStream()
                    val buffer = ByteArray(32768)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        if (output.size() + count > MAX_BYTES) throw IllegalArgumentException("图片不能超过 20 MB")
                        output.write(buffer, 0, count)
                    }
                    output.toByteArray()
                } ?: throw IllegalArgumentException("无法读取所选图片")
                main.post { if (!closed) { pending = null; result.success(bytes) } }
            } catch (error: Exception) {
                main.post { if (!closed) {
                    pending = null
                    result.error("IMAGE", if (error is IllegalArgumentException) error.message ?: "图片格式不可用" else "无法读取图片，请保存到本机后重试", null)
                } }
            }
        }
        return true
    }

    fun close() {
        closed = true
        channel.setMethodCallHandler(null)
        pending?.error("CLOSED", "图片选择已取消，请重试", null)
        pending = null
        worker.shutdownNow()
    }
}
