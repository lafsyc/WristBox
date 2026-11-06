import 'dart:typed_data';

import 'package:oronbox/src/features/resources/services/resource_payload_analyzer.dart';

bool isLocalInstallFile(String name) =>
    name.toLowerCase().endsWith('.rpk') || name.toLowerCase().endsWith('.bin');

ResourcePayloadAnalysis analyzeLocalPackage(String name, Uint8List bytes) {
  if (!isLocalInstallFile(name)) throw StateError('请选择 RPK 或 BIN 安装包');
  if (bytes.isEmpty || bytes.length > 64 * 1024 * 1024) {
    throw StateError('安装包不能为空，且不能超过 64 MB');
  }
  final result = ResourcePayloadAnalyzer().analyze(
    fileName: name,
    bytes: bytes,
  );
  if (result == null || result.platform != ResourcePlatform.vela) {
    throw StateError('无法识别文件内容。请选择完整的 Vela 应用包或表盘 BIN 文件');
  }
  if (result.type == LocalDeviceInstallType.firmware) {
    throw StateError('这是固件文件，不能作为应用或表盘安装');
  }
  if (result.identifier == null || result.identifier!.trim().isEmpty) {
    throw StateError('安装包缺少有效的应用标识或表盘 ID，请重新获取完整文件');
  }
  return result;
}
