import 'package:flutter/material.dart';

class BinUploadDialog extends StatefulWidget {
  const BinUploadDialog({super.key, required this.fileName});
  final String fileName;
  @override
  State<BinUploadDialog> createState() => _BinUploadDialogState();
}

class _BinUploadDialogState extends State<BinUploadDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: widget.fileName.replaceFirst(
      RegExp(r'(\.face)?\.bin$', caseSensitive: false),
      '',
    ),
  );
  final _version = TextEditingController(text: '1.0.0');
  final _code = TextEditingController(text: '1');
  @override
  void dispose() {
    _name.dispose();
    _version.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('上传 BIN 资源'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('支持小米表盘容器 BIN，不支持固件刷机文件。上传后会保存为草稿，再设置授权标识、型号和固件。'),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                maxLength: 100,
                decoration: const InputDecoration(labelText: '资源名称'),
                validator: (v) => (v ?? '').trim().isEmpty ? '请输入资源名称' : null,
              ),
              TextFormField(
                controller: _version,
                maxLength: 50,
                decoration: const InputDecoration(labelText: '显示版本，例如 2.4.1'),
                validator: (v) => (v ?? '').trim().isEmpty ? '请输入显示版本' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _code,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '版本号（正整数）',
                  helperText: '用于更新排序，新包应大于旧包，例如 20401',
                ),
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  return n == null || n < 1 || n > 2147483647
                      ? '请输入有效的正整数版本号'
                      : null;
                },
              ),
            ],
          ),
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
          if (!_form.currentState!.validate()) return;
          Navigator.pop(context, <String, dynamic>{
            'name': _name.text.trim(),
            'version': _version.text.trim(),
            'versionCode': int.parse(_code.text),
          });
        },
        child: const Text('上传为草稿'),
      ),
    ],
  );
}
