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
  bool _repair =
      SharedPrefsService.instance.getBool(androidRebuildBondSettingKey) ??
      false;
  bool _saving = false;
  String? _error;
  Future<void> _change(bool value) async {
    if (_saving) return;
    if (value) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('启用重建配对？'),
          content: const Text(
            '下次连接时会尝试移除目标手环的系统蓝牙配对，然后重新配对。运动健康连接、手环解锁手机等功能可能需要重新配置。仅在直接连接失败时尝试。',
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
        const Text(
          '默认保留手环与这台手机的系统配对，直接尝试连接。请唤醒手环，确认手机或手环出现的配对提示；不需要先把“连接新设备”作为必做步骤。',
          style: TextStyle(height: 1.7),
        ),
        const SizedBox(height: 24),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('连接前重建系统配对'),
          subtitle: const Text('兼容选项，通常保持关闭。只影响下一次连接。'),
          value: _repair,
          onChanged: _saving ? null : _change,
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
          '• 使用当前有效的 Key；恢复出厂后需重新同步或导入。\n• “系统蓝牙已连接”不等于 WristBox 已完成设备认证。\n• 这个选项不保证运动健康和 WristBox 能同时操作手环。若其他应用占用连接，可先暂停其连接再试。\n• 不同手机、手环型号和固件的行为可能不同；直接连接失败时再尝试兼容方式。',
          style: TextStyle(height: 1.8),
        ),
      ],
    ),
  );
}
