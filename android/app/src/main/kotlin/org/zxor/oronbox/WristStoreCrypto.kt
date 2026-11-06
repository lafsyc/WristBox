package org.zxor.oronbox

import android.os.Handler
import android.os.Looper
import android.util.Base64
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.nio.ByteBuffer
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.MessageDigest
import java.security.Signature
import java.security.spec.MGF1ParameterSpec
import java.security.spec.X509EncodedKeySpec
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.OAEPParameterSpec
import javax.crypto.spec.PSource
import javax.crypto.spec.SecretKeySpec

/** Ephemeral installation secrets; no package or session key file is created. */
class WristStoreCrypto(messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "wristbox/store_crypto")
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pair: KeyPair? = null
    private var key: ByteArray? = null
    private var envelope: JSONObject? = null
    private var envelopeHash: ByteArray? = null
    private var closed = false

    init {
        channel.setMethodCallHandler { call, result ->
            executor.execute {
                try {
                    check(!closed)
                    val value = handle(call)
                    main.post { try { result.success(value) } finally { if (value is ByteArray) value.fill(0) } }
                } catch (_: Exception) {
                    clear()
                    main.post { result.error("store_integrity", "安全校验失败或安装会话过期，已停止安装", null) }
                }
            }
        }
    }
    private fun bytes(value: String) = Base64.decode(value, Base64.NO_WRAP)
    private fun hex(value: ByteArray) = value.joinToString("") { "%02x".format(it.toInt() and 255) }
    private fun sha(value: ByteArray) = MessageDigest.getInstance("SHA-256").digest(value)
    private fun clear() {
        key?.fill(0); key = null; pair = null; envelope = null; envelopeHash = null
    }
    private fun handle(call: MethodCall): Any? = when (call.method) {
        "prepare" -> {
            clear()
            pair = KeyPairGenerator.getInstance("RSA").apply { initialize(3072) }.generateKeyPair()
            Base64.encodeToString(pair!!.public.encoded, Base64.NO_WRAP)
        }
        "prove" -> {
            val message = call.argument<String>("message")!!
            require(message.matches(Regex("WristBox/install/v1:[0-9a-f]{32}:[0-9a-f]{64}:[0-9a-f]{64}")))
            val signer = Signature.getInstance("SHA256withRSA")
            signer.initSign(pair!!.private)
            signer.update(message.toByteArray(Charsets.UTF_8))
            Base64.encodeToString(signer.sign(), Base64.NO_WRAP)
        }
        "accept" -> {
            val payload = bytes(call.argument<String>("envelope")!!)
            require(payload.size <= 131072)
            val trusted = call.argument<ByteArray>("trustedKey")!!
            val verifier = Signature.getInstance("SHA256withRSA")
            verifier.initVerify(KeyFactory.getInstance("RSA").generatePublic(X509EncodedKeySpec(trusted)))
            verifier.update(payload)
            require(verifier.verify(bytes(call.argument<String>("signature")!!)))
            val env = JSONObject(String(payload, Charsets.UTF_8))
            val meta = env.getJSONObject("manifest")
            require(env.getInt("protocol") == 1 && meta.getInt("protocol") == 1)
            require(env.getString("device") == call.argument<String>("device"))
            require(env.getString("model") == call.argument<String>("model"))
            require(env.optString("firmware", "") == (call.argument<String>("firmware") ?: ""))
            if (call.argument<Boolean>("activationRequired") == true || env.has("activationId")) {
                require(env.getString("activationId").matches(Regex("[0-9a-f]{32}")))
                require(env.getString("deviceIdentity") == call.argument<String>("deviceIdentity"))
            }
            require(meta.getString("id") == call.argument<String>("resourceId"))
            require(env.getString("clientKeyHash") == hex(sha(pair!!.public.encoded)))
            val remaining = env.getLong("expires") - System.currentTimeMillis() / 1000
            require(remaining in 1..1260)
            val size = meta.getInt("size")
            require(size in 1..33554432 && meta.getInt("chunkSize") == 65536)
            require(meta.getJSONArray("chunkSha256").length() == (size + 65535) / 65536)
            require(bytes(env.getString("noncePrefix")).size == 8)
            val cipher = Cipher.getInstance("RSA/ECB/OAEPPadding")
            cipher.init(Cipher.DECRYPT_MODE, pair!!.private,
                OAEPParameterSpec("SHA-256", "MGF1", MGF1ParameterSpec.SHA256,
                    PSource.PSpecified("WristBox/store/v1".toByteArray(Charsets.UTF_8))))
            key = cipher.doFinal(bytes(env.getString("wrappedKey")))
            require(key!!.size == 32)
            pair = null
            envelope = env; envelopeHash = sha(payload)
            true
        }
        "decrypt" -> {
            val env = envelope!!
            require(env.getLong("expires") > System.currentTimeMillis() / 1000)
            val seq = call.argument<Int>("seq")!!
            val meta = env.getJSONObject("manifest")
            val hashes = meta.getJSONArray("chunkSha256")
            require(seq >= 0 && seq < hashes.length())
            val expected = minOf(65536, meta.getInt("size") - seq * 65536)
            val encrypted = call.argument<ByteArray>("ciphertext")!!
            require(encrypted.size == expected + 16)
            val index = ByteBuffer.allocate(4).putInt(seq).array()
            val nonce = bytes(env.getString("noncePrefix")) + index
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key!!, "AES"), GCMParameterSpec(128, nonce))
            cipher.updateAAD(envelopeHash!! + index)
            val plain = cipher.doFinal(encrypted)
            if (hex(sha(plain)) != hashes.getString(seq)) {
                plain.fill(0); throw IllegalStateException()
            }
            plain
        }
        "close" -> { clear(); true }
        else -> throw IllegalArgumentException()
    }
    fun close() {
        channel.setMethodCallHandler(null)
        executor.execute { closed = true; clear() }
        executor.shutdown()
    }
}
