import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oronbox/src/core/models/bt_models.dart';
import 'package:oronbox/src/features/devices/controllers/device_manager.dart';
import 'package:oronbox/src/protocols/common/device_protocol.dart'
    show ProtocolState;

import 'backend.dart';
import 'cloud_store.dart';
import 'resource_activation_dialog.dart';
import 'store_media.dart';
import 'store_models.dart';

MiWearState? _target(DeviceManagerState state, String? fallback) {
  if (state.protocolState == ProtocolState.ready &&
      state.currentDevice != null) {
    return state.currentDevice;
  }
  for (final device in state.pairedDevices) {
    if (device.addr == fallback) return device;
  }
  return null;
}

String? _model(DeviceManagerState state, MiWearState? device) =>
    storeModelForDevice(
      device,
      systemInfo:
          state.protocolState == ProtocolState.ready &&
              state.currentDevice?.addr == device?.addr
          ? state.systemInfo
          : null,
    );

class CloudStorePage extends ConsumerStatefulWidget {
  const CloudStorePage({
    super.key,
    this.deviceId,
    this.deviceName,
    this.store,
    this.embedded = false,
    this.headerInAppBar = false,
    this.bottomInset = 0,
    this.accountRevision = 0,
    this.onAccountChanged,
  });
  final bool embedded;
  final bool headerInAppBar;
  final double bottomInset;
  final int accountRevision;
  final VoidCallback? onAccountChanged;
  final String? deviceId, deviceName;
  final CloudStore? store;
  @override
  ConsumerState<CloudStorePage> createState() => _CloudStorePageState();
}

class _CloudStorePageState extends ConsumerState<CloudStorePage> {
  CloudStore? _store;
  List<StoreApp> _apps = [];
  bool _loading = true, _enabled = true;
  String? _error, _browseModel;
  String _notice = '', _search = '';
  bool _workshop = false;
  final _searchController = TextEditingController();
  int _loadRevision = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(CloudStorePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accountRevision != widget.accountRevision) _load();
  }

  Future<void> _load() async {
    final revision = ++_loadRevision;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final store = widget.store ?? await CloudStore.connect();
      final policy = await store.info();
      if (!mounted || revision != _loadRevision) return;
      setState(() {
        _enabled = policy['storeEnabled'] == true;
        _notice = policy['notice'] as String? ?? '';
      });
      final resources = _enabled
          ? await store.catalog()
          : <Map<String, dynamic>>[];
      if (mounted && revision == _loadRevision) {
        setState(() {
          _store = store;
          _apps = groupStoreApps(resources);
        });
      }
    } catch (e) {
      if (mounted && revision == _loadRevision) {
        setState(() {
          _error = cloudError(e);
          _apps = [];
          _store = null;
        });
      }
    } finally {
      if (mounted && revision == _loadRevision) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(deviceManagerProvider);
    final device = _target(state, widget.deviceId);
    final current = _model(state, device);
    final model = _browseModel ?? current;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final apps = _apps
        .where(
          (a) =>
              '${a.display(model)['name']} ${a.display(model)['description']}'
                  .toLowerCase()
                  .contains(_search.toLowerCase()),
        )
        .toList();
    final refresh = IconButton(
      onPressed: _loading ? null : _load,
      tooltip: '刷新商店',
      icon: const Icon(Icons.refresh_rounded),
    );
    final content = RefreshIndicator(
      onRefresh: _load,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: CustomScrollView(
            key: const PageStorageKey('store-catalog'),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                sliver: SliverList.list(
                  children: [
                    if (widget.embedded && !widget.headerInAppBar) ...[
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              '应用商店',
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -.7,
                              ),
                            ),
                          ),
                          refresh,
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('精选应用')),
                        ButtonSegment(value: true, label: Text('创意工坊')),
                      ],
                      selected: {_workshop},
                      showSelectedIcon: false,
                      expandedInsets: EdgeInsets.zero,
                      onSelectionChanged: (value) =>
                          setState(() => _workshop = value.single),
                    ),
                    const SizedBox(height: 20),
                    if (_workshop)
                      CreativeWorkshopPreview(
                        onBrowse: () => setState(() => _workshop = false),
                      ),
                    if (!_workshop) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: '搜索应用',
                          prefixIcon: const Icon(Icons.search_rounded),
                          filled: true,
                          fillColor: colors.surfaceContainerLow,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (value) => setState(() => _search = value),
                      ),
                      const SizedBox(height: 16),
                      _ModelPicker(
                        value: _browseModel,
                        current: current,
                        onChanged: (value) =>
                            setState(() => _browseModel = value),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(
                            Icons.bluetooth_rounded,
                            size: 16,
                            color: colors.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              device == null
                                  ? '连接手环后自动匹配安装版本'
                                  : '安装目标 · ${storeModelNames[current] ?? device.name}',
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_notice.isNotEmpty)
                        _MessageCard(
                          icon: Icons.campaign_outlined,
                          text: _notice,
                        ),
                      if (!_enabled)
                        const _MessageCard(
                          icon: Icons.construction_rounded,
                          text: '商店维护中，暂时无法安装应用。',
                        ),
                      if (_error != null)
                        _MessageCard(icon: Icons.info_outline, text: _error!),
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 36),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      if (!_loading && _error == null) ...[
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                '应用精选',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              '${apps.length} 款',
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        if (apps.isEmpty)
                          const _MessageCard(
                            icon: Icons.widgets_outlined,
                            text: '没有找到应用，试试其他关键词。',
                          ),
                      ],
                    ],
                  ],
                ),
              ),
              if (!_workshop && _store != null && !_loading && _error == null)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      mainAxisExtent:
                          280 +
                          (MediaQuery.textScalerOf(context).scale(14) / 14 - 1)
                                  .clamp(0, 2) *
                              220,
                    ),
                    itemCount: apps.length,
                    itemBuilder: (context, index) => StoreAppCard(
                      app: apps[index],
                      model: model,
                      firmware:
                          state.protocolState == ProtocolState.ready &&
                              state.currentDevice?.addr == device?.addr &&
                              model == current
                          ? state.systemInfo?.firmwareVersion.trim() ?? ''
                          : '',
                      store: _store!,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => StoreAppPage(
                            app: apps[index],
                            store: _store!,
                            deviceId: device?.addr,
                            initialModel: _browseModel,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: SizedBox(height: 28 + widget.bottomInset),
              ),
            ],
          ),
        ),
      ),
    );
    return widget.embedded && !widget.headerInAppBar
        ? content
        : Scaffold(
            appBar: AppBar(
              title: Text(
                '应用商店',
                style: widget.headerInAppBar
                    ? const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -.8,
                      )
                    : null,
              ),
              actions: [refresh],
            ),
            body: content,
          );
  }
}

