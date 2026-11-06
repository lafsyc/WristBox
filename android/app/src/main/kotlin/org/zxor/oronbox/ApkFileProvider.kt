package org.zxor.oronbox

import androidx.core.content.FileProvider

/** Exposes downloaded APKs (in filesDir/apk) to the system installer. */
class ApkFileProvider : FileProvider()
