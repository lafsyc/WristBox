import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oronbox/src/core/models/bt_models.dart';
import 'package:oronbox/src/features/devices/controllers/device_manager.dart';
import 'package:oronbox/src/protocols/common/device_protocol.dart'
    show ProtocolState;

import 'backend.dart';
import 'cloud_store.dart';
import 'store_media.dart';
import 'store_models.dart';

String activatedResourceAction({
  required bool matchesDevice,
  required bool appsKnown,
  required int? installedVersion,
  required int latestVersion,
}) {
  if (!matchesDevice) return '连接并安装';
  if (!appsKnown || installedVersion == 0) return '安装 / 更新';
  if (installedVersion == null) return '安装';
  if (installedVersion > latestVersion) return '已安装更新版本';
  return installedVersion < latestVersion ? '更新' : '重新安装';
}

class ActivatedResourcesPage extends ConsumerStatefulWidget {
  const ActivatedResourcesPage({super.key, this.store});
  final CloudStore? store;
  @override
  ConsumerState<ActivatedResourcesPage> createState() =>
      _ActivatedResourcesPageState();
}

class _ActivatedResourcesPageState
    extends ConsumerState<ActivatedResourcesPage> {
  CloudStore? _store;
  List<Map<String, dynamic>> _items = [];
  bool _loading = false,
      _busy = false,
      _deviceChanged = false,
      _storeEnabled = true;
  int _request = 0, _total = 0, _nextOffset = 0;
  String? _error, _notice, _snapshot, _appsSnapshot, _busyId;
  String _stage = '';
  double? _progress;

  String _stamp(DeviceManagerState state) =>
      state.protocolState == ProtocolState.ready
      ? '${state.currentDevice?.addr}\u0000${storeModelForDevice(state.currentDevice, systemInfo: state.systemInfo)}\u0000${state.systemInfo?.serialNumber}'
      : '';

  @override
  void initState() {
    super.initState();
    _store = widget.store;
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _request++;
    super.dispose();
  }

  Future<void> _load({bool more = false, bool refreshDevice = true}) async {
    if (!mounted || _busy) return;
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      if (!more) _snapshot = null;
    });
    try {
      final store = _store ?? await CloudStore.connect();
      if (!mounted || request != _request) return;
      _store = store;
      final backend = ref.read(steadyBackendProvider);
      final before = ref.read(deviceManagerProvider);
      if (refreshDevice && !more) {
        _appsSnapshot = null;
        if (before.currentDevice != null &&
            before.protocolState == ProtocolState.ready &&
            !backend.queue.busy) {
          try {
            await backend.refresh(before.currentDevice!.addr);
            if (backend.state.currentDevice?.addr ==
                    before.currentDevice!.addr &&
                backend.state.protocolState == ProtocolState.ready) {
              _appsSnapshot = _stamp(backend.state);
            }
          } catch (_) {
            _notice = '暂未读取到已安装版本，安装时会重新检查设备。';
          }
        }
      }
      if (!mounted || request != _request) return;
      final state = ref.read(deviceManagerProvider),
          stamp = _stamp(ref.read(deviceManagerProvider));
      final ready = stamp.isNotEmpty;
      final result = await _store!.activatedResources(
        model: ready
            ? storeModelForDevice(
                    state.currentDevice,
                    systemInfo: state.systemInfo,
                  ) ??
                  ''
            : '',
        serial: ready ? state.systemInfo?.serialNumber ?? '' : '',
        offset: more ? _nextOffset : 0,
      );
      if (!mounted || request != _request) return;
      if (_stamp(ref.read(deviceManagerProvider)) != stamp) {
        _deviceChanged = true;
        return;
      }
      setState(() {
        final rows = (result['items'] as List)
            .map((v) => (v as Map).cast<String, dynamic>())
            .toList();
        _nextOffset = (more ? _nextOffset : 0) + rows.length;
        final ids = <String>{};
        _items = (more ? [..._items, ...rows] : rows)
            .where((row) => ids.add(row['id'] as String))
            .toList();
        _total = result['total'] as int;
        _snapshot = stamp;
        _storeEnabled = result['storeEnabled'] != false;
      });
    } catch (e) {
      if (mounted && request == _request) {
        setState(() {
          _error = cloudError(e);
          if (!more) _items = [];
        });
      }
    } finally {
      if (mounted && request == _request) {
        setState(() => _loading = false);
        if (_deviceChanged && !_busy) {
          _deviceChanged = false;
          Future.microtask(() => _load(refreshDevice: false));
        }
      }
    }
  }

  bool _matches(Map<String, dynamic> item, DeviceManagerState state) =>
      _snapshot != null &&
      _snapshot!.isNotEmpty &&
      _snapshot == _stamp(state) &&
      item['matchesDevice'] == true;

  void _outcome(String message) {
    if (!mounted) return;
    setState(() => _notice = message);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<MiWearState?> _target(Map<String, dynamic> item) async {
    final state = ref.read(deviceManagerProvider);
    if (_matches(item, state)) return state.currentDevice;
    final choices = state.pairedDevices
        .where(
          (d) =>
              storeModelForDevice(
                d,
                systemInfo:
                    d.addr == state.currentDevice?.addr &&
                        state.protocolState == ProtocolState.ready
                    ? state.systemInfo
                    : null,
              ) ==
              item['model'],
        )
        .toList();
    if (choices.isEmpty) {
      setState(
        () => _notice =
            '请先到设备页添加绑定的${storeModelNames[item['model']] ?? '手环'}，再返回安装。',
      );
      return null;
    }
    if (choices.length == 1) return choices.single;
    return showDialog<MiWearState>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('选择绑定手环\nSN ${item['serialHint']}'),
        children: [
          for (final d in choices)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, d),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('${d.name}\n${d.addr}'),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _install(Map<String, dynamic> item) async {
    if (_busy || _loading) return;
    final target = await _target(item);
    if (target == null || !mounted || _busy) return;
    final resource = (item['resource'] as Map).cast<String, dynamic>();
    setState(() {
      _busy = true;
      _busyId = item['id'] as String;
      _progress = null;
      _stage = '正在连接绑定手环';
      _notice = null;
    });
    try {
      await ref
          .read(steadyBackendProvider)
          .installCloud(
            _store!,
            resource['id'] as String,
            target.addr,
            (value) {
              if (mounted) {
                setState(() {
                  _progress = value;
                  _stage = value >= 1 ? '等待手环确认' : '正在传输到手环';
                });
              }
            },
            expectedModel: item['model'] as String,
            expectedGrantId: item['id'] as String,
            onStage: (stage) {
              if (mounted) setState(() => _stage = stage);
            },
          );
      _outcome('${item['name']} v${resource['version']} 已安装到绑定手环');
    } catch (e) {
      _outcome(cloudError(e));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyId = null;
          _progress = null;
        });
        await _load();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(deviceManagerProvider),
        colors = Theme.of(context).colorScheme;
    ref.listen(deviceManagerProvider, (previous, next) {
      if (previous != null && _stamp(previous) != _stamp(next)) {
        if (_busy || _loading) {
          _deviceChanged = true;
        } else {
          _load();
        }
      }
    });
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('已激活资源'),
          automaticallyImplyLeading: !_busy,
          actions: [
            IconButton(
              tooltip: '刷新资源与设备版本',
              onPressed: _busy || _loading ? null : () => _load(),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () => _load(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Row(
                children: [
                  Icon(
                    state.protocolState == ProtocolState.ready
                        ? Icons.bluetooth_connected_rounded
                        : Icons.bluetooth_rounded,
                    size: 20,
                    color: colors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.protocolState == ProtocolState.ready
                          ? '${state.currentDevice?.name ?? '手环'} · 已连接'
                          : '连接手环后，查看这台设备的已激活资源',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_loading) const LinearProgressIndicator(),
              if (_error != null) ...[
                _message(_error!),
                TextButton(
                  onPressed: _loading ? null : () => _load(),
                  child: const Text('重新加载'),
                ),
              ],
              if (_notice != null) _message(_notice!),
              if (!_storeEnabled) _message('商店正在维护，绑定记录仍可查看，暂时无法安装。'),
              if (!_loading && _error == null && _items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 64),
                  child: Column(
                    children: [
                      Icon(
                        Icons.verified_outlined,
                        size: 46,
                        color: colors.primary,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        state.protocolState == ProtocolState.ready
                            ? '这台手环还没有激活资源'
                            : '先连接你的手环',
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '授权跟随手环，无需登录。连接后可查看原有激活记录。',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              for (final item in _items) _card(item, state),
              if (_nextOffset < _total && _items.isNotEmpty)
                TextButton(
                  onPressed: _loading || _busy
                      ? null
                      : () => _load(more: true, refreshDevice: false),
                  child: const Text('加载更多'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _message(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(text),
  );

  Widget _card(Map<String, dynamic> item, DeviceManagerState state) {
    final colors = Theme.of(context).colorScheme;
    final resource = (item['resource'] as Map?)?.cast<String, dynamic>();
    final active = item['status'] == 'active', matches = _matches(item, state);
    final appsKnown = matches && _appsSnapshot == _stamp(state);
    final installed = appsKnown
        ? state.apps
              .where((a) => a.packageName == item['packageName'])
              .firstOrNull
        : null;
    final latest = (resource?['versionCode'] as num?)?.toInt() ?? 0;
    final newer =
        appsKnown && installed != null && installed.versionCode > latest;
    final action = !active
        ? '授权已撤销'
        : resource == null
        ? '暂无可安装版本'
        : activatedResourceAction(
            matchesDevice: matches,
            appsKnown: appsKnown,
            installedVersion: installed?.versionCode,
            latestVersion: latest,
          );
    final stamp = DateTime.fromMillisecondsSinceEpoch(
      (item['activatedAt'] as int) * 1000,
    ).toLocal();
    return Card(
      margin: const EdgeInsets.only(top: 16),
      elevation: 0,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StoreMediaImage(
                  id: item['iconId'] as String? ?? '',
                  load: _store!.media,
                  width: 54,
                  height: 54,
                  radius: 16,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${item['name']}',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        active ? '已激活' : '授权已撤销',
                        style: TextStyle(
                          color: active ? colors.primary : colors.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.watch_outlined,
                  size: 20,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${storeModelNames[item['model']] ?? item['model']}\nSN ${item['serialHint']}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              !active
                  ? '绑定记录保留，仅供查看'
                  : matches
                  ? '当前已连接绑定设备'
                  : '安装时会读取序列号，确认是这台手环',
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Text(
              resource == null
                  ? '应用已下架或暂未提供此型号的版本'
                  : '最新上架 v${resource['version']}',
            ),
            if (appsKnown)
              Text(
                installed == null
                    ? '当前手环尚未安装'
                    : installed.versionCode == 0
                    ? '已安装，设备未返回版本号'
                    : installed.versionCode == latest
                    ? '已是最新版本'
                    : installed.versionCode > latest
                    ? '当前版本高于商店，已阻止降级'
                    : '发现新版本，可直接更新',
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
              ),
            const SizedBox(height: 6),
            Text(
              '激活于 ${stamp.year}.${stamp.month.toString().padLeft(2, '0')}.${stamp.day.toString().padLeft(2, '0')}',
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
            if (_busyId == item['id']) ...[
              const SizedBox(height: 16),
              Text(_stage),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: _progress == null || _progress! >= 1 ? null : _progress,
                minHeight: 6,
                borderRadius: BorderRadius.circular(12),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed:
                    !active ||
                        resource == null ||
                        newer ||
                        _busy ||
                        _loading ||
                        !_storeEnabled ||
                        _error != null
                    ? null
                    : () => _install(item),
                icon: Icon(
                  action == '更新'
                      ? Icons.upgrade_rounded
                      : Icons.install_mobile_rounded,
                ),
                label: Text(action),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
