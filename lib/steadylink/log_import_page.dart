import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oronbox/src/core/models/bt_models.dart';
import 'package:oronbox/src/features/devices/controllers/device_manager.dart';

import 'backend.dart';
import 'error_message.dart';
import 'log_key_parser.dart';
import 'store_models.dart';

const _logChannel = MethodChannel('wristbox/log_import');

String logDeviceName(LogKeyCandidate candidate) {
  if (candidate.name.isNotEmpty) return candidate.name;
  final model = storeModelForDevice(
    MiWearState(
      name: '',
      addr: '',
      connectType: 'spp',
      codename: candidate.model,
    ),
  );
  return storeModelNames[model] ??
      (candidate.address.isEmpty
          ? '未识别设备'
          : '蓝牙设备 ${candidate.address.substring(12)}');
}

MiWearState? deviceFromLogCandidate(
  LogKeyCandidate candidate,
  List<MiWearState> devices,
) {
  if (candidate.address.isEmpty) return null;
  final existing = devices
      .where((d) => d.addr.toUpperCase() == candidate.address)
      .firstOrNull;
  if (existing != null) return existing.copyWith(authkey: candidate.key);
  final model = storeModelForDevice(
    MiWearState(
      name: candidate.name,
      addr: '',
      connectType: 'spp',
      codename: candidate.model,
    ),
  );
  return MiWearState(
    name: logDeviceName(candidate),
    addr: candidate.address,
    connectType: 'spp',
    codename: model,
    authkey: candidate.key,
    disconnected: true,
  );
}

class LogImportPage extends ConsumerStatefulWidget {
  const LogImportPage({super.key, this.pickLog});
  final Future<Map<String, dynamic>?> Function()? pickLog;
  @override
  ConsumerState<LogImportPage> createState() => _LogImportPageState();
}

