package org.zxor.oronbox

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

class WristBoxUpdates(private val activity: Activity, messenger: BinaryMessenger) {
    init {
        MethodChannel(messenger, "wristbox/updates").setMethodCallHandler { call, result ->
            try {
                val pm = activity.packageManager
                val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
                val current = pm.getPackageInfo(activity.packageName, flags)
                fun code(p: android.content.pm.PackageInfo): Long = if (Build.VERSION.SDK_INT >= 28) p.longVersionCode else p.versionCode.toLong()
                when (call.method) {
                    "version" -> result.success(mapOf("version" to current.versionName, "build" to code(current)))
                    "install" -> {
                        val file = File(call.argument<String>("path") ?: "").canonicalFile
                        val root = File(activity.cacheDir, "wristbox-updates").canonicalFile
                        require(file.parentFile == root && file.extension == "apk" && file.isFile) { "更新包位置无效，请重新下载" }
                        val incoming = pm.getPackageArchiveInfo(file.path, flags) ?: error("无法读取更新包")
                        require(incoming.packageName == activity.packageName) { "更新包不属于 WristBox" }
                        val expected = call.argument<Number>("build")?.toLong() ?: 0
                        require(code(incoming) == expected && expected > code(current)) { "更新版本信息不匹配，请重新检查更新" }
                        fun signatures(p: android.content.pm.PackageInfo): Set<String> {
                            val values = if (Build.VERSION.SDK_INT >= 28) p.signingInfo?.apkContentsSigners else p.signatures
                            return values?.map { it.toCharsString() }?.toSet() ?: emptySet()
                        }
                        require(signatures(current).isNotEmpty() && signatures(incoming) == signatures(current)) { "更新包签名不一致，已阻止安装" }
                        if (!pm.canRequestPackageInstalls()) {
                            activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}")))
                            result.success("permission_required")
                        } else {
                            val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updateprovider", file)
                            activity.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                            result.success("installer_opened")
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("update_install", e.message ?: "无法打开系统安装界面", null)
            }
        }
    }
}
