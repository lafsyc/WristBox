import 'package:flutter/material.dart';
import 'package:oronbox/src/core/models/bt_models.dart';

class DeviceKeyDialog extends StatefulWidget {
  const DeviceKeyDialog({super.key, required this.device});
  final MiWearState device;
  @override
  State<DeviceKeyDialog> createState() => _DeviceKeyDialogState();
}

class _DeviceKeyDialogState extends State<DeviceKeyDialog> {
  final _key = TextEditingController();
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('更新连接 Key'),
    content: SizedBox(
      width: 400,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.device.name,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              widget.device.addr,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            const Text(
              '手环恢复出厂设置后，请先在小米运动健康重新绑定。可通过“同步小米账号”自动更新，也可以在这里粘贴新的 Key。保存后需重新连接。',
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _key,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: '新的 Key',
                helperText: '32 位十六进制字符；原 Key 不会显示',
              ),
              validator: (value) =>
                  RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(value!.trim())
                  ? null
                  : '请输入完整的 32 位 Key',
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, _key.text.trim());
          }
        },
        child: const Text('保存新 Key'),
      ),
    ],
  );
}