class CreativeWorkshopPreview extends StatelessWidget {
  const CreativeWorkshopPreview({super.key, required this.onBrowse});
  final VoidCallback onBrowse;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('creative-workshop-preview'),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 34),
      decoration: BoxDecoration(
        color: c.surfaceContainerLow,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: c.primary.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(
              Icons.auto_awesome_outlined,
              size: 32,
              color: c.primary,
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            '创意工坊',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: c.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '筹备中',
              style: TextStyle(color: c.onSurfaceVariant, fontSize: 12),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '敬请期待',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.onSurfaceVariant,
              fontSize: 14,
              height: 1.7,
            ),
          ),
          const SizedBox(height: 28),
          OutlinedButton(onPressed: onBrowse, child: const Text('先逛逛精选应用')),
        ],
      ),
    );
  }
}

class StoreAppCard extends StatelessWidget {
  const StoreAppCard({
    super.key,
    required this.app,
    required this.model,
    required this.store,
    required this.onTap,
    this.firmware = '',
  });
  final String firmware;
  final StoreApp app;
  final String? model;
  final CloudStore store;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final item = app.display(model);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final match = app.forDevice(model, firmware);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: .18)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StoreMediaImage(
                id: item['iconId'] as String? ?? '',
                load: store.media,
                width: 52,
                height: 52,
                radius: 15,
              ),
              const SizedBox(height: 12),
              Text(
                '${item['name']}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '${item['category'] ?? '工具'} · v${item['version']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              Text(
                (item['description'] as String? ?? '').isEmpty
                    ? '查看详情与适用型号'
                    : item['description'] as String,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  color:
                      (match != null ? colors.primary : colors.onSurfaceVariant)
                          .withValues(alpha: .07),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  model == null
                      ? '查看适用型号'
                      : match == null
                      ? (app.forModel(model) == null ? '暂无适配版本' : '需核对固件版本')
                      : '型号与固件匹配',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: match != null
                        ? colors.primary
                        : colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StoreAppPage extends ConsumerStatefulWidget {
  const StoreAppPage({
    super.key,
    required this.app,
    required this.store,
    this.deviceId,
    this.initialModel,
  });
  final StoreApp app;
  final CloudStore store;
  final String? deviceId, initialModel;
  @override
  ConsumerState<StoreAppPage> createState() => _StoreAppPageState();
}

class _StoreAppPageState extends ConsumerState<StoreAppPage> {
  late String? _browseModel = widget.initialModel;
  bool _busy = false;
  double? _progress;
  String? _message;
  String _stage = '';

  Future<void> _install(
    MiWearState device,
    String model,
    Map<String, dynamic> item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('安装到当前手环'),
        content: Text(
          '${item['name']} · v${item['version']}\n目标：${storeModelNames[model]}\n\n会使用此型号的安装包，完成传输后等待手环确认。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('开始安装'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _progress = null;
      _stage = '正在连接并校验型号';
      _message = null;
    });
    try {
      await ref
          .read(steadyBackendProvider)
          .installCloud(
            widget.store,
            item['id'] as String,
            device.addr,
            (p) {
              if (mounted) {
                setState(() {
                  _progress = p;
                  _stage = p >= 1 ? '等待手环确认安装结果' : '正在传输到手环';
                });
              }
            },
            expectedModel: model,
            onActivationRequired: (verifiedModel, serial) async {
              if (!mounted) return false;
              return await showDialog<bool>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => ResourceActivationDialog(
                      appName: '${item['name']}',
                      model: verifiedModel,
                      serial: serial,
                      activate: (code) async {
                        final current = ref.read(deviceManagerProvider);
                        if (current.currentDevice?.addr != device.addr ||
                            current.protocolState != ProtocolState.ready ||
                            current.systemInfo?.serialNumber
                                    .trim()
                                    .toUpperCase() !=
                                serial) {
                          throw StateError('手环连接已改变，请取消后重新连接目标手环');
                        }
                        await widget.store.activate(
                          item['id'] as String,
                          verifiedModel,
                          serial,
                          code,
                          firmware:
                              current.systemInfo?.firmwareVersion.trim() ?? '',
                        );
                      },
                    ),
                  ) ==
                  true;
            },
            onStage: (stage) {
              if (mounted) setState(() => _stage = stage);
            },
          );
      if (mounted) setState(() => _message = '${item['name']} 已安装到手环');
    } catch (e) {
      if (mounted) {
        setState(
          () => _message = e is ActivationCancelled
              ? '已取消激活，未开始下载。'
              : '${cloudError(e)}\n安装阶段：$_stage',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _viewImage(String id) => showDialog<void>(
    context: context,
    builder: (context) => Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(title: const Text('应用预览')),
        body: Center(
          child: InteractiveViewer(
            minScale: .5,
            maxScale: 4,
            child: StoreMediaImage(
              id: id,
              load: widget.store.media,
              width: MediaQuery.sizeOf(context).width,
              height: MediaQuery.sizeOf(context).height * .8,
              radius: 0,
              preview: true,
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(deviceManagerProvider);
    final device = _target(state, widget.deviceId);
    final current = _model(state, device);
    final model = _browseModel ?? current;
    final firmware =
        state.protocolState == ProtocolState.ready &&
            state.currentDevice?.addr == device?.addr
        ? state.systemInfo?.firmwareVersion.trim() ?? ''
        : '';
    final variant = widget.app.forDevice(model, firmware);
    final item = variant ?? widget.app.display(model);
    final previews = (item['previewIds'] as List? ?? []).cast<String>();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final canInstall =
        !_busy &&
        device != null &&
        current != null &&
        model == current &&
        variant != null;
    final explanation = device == null
        ? '请先返回设备页，选择并连接手环。'
        : current == null
        ? '暂时无法识别手环型号，请连接手环并刷新设备信息。'
        : model != current
        ? '当前连接的是${storeModelNames[current]}，不能安装其他型号的版本。'
        : variant == null
        ? (widget.app.forModel(current) == null
              ? '暂无适用于${storeModelNames[current]}的安装包，请等待开发者适配。'
              : firmwareMismatch(item, current, firmware) ?? '暂无匹配当前固件的安装包。')
        : null;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('应用详情'),
          automaticallyImplyLeading: !_busy,
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
              children: [
                if (firmwareSummary(item).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Text('安装包适用固件\n${firmwareSummary(item)}'),
                  ),
                Row(
                  children: [
                    StoreMediaImage(
                      id: item['iconId'] as String? ?? '',
                      load: widget.store.media,
                      width: 88,
                      height: 88,
                      radius: 25,
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${item['name']}',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            '${item['category'] ?? '工具'} · v${item['version']}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${((item['size'] as num) / 1048576).toStringAsFixed(1)} MB',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 30),
                if (item['activationRequired'] == true)
                  const _MessageCard(
                    icon: Icons.key_rounded,
                    text: '卡密激活资源 · 一码一手环\n无需登录。授权跟随手环，换手机、换账号后仍可安装和更新。',
                  ),
                _ModelPicker(
                  value: _browseModel,
                  current: current,
                  enabled: !_busy,
                  onChanged: (v) => setState(() => _browseModel = v),
                ),
                if (explanation != null)
                  _MessageCard(
                    icon: Icons.info_outline_rounded,
                    text: explanation,
                  ),
                if (current != null && model != current)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _browseModel = null),
                      icon: const Icon(Icons.sync_rounded),
                      label: const Text('自动匹配当前手环'),
                    ),
                  ),
                const SizedBox(height: 28),
                Text(
                  '先看一眼',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                if (variant == null && model != null && previews.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: Text('以下为其他型号的预览，仅供参考。'),
                  ),
                if (previews.isEmpty)
                  const _MessageCard(
                    icon: Icons.photo_outlined,
                    text: '开发者暂未添加预览图。',
                  ),
                if (previews.isNotEmpty)
                  SizedBox(
                    height: 270,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: previews.length,
                      separatorBuilder: (_, index) => const SizedBox(width: 14),
                      itemBuilder: (context, index) => Semantics(
                        label: '预览图 ${index + 1}，点击放大',
                        button: true,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(22),
                          onTap: () => _viewImage(previews[index]),
                          child: StoreMediaImage(
                            id: previews[index],
                            load: widget.store.media,
                            width: 190,
                            height: 270,
                            radius: 22,
                            preview: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 30),
                Text(
                  '关于这款应用',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  (item['description'] as String? ?? '').isEmpty
                      ? '开发者尚未填写描述。'
                      : item['description'] as String,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    height: 1.75,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 26),
                Text(
                  '已上架型号',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in widget.app.models)
                      ActionChip(
                        label: Text(storeModelNames[entry] ?? entry),
                        onPressed: _busy
                            ? null
                            : () => setState(() => _browseModel = entry),
                      ),
                  ],
                ),
                if (_message != null)
                  _MessageCard(
                    icon: Icons.info_outline_rounded,
                    text: _message!,
                  ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 18),
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border(
                top: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: .4),
                ),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_busy) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(_stage, style: theme.textTheme.labelLarge),
                      ),
                      if (_progress != null)
                        Text('${(_progress! * 100).round()}%'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: _progress ?? 0),
                    duration: const Duration(milliseconds: 280),
                    builder: (_, value, child) => LinearProgressIndicator(
                      value: _progress == null || _progress! >= 1
                          ? null
                          : value,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: canInstall
                        ? () => _install(device, model!, variant)
                        : null,
                    icon: Icon(
                      _busy ? Icons.sync_rounded : Icons.install_mobile_rounded,
                    ),
                    label: Text(
                      _busy
                          ? '安装中，请保持连接'
                          : canInstall
                          ? '安装到${storeModelNames[current]}'
                          : variant == null &&
                                current != null &&
                                model == current
                          ? '暂无适配版本'
                          : '连接对应型号后安装',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModelPicker extends StatelessWidget {
  const _ModelPicker({
    required this.value,
    required this.current,
    required this.onChanged,
    this.enabled = true,
  });
  final String? value, current;
  final ValueChanged<String?> onChanged;
  final bool enabled;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    key: ValueKey('$value:$current'),
    initialValue: value ?? '',
    isExpanded: true,
    decoration: InputDecoration(
      labelText: '浏览型号',
      prefixIcon: const Icon(Icons.watch_outlined),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
    ),
    items: [
      DropdownMenuItem(
        value: '',
        child: Text(
          current == null
              ? '自动匹配 · 等待连接'
              : '自动匹配 · ${storeModelNames[current]}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      for (final model in storeModelNames.entries)
        DropdownMenuItem(
          value: model.key,
          child: Text(
            model.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ],
    onChanged: enabled ? (v) => onChanged(v == '' ? null : v) : null,
  );
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 14),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer
          .withValues(alpha: .4),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 21),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(height: 1.5))),
      ],
    ),
  );
}
