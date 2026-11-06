import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'admin_api.dart';
import 'cloud_store.dart';
import 'store_models.dart';

class AdminActivationPage extends StatefulWidget {
  const AdminActivationPage({super.key, required this.api});
  final AdminApi api;
  @override
  State<AdminActivationPage> createState() => _AdminActivationPageState();
}

class _AdminActivationPageState extends State<AdminActivationPage> {
  List<Map<String, dynamic>> _apps = [], _cards = [];
  String? _rid, _error;
  bool _busy = false;
  int _offset = 0, _total = 0, _count = 5, _days = 30;
  @override
  void initState() {
    super.initState();
    _run(_reload);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = cloudError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reload() async {
    final catalog = await widget.api.store.catalog(manage: true);
    final packages = <String>{};
    final apps = catalog
        .where(
          (a) =>
              packages.add((a['activationKey'] ?? a['packageName']) as String),
        )
        .toList();
    if (!mounted) return;
    setState(() {
      _apps = apps;
      if (!_apps.any((a) => a['id'] == _rid)) {
        _rid = _apps.isEmpty ? null : _apps.first['id'] as String;
      }
    });
    await _loadCards();
  }

  Future<void> _loadCards() async {
    if (_rid == null) return;
    final result = await widget.api.get('activation/cards', {
      'resourceId': _rid,
      'offset': _offset,
    });
    if (mounted) {
      setState(() {
        _cards = (result['items'] as List)
            .map((v) => (v as Map).cast<String, dynamic>())
            .toList();
        _total = result['total'] as int;
      });
    }
  }

  Future<bool> _confirm(String title, String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认'),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _generate() async {
    final response = await widget.api.dio.post<dynamic>(
      'v1/admin/activation/cards',
      data: {'resourceId': _rid, 'count': _count, 'validDays': _days},
    );
    if (!mounted) return;
    final name = _apps.firstWhere((a) => a['id'] == _rid)['name'];
    final codes = (response.data['cards'] as List)
        .map((c) => c['code'])
        .join('\n');
    final text =
        '$name · 资源激活卡密\n每张绑定一台手环，不绑定账号；${_days == 0 ? '未使用卡密长期有效' : '未使用卡密 $_days 天内有效'}。\n\n$codes\n';
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('卡密已生成，请保存'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('完整卡密仅显示这一次，服务器不会保存明文。关闭前请复制或导出。'),
                const SizedBox(height: 18),
                SelectableText(text),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('卡密已复制，请妥善保管')));
              }
            },
            child: const Text('复制全部'),
          ),
          TextButton(
            onPressed: () async {
              try {
                await FilePicker.saveFile(
                  dialogTitle: '保存资源卡密',
                  fileName:
                      'WristBox-cards-${DateTime.now().millisecondsSinceEpoch}.txt',
                  type: FileType.custom,
                  allowedExtensions: ['txt'],
                  bytes: Uint8List.fromList(utf8.encode(text)),
                );
              } catch (_) {
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('导出失败，请复制卡密保存')));
                }
              }
            },
            child: const Text('导出 TXT'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('已保存，关闭'),
          ),
        ],
      ),
    );
    _offset = 0;
    await _loadCards();
  }

  String _date(dynamic value) => value == null || value == 0
      ? '—'
      : DateTime.fromMillisecondsSinceEpoch((value as int) * 1000)
            .toLocal()
            .toString()
            .substring(0, 16);

  @override
  Widget build(BuildContext context) {
    final app = _apps.where((a) => a['id'] == _rid).firstOrNull;
    final required = app?['activationRequired'] == true;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('资源激活与设备授权'),
          actions: [
            IconButton(
              tooltip: '刷新',
              onPressed: _busy ? null : () => _run(_reload),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: ListView(
              padding: const EdgeInsets.all(28),
              children: [
                Text(
                  '一张卡密，一台设备',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  '授权按固定授权标识生效，后续替换安装包时选择相同标识即可沿用。新卡密为十二位随机字母数字。卡密使用后不可换绑；撤销会同时撤销设备授权并停止后续分发。',
                ),
                const SizedBox(height: 24),
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_apps.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: _rid,
                    key: ValueKey(_rid),
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '管理应用'),
                    items: _apps
                        .map(
                          (a) => DropdownMenuItem(
                            value: a['id'] as String,
                            child: Text(
                              '${a['name']} · ${a['packageName']}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (value) {
                            setState(() {
                              _rid = value;
                              _offset = 0;
                            });
                            _run(_loadCards);
                          },
                  ),
                if (_apps.isEmpty && !_busy) const Text('暂无应用，请先在应用与版本中上传资源。'),
                if (app != null) ...[
                  const SizedBox(height: 16),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('下载前需要卡密激活'),
                    subtitle: const Text('当前应用的所有型号、所有版本同时生效；管理员安装也需要激活。'),
                    value: required,
                    onChanged: _busy
                        ? null
                        : (value) async {
                            if (!await _confirm(
                              value ? '启用卡密激活？' : '改为免费资源？',
                              value
                                  ? '已有安装会话会结束，后续下载必须先绑定当前手环。'
                                  : '所有用户都可下载兼容此设备的版本。已有卡密和绑定记录会保留。',
                            )) {
                              return;
                            }
                            await _run(() async {
                              await widget.api.change(
                                'PATCH',
                                'activation/resources/$_rid',
                                {'required': value},
                              );
                              await _reload();
                            });
                          },
                  ),
                  const Divider(height: 32),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 150,
                        child: DropdownButtonFormField<int>(
                          initialValue: _count,
                          decoration: const InputDecoration(labelText: '生成数量'),
                          items: [1, 5, 10, 20, 50, 100, 500, 1000, 2000]
                              .map(
                                (v) => DropdownMenuItem(
                                  value: v,
                                  child: Text('$v 张'),
                                ),
                              )
                              .toList(),
                          onChanged: _busy
                              ? null
                              : (v) => setState(() => _count = v!),
                        ),
                      ),
                      SizedBox(
                        width: 180,
                        child: DropdownButtonFormField<int>(
                          initialValue: _days,
                          decoration: const InputDecoration(
                            labelText: '未使用卡密有效期',
                          ),
                          items: [0, 7, 30, 90, 365]
                              .map(
                                (v) => DropdownMenuItem(
                                  value: v,
                                  child: Text(v == 0 ? '长期有效' : '$v 天'),
                                ),
                              )
                              .toList(),
                          onChanged: _busy
                              ? null
                              : (v) => setState(() => _days = v!),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: _busy || !required
                            ? null
                            : () => _run(_generate),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('生成卡密'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Text(
                    '卡密与绑定记录 · $_total 条',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  for (final card in _cards)
                    Card(
                      child: ListTile(
                        leading: Icon(
                          card['revoked'] == 1
                              ? Icons.block
                              : card['redeemed'] != null
                              ? Icons.verified_outlined
                              : Icons.key_rounded,
                        ),
                        title: Text(
                          '尾号 ${card['suffix']} · ${card['revoked'] == 1
                              ? '已撤销'
                              : card['redeemed'] != null
                              ? '已激活'
                              : (card['expires'] as int) != 0 && (card['expires'] as int) <= DateTime.now().millisecondsSinceEpoch ~/ 1000
                              ? '已过期'
                              : '未使用'}',
                        ),
                        subtitle: Text(
                          card['redeemed'] != null
                              ? '${card['email'] == null ? '免登录激活' : '原激活账号 ID ${card['userId'] ?? '—'} · ${card['email']}'}\n${storeModelNames[card['model']] ?? card['model']} · SN ${card['serialHint']}\n激活于 ${_date(card['redeemed'])}'
                              : '生成于 ${_date(card['created'])} · ${card['expires'] == 0 ? '长期有效' : '截止 ${_date(card['expires'])}'}',
                        ),
                        isThreeLine: true,
                        trailing: TextButton(
                          onPressed: _busy || card['revoked'] == 1
                              ? null
                              : () async {
                                  if (!await _confirm(
                                    '撤销此卡密？',
                                    '此操作会使卡密永久失效，已绑定的设备也将失去此应用授权。需要恢复时请发放新卡密。',
                                  )) {
                                    return;
                                  }
                                  await _run(() async {
                                    await widget.api.change(
                                      'POST',
                                      'activation/cards/${card['id']}/revoke',
                                      {},
                                    );
                                    await _loadCards();
                                  });
                                },
                          child: const Text('撤销'),
                        ),
                      ),
                    ),
                  if (_cards.isEmpty && !_busy)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('暂无卡密，可在上方生成。'),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _busy || _offset == 0
                            ? null
                            : () {
                                _offset -= 25;
                                _run(_loadCards);
                              },
                        child: const Text('上一页'),
                      ),
                      Text('${_offset ~/ 25 + 1}'),
                      TextButton(
                        onPressed: _busy || _offset + 25 >= _total
                            ? null
                            : () {
                                _offset += 25;
                                _run(_loadCards);
                              },
                        child: const Text('下一页'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
