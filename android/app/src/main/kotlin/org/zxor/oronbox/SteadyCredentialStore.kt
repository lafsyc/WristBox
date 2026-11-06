package org.zxor.oronbox

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import android.util.Base64
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.security.KeyStore
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Android counterpart of the Windows credential channel. No plaintext backup. */
class SteadyCredentialStore(context: Context, messenger: BinaryMessenger) {
    private val file = AtomicFile(File(context.noBackupFilesDir, "steadylink-credentials.bin"))
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val alias = "steadylink.credentials.v1"

    init {
        MethodChannel(messenger, "steadylink/credentials").setMethodCallHandler { call, result ->
            if (call.method != "read" && call.method != "write") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            worker.execute {
                try {
                    val value = if (call.method == "read") read() else {
                        val plain = call.arguments as? String ?: error("Expected credential data")
                        require(plain.toByteArray(Charsets.UTF_8).size <= 4 * 1024 * 1024)
                        write(plain)
                        null
                    }
                    main.post { result.success(value) }
                } catch (_: Exception) {
                    // Do not expose key material, cookies or raw storage contents.
                    main.post { result.error("SECURE_STORAGE", "无法读取或保存本机加密凭据", null) }
                }
            }
        }
    }

    private fun key(create: Boolean): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        check(create) { "Credential key is missing" }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256).build())
        }.generateKey()
    }

    private fun read(): String? {
        if (!file.baseFile.exists() && !File(file.baseFile.path + ".bak").exists()) return null
        val bytes = file.readFully()
        require(bytes.size <= 6 * 1024 * 1024)
        val data = JSONObject(String(bytes, Charsets.UTF_8))
        require(data.getInt("version") == 1)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(false), GCMParameterSpec(128, Base64.decode(data.getString("iv"), Base64.NO_WRAP)))
        return String(cipher.doFinal(Base64.decode(data.getString("data"), Base64.NO_WRAP)), Charsets.UTF_8)
    }

    private fun write(plain: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key(true))
        val encrypted = cipher.doFinal(plain.toByteArray(Charsets.UTF_8))
        val data = JSONObject().put("version", 1)
            .put("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
            .put("data", Base64.encodeToString(encrypted, Base64.NO_WRAP)).toString()
        val stream = file.startWrite()
        try {
            stream.write(data.toByteArray(Charsets.UTF_8))
            file.finishWrite(stream)
        } catch (error: Exception) {
            file.failWrite(stream)
            throw error
        }
    }

    fun close() { worker.shutdown() }
}
