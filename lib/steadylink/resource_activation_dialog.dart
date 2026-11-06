import 'package:flutter/material.dart';

import 'cloud_store.dart';
import 'store_models.dart';

class ResourceActivationDialog extends StatefulWidget {
  const ResourceActivationDialog({
    super.key,
    required this.appName,
    required this.model,
    required this.serial,
    required this.activate,
  });
  final String appName, model, serial;
  final Future<void> Function(String code) activate;
  @override
  State<ResourceActivationDialog> createState() =>
      _ResourceActivationDialogState();
}

class _ResourceActivationDialogState extends State<ResourceActivationDialog> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    if (_busy) return;
    if (_code.text.trim().isEmpty) {
      setState(() => _error = '请填写资源激活卡密');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.activate(_code.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = cloudError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      icon: const Icon(Icons.key_rounded),
      title: const Text('激活到这台手环'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.appName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Text(
                '${storeModelNames[widget.model] ?? widget.model}\n序列号：${widget.serial}',
              ),
              const SizedBox(height: 14),
              const Text('一张卡密仅绑定这一台手环，不绑定账号。换手机或换账号后，连接同一手环即可安装及更新；换另一台手环需要新卡密。请确认序列号后激活。'),
              const SizedBox(height: 20),
              TextField(
                controller: _code,
                enabled: !_busy,
                maxLength: 80,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: '资源卡密',
                  hintText: '输入或粘贴卡密',
                  counterText: '',
                ),
                onSubmitted: (_) => _redeem(),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy ? null : _redeem,
          child: Text(_busy ? '正在激活…' : '激活并继续安装'),
        ),
      ],
    ),
  );
}