class _LogImportPageState extends ConsumerState<LogImportPage>
    with WidgetsBindingObserver {
  bool _busy = false;
  List<LogKeyCandidate> _candidates = [];
  final Map<String, String> _selectedKeys = {};
  String? _file, _error, _notice, _savedDevice;
  bool _awaitingHealth = false, _healthLeft = false;
  int _openedAt = 0;
  String? _modified;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_awaitingHealth) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _healthLeft = true;
    }
    if (state == AppLifecycleState.resumed && _healthLeft) {
      _awaitingHealth = false;
      _pick(automatic: true, notBefore: _openedAt - 2000);
    }
  }

  Future<void> _openHealth() async {
    _openedAt = DateTime.now().millisecondsSinceEpoch;
    _healthLeft = false;
    _awaitingHealth = true;
    try {
      await _logChannel.invokeMethod<void>('openHealth');
    } catch (_) {
      _awaitingHealth = false;
      if (mounted) setState(() => _error = '无法打开运动健康，请从桌面打开并导出日志，再回来点击自动读取');
    }
  }

  Future<void> _grantFolder() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    bool granted = false;
    try {
      granted = await _logChannel.invokeMethod<bool>('grantFolder') == true;
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.message ?? '无法授权日志文件夹');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (granted && mounted) await _pick(automatic: true);
  }

  Future<void> _forgetFolder() async {
    if (_busy) return;
    try {
      await _logChannel.invokeMethod<void>('forgetFolder');
      if (mounted) {
        setState(
          () => _notice =
              '已取消本功能保存的文件夹授权。已有 Key 保留；也可继续手动选择单个日志。若已开启所有文件访问，仍可按需读取默认日志目录。',
        );
      }
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.message ?? '无法取消文件夹授权');
    }
  }

  Future<void> _pick({bool automatic = false, int notBefore = 0}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
      _savedDevice = null;
      _candidates = [];
      _selectedKeys.clear();
      _file = null;
      _modified = null;
    });
    try {
      final result = await (automatic
          ? _logChannel.invokeMapMethod<String, dynamic>('scanLatest', {
              'notBefore': notBefore,
            })
          : widget.pickLog?.call() ??
                _logChannel.invokeMapMethod<String, dynamic>('pick'));
      if (result == null || !mounted) return;
      final records = (result['records'] as List)
          .map((r) => (r as Map).cast<String, dynamic>())
          .toList();
      final items = await compute(parseLogKeyRecords, records);
      if (!mounted) return;
      setState(() {
        _file = result['name'] as String;
        final modified = (result['modified'] as num?)?.toInt() ?? 0;
        if (modified > 0) {
          _modified = DateTime.fromMillisecondsSinceEpoch(modified)
              .toLocal()
              .toString()
              .split('.')
              .first;
        }
        _candidates = items;
        if (items.isEmpty) _notice = '未找到有效的 32 位连接 Key。请先让运动健康连接手环，再重新导出日志；某些版本可能不再输出 Key，仍可使用原来的小米账号同步。';
      });
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.message ?? '日志读取失败，请重新选择');
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '无法解析此日志，请重新导出后选择 ZIP、LOG 或 TXT 文件');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(LogKeyCandidate candidate) async {
    final backend = ref.read(steadyBackendProvider);
    if (_busy || backend.queue.busy) {
      setState(() => _error = '请等待当前连接或安装任务完成后再导入');
      return;
    }
    final devices = ref.read(deviceManagerProvider).pairedDevices;
    final identified = deviceFromLogCandidate(candidate, devices);
    final target =
        identified ??
        await showDialog<MiWearState>(
          context: context,
          builder: (_) =>
              LogKeyTargetDialog(candidate: candidate, devices: devices),
        );
    if (target == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _savedDevice = null;
    });
    try {
      await backend.importDevice(target);
      if (mounted) {
        setState(() {
          _savedDevice = target.addr;
          _notice =
              '已保存到「${target.name}」。日志可能包含历史 Key，请点击“验证连接”，成功认证后才可确认 Key 可用。';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final id = _savedDevice;
    if (id == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(steadyBackendProvider).queue.exclusive(id, () async {});
      if (mounted) {
        setState(() => _notice = '连接认证成功，这个 Key 可以用于当前手环。返回设备页即可安装应用。');
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error =
              '${friendlyError(e)}\n新 Key 已保存；可以选择其他日志记录重新导入，或使用账号同步更新。',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('从日志导入 Key'),
          automaticallyImplyLeading: !_busy,
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer.withValues(alpha: .4),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.folder_zip_outlined,
                        size: 32,
                        color: colors.primary,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '日志留在手机，连接由你确认',
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        '授权日志文件夹后，自动查找最新日志并在本机解析，无需逐个选择文件。日志和 Key 不上传，也不生成解压缓存。小米账号同步仍然保留。',
                        style: TextStyle(height: 1.6),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  '操作教程',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                _step('1', '先连接手环', '打开小米运动健康，让目标手环连接并同步一次。恢复出厂后需先在运动健康重新绑定。'),
                _step(
                  '2',
                  '导出设备日志',
                  '进入“我的 → 关于”，快速连续点击页面上的小米运动健康 Logo；看到导出 / 迁移日志提示后确认。部分版本入口可能不同。',
                ),
                _step(
                  '3',
                  '首次授权，之后自动读取',
                  '首次点击“授权日志文件夹”，选择 Download/wearablelog 或 Download/ResearchLog 文件夹，并允许访问。不要选择整个 Download。之后从本页打开运动健康、导出日志并返回，会自动查找本次的新日志；也可点击“自动读取最新日志”。',
                ),
                _step(
                  '4',
                  '选择设备并验证',
                  '读取后直接选择识别到的设备，已有设备自动更新 Key。同一设备存在多条历史 Key 时，请选择一条再导入并验证连接；仅未识别的记录需要手动补充。请勿把日志公开分享。',
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _openHealth,
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('打开运动健康，返回后自动读取'),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _pick(automatic: true),
                  icon: const Icon(Icons.manage_search_rounded),
                  label: Text(_busy ? '正在读取…' : '自动读取最新日志'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _grantFolder,
                  icon: const Icon(Icons.folder_open_rounded),
                  label: const Text('授权日志文件夹'),
                ),
                TextButton(
                  onPressed: _busy ? null : _forgetFolder,
                  child: const Text('取消日志文件夹授权'),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _busy ? null : _pick,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.file_open_outlined),
                  label: Text(_busy ? '正在处理…' : '手动选择日志（备用）'),
                ),
                const SizedBox(height: 12),
                Text(
                  '文件上限 32 MB。不会后台持续扫描；只在你点击读取或从本页打开运动健康后返回时查找。若此前已开启所有文件访问，也可直接查找默认日志目录，无需重复授权。',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.6,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      _error!,
                      style: TextStyle(color: colors.error, height: 1.5),
                    ),
                  ),
                if (_notice != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(_notice!, style: const TextStyle(height: 1.6)),
                  ),
                if (_savedDevice != null)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _verify,
                    icon: const Icon(Icons.bluetooth_connected_rounded),
                    label: const Text('验证连接'),
                  ),
                if (_file != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    '识别到 ${groupLogDevices(_candidates).where((g) => g.device.address.isNotEmpty).length} 台设备 · ${_candidates.length} 条 Key',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    _file!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                  if (_modified != null) Text('日志修改时间：$_modified；请核对是否刚刚导出'),
                ],
                for (final group in groupLogDevices(_candidates))
                  _deviceCard(group),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _step(String number, String title, String detail) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 15,
          child: Text(number, style: const TextStyle(fontSize: 13)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 5),
              Text(detail, style: const TextStyle(height: 1.6)),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _deviceCard(LogDeviceGroup group) {
    final device = group.device;
    final selection = _selectedKeys[device.address];
    final selected = group.candidates.length == 1
        ? device
        : group.candidates.where((c) => c.key == selection).firstOrNull;
    final known = device.address.isNotEmpty;
    return Card(
      margin: const EdgeInsets.only(top: 14),
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(known ? Icons.watch_rounded : Icons.help_outline_rounded),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    logDeviceName(device),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (known) const Chip(label: Text('已识别')),
              ],
            ),
            if (device.model.isNotEmpty) Text(device.model),
            Text(known ? device.address : '无法可靠关联设备，仅此记录需要手动选择'),
            const SizedBox(height: 12),
            if (group.candidates.length > 1) ...[
              const Text(
                '发现多个历史 Key，请选择后验证连接；日志顺序不代表当前有效。',
                style: TextStyle(height: 1.5),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: ValueKey('history-${device.address}'),
                initialValue: selection,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '选择连接 Key'),
                items: [
                  for (var i = 0; i < group.candidates.length; i++)
                    DropdownMenuItem(
                      value: group.candidates[i].key,
                      child: Text('记录 ${i + 1} · ${group.candidates[i].hint}'),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() {
                        if (value != null) {
                          _selectedKeys[device.address] = value;
                        }
                      }),
              ),
            ] else
              Text(
                'Key  ${device.hint}',
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            if (selected != null) ...[
              const SizedBox(height: 6),
              Text(
                '${selected.source} · 第 ${selected.line} 行',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: _busy || selected == null
                    ? null
                    : () => _save(selected),
                icon: Icon(
                  known ? Icons.add_link_rounded : Icons.edit_outlined,
                ),
                label: Text(known ? '选择并导入' : '手动选择目标'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LogKeyTargetDialog extends StatefulWidget {
  const LogKeyTargetDialog({
    super.key,
    required this.candidate,
    required this.devices,
  });
  final LogKeyCandidate candidate;
  final List<MiWearState> devices;
  @override
  State<LogKeyTargetDialog> createState() => _LogKeyTargetDialogState();
}

class _LogKeyTargetDialogState extends State<LogKeyTargetDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name, _mac;
  String? _target, _model;
  @override
  void initState() {
    super.initState();
    final c = widget.candidate;
    _name = TextEditingController(text: c.name);
    _mac = TextEditingController(text: c.address);
    _model = storeModelForDevice(
      MiWearState(
        name: c.name,
        addr: '',
        connectType: 'spp',
        codename: c.model,
      ),
    );
    final matches = widget.devices
        .where((d) => d.addr.toUpperCase() == c.address)
        .toList();
    _target = matches.length == 1
        ? matches.single.addr
        : widget.devices.isEmpty
        ? 'new'
        : null;
  }

  @override
  void dispose() {
    _name.dispose();
    _mac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('确认导入目标'),
    content: SizedBox(
      width: 420,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Key ${widget.candidate.hint}'),
            const SizedBox(height: 12),
            const Text(
              '日志可能保留多台设备或旧 Key。只会修改你确认的这一台设备，保存后需验证连接。',
              style: TextStyle(height: 1.6),
            ),
            const SizedBox(height: 18),
            DropdownButtonFormField<String>(
              initialValue: _target,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '目标设备'),
              items: [
                for (final device in widget.devices)
                  DropdownMenuItem(
                    value: device.addr,
                    child: Text(
                      '${device.name} · ${device.addr}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                const DropdownMenuItem(value: 'new', child: Text('新增一台设备')),
              ],
              onChanged: (v) => setState(() => _target = v),
              validator: (v) {
                if (v == null) return '请明确选择目标设备';
                if (v != 'new' &&
                    widget.candidate.address.isNotEmpty &&
                    v.toUpperCase() != widget.candidate.address) {
                  return '日志地址与此设备不同，请选择正确的设备';
                }
                return null;
              },
            ),
            if (_target == 'new') ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: '设备名称'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? '请输入设备名称' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _mac,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: '蓝牙 MAC 地址',
                  helperText: '从运动健康的设备信息中核对地址',
                  hintText: 'AA:BB:CC:DD:EE:FF',
                ),
                validator: (v) {
                  final value = v?.trim().toUpperCase() ?? '';
                  if (!RegExp(r'^[0-9A-F]{2}(:[0-9A-F]{2}){5}$')
                          .hasMatch(value) ||
                      value == '00:00:00:00:00:00' ||
                      value == 'FF:FF:FF:FF:FF:FF') {
                    return '请输入有效的完整蓝牙地址';
                  }
                  if (widget.devices.any(
                    (d) => d.addr.toUpperCase() == value,
                  )) {
                    return '此设备已在列表中，请改选已有设备';
                  }
                  if (widget.candidate.address.isNotEmpty &&
                      value != widget.candidate.address) {
                    return '此地址与日志中的设备不同，请核对';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _model ?? '',
                isExpanded: true,
                decoration: const InputDecoration(labelText: '型号'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('其他 / 连接后识别')),
                  for (final item in storeModelNames.entries)
                    DropdownMenuItem(value: item.key, child: Text(item.value)),
                ],
                onChanged: (v) => _model = v == '' ? null : v,
              ),
            ],
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
          if (!_form.currentState!.validate()) return;
          final target = _target == 'new'
              ? MiWearState(
                  name: _name.text.trim(),
                  addr: _mac.text.trim().toUpperCase(),
                  connectType: 'spp',
                  authkey: widget.candidate.key,
                  codename: _model,
                  disconnected: true,
                )
              : widget.devices
                    .firstWhere((d) => d.addr == _target)
                    .copyWith(authkey: widget.candidate.key);
          Navigator.pop(context, target);
        },
        child: const Text('确认保存'),
      ),
    ],
  );
}
