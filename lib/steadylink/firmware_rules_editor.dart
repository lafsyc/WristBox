import 'package:flutter/material.dart';

import 'store_models.dart';

class FirmwareRulesEditor extends StatelessWidget {
  const FirmwareRulesEditor({
    super.key,
    required this.models,
    required this.rules,
    required this.enabled,
    required this.onChanged,
  });
  final Set<String> models;
  final Map<String, Map<String, dynamic>> rules;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('逐型号固件匹配', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6),
      const Text('指定版本或范围不匹配时，服务器拒绝激活和下载。无法读取固件也会拦截。范围包含上下限，按数字逐段比较。'),
      for (final model in models) _rule(context, model),
    ],
  );

  Widget _rule(BuildContext context, String model) {
    final rule = rules.putIfAbsent(
      model,
      () => {
        'model': model,
        'mode': 'any',
        'versions': <String>[],
        'minVersion': '',
        'maxVersion': '',
      },
    );
    final mode = rule['mode'] as String;
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(storeModelNames[model] ?? model),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: ValueKey('$model-mode-$mode'),
              initialValue: mode,
              decoration: const InputDecoration(labelText: '固件要求'),
              items: const [
                DropdownMenuItem(value: 'any', child: Text('不限固件（确认通用后选择）')),
                DropdownMenuItem(value: 'exact', child: Text('仅指定版本')),
                DropdownMenuItem(value: 'range', child: Text('指定版本范围')),
              ],
              onChanged: !enabled
                  ? null
                  : (value) {
                      rules[model] = {
                        'model': model,
                        'mode': value!,
                        'versions': <String>[],
                        'minVersion': '',
                        'maxVersion': '',
                      };
                      onChanged();
                    },
            ),
            if (mode == 'exact') ...[
              const SizedBox(height: 12),
              TextFormField(
                key: ValueKey('$model-exact'),
                enabled: enabled,
                initialValue: (rule['versions'] as List? ?? []).join(', '),
                decoration: const InputDecoration(
                  labelText: '允许的固件版本',
                  hintText: '例如 3.1.171, 3.1.172',
                ),
                onChanged: (value) => rule['versions'] = value
                    .trim()
                    .split(RegExp(r'[,，\s]+'))
                    .where((v) => v.isNotEmpty)
                    .toList(),
                validator: (value) {
                  final versions = (value ?? '').trim().split(
                    RegExp(r'[,，\s]+'),
                  );
                  return versions.isEmpty ||
                          versions.length > 64 ||
                          versions.any((v) => firmwareParts(v) == null)
                      ? '填写有效版本号，最多 64 个，用逗号分隔'
                      : null;
                },
              ),
            ],
            if (mode == 'range') ...[
              const SizedBox(height: 12),
              TextFormField(
                key: ValueKey('$model-min'),
                enabled: enabled,
                initialValue: rule['minVersion'] as String? ?? '',
                decoration: const InputDecoration(labelText: '最低固件版本（包含）'),
                onChanged: (v) => rule['minVersion'] = v.trim(),
                validator: (v) =>
                    firmwareParts(v ?? '') == null ? '请输入数字和点组成的版本号' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: ValueKey('$model-max'),
                enabled: enabled,
                initialValue: rule['maxVersion'] as String? ?? '',
                decoration: const InputDecoration(labelText: '最高固件版本（包含）'),
                onChanged: (v) => rule['maxVersion'] = v.trim(),
                validator: (v) {
                  final min = firmwareParts('${rule['minVersion']}'),
                      max = firmwareParts(v ?? '');
                  if (max == null) return '请输入数字和点组成的版本号';
                  if (min != null && compareFirmware(min, max) > 0) {
                    return '最高版本不能低于最低版本';
                  }
                  return null;
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
