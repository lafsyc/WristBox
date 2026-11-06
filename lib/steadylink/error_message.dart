import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// User-facing errors never echo native request payloads or credentials.
String friendlyError(Object error, {bool installing = false}) {
  final raw = error is PlatformException
      ? '${error.code}: ${error.message ?? ''}'
      : error.toString();
  final text = raw.toLowerCase();
  if (error is TimeoutException ||
      text.contains('timeout') ||
      text.contains('timed out')) {
    return installing
        ? '安装等待超时。请先刷新手环应用列表，确认是否已安装成功，再决定是否重试；保持手环靠近并暂停其他设备的连接。'
        : '等待手环响应超时。请唤醒手环并靠近，暂停小米运动健康或其他工具的连接后重试；恢复出厂设置后需重新同步 Key。';
  }
  if (text.contains('auth') ||
      text.contains('认证') ||
      text.contains('handshake') ||
      text.contains('decrypt')) {
    return '手环身份验证失败。若手环已恢复出厂设置，请先在小米运动健康重新绑定，再同步小米账号或在设备操作中更新 Key，然后重新连接。';
  }
  if (text.contains('permission') ||
      text.contains('denied') ||
      text.contains('unauthorized')) {
    return '权限不足。请在系统设置中允许 SteadyLink 使用蓝牙和“附近的设备”；较旧的 Android 还需位置权限，再重试。';
  }
  if (text.contains('bluetooth_off') ||
      text.contains('bluetooth_disabled') ||
      text.contains('adapter disabled')) {
    return '蓝牙尚未开启。请打开系统蓝牙开关，确认蓝牙适配器可用，再点击设备重新连接。';
  }
  if (text.contains('pair') || text.contains('bond')) {
    return '蓝牙配对未完成。请查看手环和系统的配对提示；如配对记录已失效，请在系统蓝牙设置中移除旧配对，再重新连接。';
  }
  if (error is FileSystemException || text.contains('file not found')) {
    return '无法读取安装包。文件可能已移动、被删除或无访问权限，请重新选择本机保存的 RPK / BIN 文件。';
  }
  if (text.contains('disconnect') ||
      text.contains('not connected') ||
      text.contains('not ready') ||
      text.contains('socket') ||
      text.contains('connection failed') ||
      text.contains('broken pipe')) {
    return installing
        ? '安装时连接中断。请重新连接并刷新应用列表，确认安装结果后再重试。'
        : '未能建立可用连接。请检查蓝牙、唤醒手环并暂停其他应用的连接，再重试。若重置过手环，请先更新 Key。';
  }
  if (text.contains('space') || text.contains('storage full')) {
    return '手环存储空间不足，请卸载不需要的应用后重新安装。';
  }
  if (text.contains('crc') ||
      text.contains('checksum') ||
      text.contains('invalid package')) {
    return '安装包校验失败，请重新获取适合此手环的完整 RPK / BIN 文件。';
  }
  // Preserve our Chinese explanations, stripping implementation prefixes and
  // long secrets. Unknown English payloads are deliberately not shown.
  if (RegExp(r'[\u4e00-\u9fff]').hasMatch(raw)) {
    final safe = raw
        .replaceFirst(
          RegExp(
            r'^(Bad state: |Exception: |FormatException: |ProtocolException: )',
          ),
          '',
        )
        .replaceAll(RegExp(r'[a-fA-F0-9]{32,}'), '［已隐藏］')
        .replaceAll(RegExp(r'https?://\S+'), '［链接已隐藏］');
    return safe.length > 350 ? '${safe.substring(0, 350)}…' : safe;
  }
  return installing
      ? '安装未完成，手环未返回成功确认。请检查安装包是否适配当前型号，并刷新应用列表确认结果后重试。'
      : '操作未完成。请检查蓝牙和设备连接后重试；重置或重新绑定手环后，请先同步小米账号更新 Key。';
}
