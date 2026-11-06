import 'dart:typed_data';

import 'watchface_install_policy.dart';

/// Cloud payloads are immutable: never regenerate or patch a signed BIN ID.
void validateCloudWatchfaceHeader(Uint8List header, String id, int length) {
  if (length <= 0x34 ||
      header.length != 0x34 ||
      header[0] != 0x5a ||
      header[1] != 0xa5 ||
      header[2] != 0x34 ||
      header[3] != 0x12 ||
      !RegExp(r'^[A-Za-z0-9_-]{1,12}$').hasMatch(id) ||
      RegExp(r'^0+$').hasMatch(id) ||
      isRestrictedWatchfaceId(id)) {
    throw StateError('云端 BIN 类型或表盘标识无效，已停止安装');
  }
  for (var i = 0; i < 12; i++) {
    if (header[0x28 + i] != (i < id.length ? id.codeUnitAt(i) : 0)) {
      throw StateError('BIN 内部标识与签名信息不一致，已停止安装');
    }
  }
}
