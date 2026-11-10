import 'package:flutter/material.dart';
import 'package:oronbox/src/core/providers/app_settings_providers.dart';
import 'package:oronbox/src/core/services/shared_prefs_service.dart';

class BluetoothConnectionSettings extends StatefulWidget {
  const BluetoothConnectionSettings({super.key});
  @override
  State<BluetoothConnectionSettings> createState() =>
      _BluetoothConnectionSettingsState();
}

class _BluetoothConnectionSettingsState
    extends State<BluetoothConnectionSettings> {
  bool _repair = androidRebuildBondEnabled();
  bool _saving = false;
  bool _autoReconnect =
      SharedPrefsService.instance.getBool('auto_reconnect_on_disconnect') ??
      true;
  String? _error;
  Future<void> _change(bool value) async {
    if (_saving) return;
    if (value) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('启用重建配对？'),
          content: const Text(
            '下次连接时会尝试移除目标手环的系统蓝牙配对，然后重新配对。请确认手机和手环的配对提示；运动健康连接、手环解锁手机等功能可能需要重新配置。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('启用兼容方式'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await SharedPrefsService.instance.setBool(
        androidRebuildBondSettingKey,
        value,
      );
      if (mounted) setState(() => _repair = value);
    } catch (_) {
      if (mounted) setState(() => _error = '未能保存连接设置，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('蓝牙连接方式')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Icon(Icons.bluetooth_connected_rounded, size: 42),
        const SizedBox(height: 20),
        Text(
          _repair ? '重建系统配对' : '优先直接连接',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        Text(
          _repair
              ? '连接前会先尝试移除目标手环的旧系统配对，再重新配对并连接。请唤醒手环，并确认手机和手环上的配对提示。'
              : '保留并复用已有系统配对；尚未配对时会先发起配对，再连接标准蓝牙通道。标准方式失败后才会尝试兼容通道。',
          style: TextStyle(height: 1.7),
        ),
        const SizedBox(height: 24),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('连接前重建系统配对'),
          subtitle: const Text('默认开启，下次连接时生效。关闭后优先复用已有配对。'),
          value: _repair,
          onChanged: _saving ? null : _change,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('断线自动恢复'),
          subtitle: const Text('短暂断开时最多尝试三轮；手动断开、取消或切换设备后停止。'),
          value: _autoReconnect,
          onChanged: _saving
              ? null
              : (value) async {
                  setState(() => _saving = true);
                  try {
                    await SharedPrefsService.instance.setBool(
                      'auto_reconnect_on_disconnect',
                      value,
                    );
                    if (mounted) {
                      setState(() {
                        _autoReconnect = value;
                        _error = null;
                      });
                    }
                  } catch (_) {
                    if (mounted) setState(() => _error = '未能保存自动恢复设置，请重试');
                  } finally {
                    if (mounted) setState(() => _saving = false);
                  }
                },
        ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 24),
        const Text('连接提示', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        const Text(
          '• 使用当前有效的 Key；恢复出厂后需重新同步或导入。\n• “系统蓝牙已连接”不等于 WristBox 已完成设备认证。\n• 重建配对可能影响运动健康连接、手环解锁手机等功能，需要时可关闭此选项。\n• 这个选项不保证两个应用能同时操作手环，也不能修复过期的 Key。',
          style: TextStyle(height: 1.8),
        ),
      ],
    ),
  );
}
