import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oronbox/src/core/models/bt_models.dart';
import 'package:oronbox/src/core/services/shared_prefs_service.dart';
import 'package:oronbox/src/features/devices/controllers/device_manager.dart';
import 'package:oronbox/src/protocols/common/device_protocol.dart'
    show ProtocolState;

import 'account_dialog.dart';
import 'admin_releases_page.dart';
import 'cloud_store_page.dart';
import 'client_updates.dart';
import 'wristbox_account.dart';
import 'privacy_gate.dart';
import 'device_key_dialog.dart';
import 'error_message.dart';
import 'band_illustration.dart';
import 'appearance.dart';
import 'backend.dart';
import 'bluetooth_connection_settings.dart';
import 'connection_guide_page.dart';
import 'connection_status.dart';
import 'mobile_motion.dart';
import 'mobile_dock.dart';
import 'local_package.dart';
import 'local_files.dart';
import 'log_import_page.dart';
import 'profile_dashboard.dart';
import 'activated_resources_page.dart';
import 'operation_queue.dart';
import 'open_source.dart';

ThemeData mobileTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF6750A4),
        brightness: brightness,
      ).copyWith(
        surface: dark ? const Color(0xFF111216) : const Color(0xFFF5F6F9),
        surfaceContainerLow: dark ? const Color(0xFF1C1E25) : Colors.white,
        surfaceContainer: dark
            ? const Color(0xFF23252D)
            : const Color(0xFFEEF0F5),
        surfaceContainerHigh: dark
            ? const Color(0xFF2A2C35)
            : const Color(0xFFE9ECF2),
        onSurface: dark ? const Color(0xFFF0F0F5) : const Color(0xFF21232C),
        onSurfaceVariant: dark
            ? const Color(0xFFABAEBC)
            : const Color(0xFF686D7C),
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      toolbarHeight: 68,
      titleSpacing: 20,
      backgroundColor: scheme.surface,
      centerTitle: false,
      scrolledUnderElevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      elevation: 0,
    ),
  );
}

class SteadyMobileApp extends ConsumerWidget {
  const SteadyMobileApp({super.key, this.initialize});
  final Future<void> Function()? initialize;
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    title: 'WristBox',
    debugShowCheckedModeBanner: false,
    theme: mobileTheme(Brightness.light),
    darkTheme: mobileTheme(Brightness.dark),
    themeMode: ref.watch(darkThemeProvider) ? ThemeMode.dark : ThemeMode.light,
    themeAnimationDuration: const Duration(milliseconds: 350),
    home: const MobileHome(),
    builder: (context, child) => PrivacyGate(
      initialize: initialize,
      child: ClientReleaseHost(child: child!),
    ),
  );
}

class MobileHome extends ConsumerStatefulWidget {
  const MobileHome({super.key});
  @override
  ConsumerState<MobileHome> createState() => _MobileHomeState();
}

class _MobileHomeState extends ConsumerState<MobileHome> {
  static const _deviceListPreference = 'wristbox.device_list_expanded';
  bool? _deviceListExpanded;

  @override
  void initState() {
    super.initState();
    final prefs = SharedPrefsService.instance;
    if (prefs.isInitialized) {
      _deviceListExpanded = prefs.getBool(_deviceListPreference);
    }
  }

  Future<void> _toggleDeviceList(bool expanded) async {
    setState(() => _deviceListExpanded = expanded);
    await _guard(() async {
      final prefs = SharedPrefsService.instance;
      if (prefs.isInitialized &&
          !await prefs.setBool(_deviceListPreference, expanded)) {
        throw StateError('列表状态保存失败，下次打开可能恢复默认显示');
      }
    });
  }

  void _openConnectionGuide() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ConnectionGuidePage(
          onAccount: _account,
          onLogs: _logImport,
          onSettings: _connectionSettings,
          onManual: _manual,
        ),
      ),
    );
  }

  void _connectionSettings() {
    if (backend.queue.busy) {
      _message('请等待当前连接或安装任务完成');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const BluetoothConnectionSettings(),
      ),
    );
  }

  int _page = 0;
  bool _storeOpened = false;
  bool _localFiles = false;
  int _accountRevision = 0;
  String? _selected;
  String _query = '';
  SteadyBackend get backend => ref.read(steadyBackendProvider);
  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      _message(friendlyError(error));
    }
  }

  Future<void> _account() async {
    if (backend.queue.busy) {
      _message('请等待当前任务完成后同步账号');
      return;
    }
    final count = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AccountDialog(importDevices: backend.syncDevices),
    );
    if (count != null) _message('已同步 $count 台设备及最新 Key，点击设备即可重新连接');
  }

  Future<void> _logImport() async {
    if (backend.queue.busy) {
      _message('请等待当前连接或安装任务完成后再导入 Key');
      return;
    }
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const LogImportPage()));
  }

  void _select(MiWearState device) {
    setState(() => _selected = device.addr);
    backend.queue.select(device.addr);
  }

  Future<void> _pick(MiWearState target) => _guard(() async {
    // RPK has no registered MIME type on many Android file providers.
    final files = await FilePicker.pickFiles(type: FileType.any);
    if (!mounted) return;
    final paths = files
        .map((f) => f.path)
        .whereType<String>()
        .where(isLocalInstallFile)
        .toList();
    if (paths.length != files.length) _message('请选择 RPK 或 BIN 安装包');
    if (paths.isEmpty) return;
    backend.queue.add(
      paths.map(
        (p) =>
            InstallJob(path: p, deviceId: target.addr, deviceName: target.name),
      ),
    );
    setState(() {
      _selected = target.addr;
      _page = 0;
    });
  });
  Future<void> _manual() async {
    final device = await showDialog<MiWearState>(
      context: context,
      builder: (_) => const _ManualDeviceDialog(),
    );
    if (device != null) {
      await _guard(() => backend.importDevice(device));
    }
  }

  Future<void> _remove(MiWearState target) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('从列表删除此设备？'),
        content: Text('从本机移除「${target.name}」的连接资料，不会清除手环中的应用。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (yes == true) {
      await _guard(() async {
        await backend.removeDevice(target.addr);
        if (mounted && _selected == target.addr) {
          setState(() => _selected = null);
        }
        _message('已从列表删除，可重新同步账号或手动添加');
      });
    }
  }

  Future<void> _updateKey(MiWearState device) async {
    final key = await showDialog<String>(
      context: context,
      builder: (_) => DeviceKeyDialog(device: device),
    );
    if (key == null) return;
    await _guard(() async {
      await backend.updateKey(device.addr, key);
      _message('Key 已保存，请点击设备重新连接');
    });
  }

  Future<void> _uninstall(MiWearState target, AppInfo app) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('卸载 ${app.appName}？'),
        content: Text('将从「${target.name}」卸载此应用，应用内数据可能被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('卸载'),
          ),
        ],
      ),
    );
    if (yes == true) {
      await _guard(() async {
        await backend.uninstall(target.addr, app);
        _message('已卸载 ${app.appName}');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(deviceManagerProvider);
    final queue = ref.watch(steadyBackendProvider).queue;
    return ListenableBuilder(
      listenable: queue,
      builder: (context, _) {
        MiWearState? target;
        for (final d in state.pairedDevices) {
          if (d.addr == _selected) target = d;
        }
        target ??= state.pairedDevices.firstOrNull;
        final selected = target;
        final ready =
            selected != null &&
            state.currentDevice?.addr == selected.addr &&
            state.protocolState == ProtocolState.ready;
        final connecting =
            queue.busy && queue.activeDevice == selected?.addr && !ready;
        final pages = [
          _devices(state, selected, ready, connecting, queue),
          _storeOpened
              ? CloudStorePage(
                  embedded: true,
                  headerInAppBar: true,
                  accountRevision: _accountRevision,
                  onAccountChanged: () => setState(() => _accountRevision++),
                  deviceId: selected?.addr,
                  deviceName: selected?.name,
                  bottomInset: MobileDock.contentInset(context),
                )
              : const SizedBox.shrink(),
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('手环应用')),
                      ButtonSegment(value: true, label: Text('本地文件')),
                    ],
                    selected: {_localFiles},
                    onSelectionChanged: (value) =>
                        setState(() => _localFiles = value.single),
                  ),
                ),
              ),
              Expanded(
                child: _localFiles
                    ? LocalFilesPane(
                        bottomInset: MobileDock.contentInset(context),
                        onPick: () {
                          final target =
                              state.protocolState == ProtocolState.ready
                              ? state.currentDevice ?? selected
                              : selected;
                          if (target == null) {
                            _message('请先添加手环');
                            return;
                          }
                          _pick(target);
                        },
                        onInstall: (file) async {
                          final target =
                              state.protocolState == ProtocolState.ready
                              ? state.currentDevice ?? selected
                              : selected;
                          if (target == null) {
                            _message('请先添加手环');
                            return;
                          }
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('安装本地文件'),
                              content: Text(
                                '${file.name}\n目标：${target.name}\n\n将根据文件内容识别应用或表盘，并发送到此设备。',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('取消'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('安装'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed != true || !mounted) return;
                          final path = await LocalFileService.prepare(file.id);
                          if (!mounted) return;
                          backend.queue.add([
                            InstallJob(
                              path: path,
                              deviceId: target.addr,
                              deviceName: target.name,
                            ),
                          ]);
                          setState(() {
                            _selected = target.addr;
                            _page = 0;
                          });
                        },
                      )
                    : _apps(state, selected, ready, queue.busy),
              ),
            ],
          ),
          _settings(),
        ];
        return Scaffold(
          extendBody: true,
          appBar: _page == 1
              ? null
              : AppBar(
                  title: Text(
                    switch (_page) {
                      2 => '应用',
                      3 => '我的',
                      _ => 'WristBox',
                    },
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.8,
                    ),
                  ),
                  actions: [
                    if (_page == 2) ...[
                      IconButton(
                        tooltip: '安装应用',
                        onPressed: () {
                          final installTarget =
                              state.protocolState == ProtocolState.ready
                              ? state.currentDevice ?? selected
                              : selected;
                          if (installTarget == null) {
                            _message('请先添加手环');
                            return;
                          }
                          _pick(installTarget);
                        },
                        icon: const Icon(Icons.add_rounded),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
          body: SafeArea(
            top: false,
            bottom: false,
            child: IndexedStack(
              index: _page,
              children: [
                for (var i = 0; i < pages.length; i++)
                  TickerMode(enabled: _page == i, child: pages[i]),
              ],
            ),
          ),
          bottomNavigationBar: MobileDock(
            selectedIndex: _page,
            onSelected: (value) => setState(() {
              _page = value;
              if (value == 1) _storeOpened = true;
            }),
            connected:
                state.currentDevice != null &&
                state.protocolState == ProtocolState.ready,
            connecting: const [
              ProtocolState.connecting,
              ProtocolState.connected,
              ProtocolState.authenticating,
            ].contains(state.protocolState),
            deviceName: state.currentDevice?.name ?? selected?.name,
            onInstallPressed: () {
              final installTarget = state.protocolState == ProtocolState.ready
                  ? state.currentDevice ?? selected
                  : selected;
              if (installTarget == null) {
                setState(() => _page = 0);
                _message('请先登录小米账号或手动添加手环');
              } else {
                _pick(installTarget);
              }
            },
          ),
        );
      },
    );
  }

  Widget _devices(
    DeviceManagerState state,
    MiWearState? target,
    bool ready,
    bool connecting,
    OperationQueue queue,
  ) {
    final colors = Theme.of(context).colorScheme;
    final info = ready ? state.systemInfo : null;
    final storage = info?.storageInfo;
    final deviceListExpanded =
        _deviceListExpanded ?? state.pairedDevices.length != 1;
    return ListView(
      key: const PageStorageKey('devices'),
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        24 + MobileDock.contentInset(context),
      ),
      children: [
        _deviceHero(state, target, ready, connecting, queue),
        if (queue.jobs.isNotEmpty) ...[
          const SizedBox(height: 24),
          Row(
            key: const ValueKey('install-task-header'),
            children: [
              const Expanded(
                child: Text(
                  '安装任务',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed: queue.clearFinished,
                child: const Text('清除已完成'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final job in [
            ...queue.jobs.where(
              (j) =>
                  j.phase == InstallPhase.connecting ||
                  j.phase == InstallPhase.installing,
            ),
            ...queue.jobs.where((j) => j.phase == InstallPhase.queued),
            ...queue.jobs.reversed
                .where(
                  (j) =>
                      j.phase == InstallPhase.succeeded ||
                      j.phase == InstallPhase.failed ||
                      j.phase == InstallPhase.cancelled,
                )
                .take(3),
          ])
            MobileTransferCard(job: job, cancel: () => queue.cancel(job)),
        ],
        if (ready) ...[
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (_, constraints) => Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _metric(
                  '电量',
                  state.battery == null ? '—' : '${state.battery!.capacity}%',
                  Icons.battery_5_bar_rounded,
                  (constraints.maxWidth - 10) / 2,
                ),
                _metric(
                  '可用空间',
                  storage == null
                      ? '—'
                      : '${((storage.total - storage.used) / 1048576).toStringAsFixed(1)} MB',
                  Icons.storage_rounded,
                  (constraints.maxWidth - 10) / 2,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              '固件 ${info?.firmwareVersion ?? '待刷新'}',
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
          ),
        ],
        if (queue.connectionError != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              queue.connectionError!,
              style: TextStyle(color: colors.error),
            ),
          ),
        const SizedBox(height: 26),
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  expanded: deviceListExpanded,
                  child: TextButton(
                    key: const ValueKey('device-list-toggle'),
                    onPressed: () => _toggleDeviceList(!deviceListExpanded),
                    style: TextButton.styleFrom(
                      foregroundColor: colors.onSurface,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    child: Wrap(
                      spacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text(
                          '我的设备',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${state.pairedDevices.length} 台 · ${deviceListExpanded ? '收起' : '展开'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        Icon(
                          deviceListExpanded
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: '同步设备',
              onPressed: queue.busy ? null : _account,
              icon: const Icon(Icons.sync_rounded),
            ),
            IconButton(
              tooltip: '手动添加',
              onPressed: queue.busy ? null : _manual,
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        if (deviceListExpanded) ...[
          if (state.pairedDevices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '设备同步后会显示在这里，也可以手动添加。',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            ),
          for (final d in state.pairedDevices)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Material(
                color: colors.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: target?.addr == d.addr
                        ? colors.primary.withValues(alpha: .35)
                        : colors.outlineVariant.withValues(alpha: .15),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  contentPadding: const EdgeInsets.only(left: 16, right: 4),
                  minVerticalPadding: 12,
                  leading: BandIllustration(
                    pro: isProBand(d.name),
                    width: 36,
                    height: 48,
                    screen: ready && target?.addr == d.addr
                        ? BandScreen.battery
                        : BandScreen.idle,
                    battery: ready && target?.addr == d.addr
                        ? state.battery?.capacity
                        : null,
                  ),
                  title: Text(d.name),
                  subtitle: Text(
                    target?.addr == d.addr
                        ? ready
                              ? '当前连接'
                              : '已选择'
                        : '点击切换连接',
                  ),
                  onTap: () => _select(d),
                  trailing: PopupMenuButton<String>(
                    tooltip: '设备操作',
                    onSelected: (action) =>
                        action == 'key' ? _updateKey(d) : _remove(d),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        enabled: !queue.busy,
                        value: 'key',
                        child: const Text('更新 Key'),
                      ),
                      PopupMenuItem(
                        enabled: !queue.busy,
                        value: 'remove',
                        child: const Text('从列表删除'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (state.pairedDevices.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '安装中切换设备，会在当前任务结束后自动连接。',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
        ],
        const SizedBox(height: 22),
        _connectionGuideEntry(),
      ],
    );
  }

  Widget _connectionGuideEntry() {
    final colors = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('connection-guide-entry'),
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _openConnectionGuide,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.menu_book_rounded,
                  color: colors.primary,
                  size: 25,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text(
                          '连接教程',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '使用指南',
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '获取 Key · 配对连接 · 常见问题',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _deviceHero(
    DeviceManagerState state,
    MiWearState? target,
    bool ready,
    bool connecting,
    OperationQueue queue,
  ) {
    final colors = Theme.of(context).colorScheme;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final statusColor = ready
        ? (colors.brightness == Brightness.dark
              ? const Color(0xFF8CD8B4)
              : const Color(0xFF237652))
        : connecting
        ? colors.primary
        : colors.onSurfaceVariant;
    final job = queue.jobs
        .where(
          (j) =>
              j.deviceId == target?.addr &&
              (j.phase == InstallPhase.connecting ||
                  j.phase == InstallPhase.installing),
        )
        .firstOrNull;
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: .09),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  ready
                      ? '已连接'
                      : connecting
                      ? mobileConnectionStatus(state.connectionPhase)
                      : target == null
                      ? '未添加设备'
                      : '未连接',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          target?.name ?? '添加你的手环',
          style: TextStyle(
            fontSize: 24,
            height: 1.3,
            fontWeight: FontWeight.w600,
            letterSpacing: -.6,
            color: colors.onSurface,
          ),
        ),
        if (!ready) ...[
          const SizedBox(height: 8),
          Text(
            target == null
                ? '登录小米账号同步设备'
                : connecting
                ? mobileConnectionHint(state.connectionPhase)
                : '打开蓝牙，保持手环在附近',
            style: TextStyle(
              fontSize: 12,
              height: 1.6,
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
    final illustration = ConnectionOrbit(
      ready: ready,
      connecting: connecting,
      pro: isProBand(target?.name ?? ''),
      battery: ready ? state.battery?.capacity : null,
      job: job,
    );
    return Container(
      key: const ValueKey('mobile-device-hero'),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .18)),
        gradient: LinearGradient(
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
          colors: [
            colors.surfaceContainerLow,
            Color.alphaBlend(
              colors.primary.withValues(alpha: .07),
              colors.surfaceContainerLow,
            ),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked =
                  constraints.maxWidth < 260 ||
                  MediaQuery.textScalerOf(context).scale(14) > 20;
              return AnimatedSize(
                duration: reduce
                    ? Duration.zero
                    : const Duration(milliseconds: 250),
                child: stacked
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          identity,
                          const SizedBox(height: 12),
                          Center(child: illustration),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: identity),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 108,
                            child: FittedBox(child: illustration),
                          ),
                        ],
                      ),
              );
            },
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: target == null
                  ? _account
                  : connecting
                  ? null
                  : ready
                  ? () => _pick(target)
                  : () => _select(target),
              icon: Icon(
                target == null
                    ? Icons.person_outline_rounded
                    : ready
                    ? Icons.add_rounded
                    : Icons.bluetooth_rounded,
                size: 20,
              ),
              label: Text(
                target == null
                    ? '登录小米账号'
                    : connecting
                    ? '连接中…'
                    : ready
                    ? '选择安装包'
                    : '连接设备',
              ),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          if (connecting) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => _guard(backend.cancelConnection),
              icon: const Icon(Icons.close_rounded),
              label: const Text('取消连接'),
            ),
          ],
          if (target == null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _logImport,
              icon: const Icon(Icons.folder_zip_outlined),
              label: const Text('从运动健康日志导入'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metric(String label, String value, IconData icon, double width) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: colors.onSurfaceVariant, size: 16),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w600,
              letterSpacing: -.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _apps(
    DeviceManagerState state,
    MiWearState? target,
    bool ready,
    bool busy,
  ) {
    final colors = Theme.of(context).colorScheme;
    final apps = ready
        ? state.apps
              .where(
                (a) => '${a.appName} ${a.packageName}'.toLowerCase().contains(
                  _query.toLowerCase(),
                ),
              )
              .toList()
        : <AppInfo>[];
    return ListView(
      key: const PageStorageKey('apps'),
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        24 + MobileDock.contentInset(context),
      ),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                target?.name ?? '请先添加设备',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            ),
            IconButton(
              tooltip: '刷新应用',
              onPressed: target == null || busy
                  ? null
                  : () => _guard(() => backend.refresh(target.addr)),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: _query,
          onChanged: (v) => setState(() => _query = v),
          decoration: const InputDecoration(
            hintText: '搜索应用或包名',
            prefixIcon: Icon(Icons.search_rounded),
          ),
        ),
        const SizedBox(height: 20),
        if (!ready)
          _empty(
            Icons.bluetooth_rounded,
            '连接后，查看手环上的应用',
            target == null ? '先到设备页登录账号或添加手环。' : '到设备页连接，或点击右上方刷新。',
          ),
        if (ready && apps.isEmpty)
          _empty(
            Icons.apps_rounded,
            _query.isEmpty ? '暂无应用' : '没有匹配的应用',
            _query.isEmpty ? '点击刷新读取列表，或安装一个新应用。' : '试试其他名称或包名。',
          ),
        for (final app in apps)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(24),
              child: ListTile(
                minVerticalPadding: 16,
                leading: CircleAvatar(
                  backgroundColor: colors.secondaryContainer,
                  foregroundColor: colors.onSecondaryContainer,
                  child: const Icon(Icons.apps_rounded),
                ),
                title: Text(app.appName),
                subtitle: Text(
                  app.packageName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: IconButton(
                  tooltip: app.canRemove ? '卸载 ${app.appName}' : '系统应用不可卸载',
                  onPressed: !busy && app.canRemove && target != null
                      ? () => _uninstall(target, app)
                      : null,
                  icon: Icon(
                    app.canRemove
                        ? Icons.delete_outline_rounded
                        : Icons.lock_outline_rounded,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _empty(IconData icon, String title, String subtitle) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 8),
    child: Column(
      children: [
        Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 20),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            height: 1.5,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );

  Widget _settings() => ListView(
    padding: EdgeInsets.fromLTRB(
      20,
      8,
      20,
      24 + MobileDock.contentInset(context),
    ),
    children: [
      WristBoxAccountButton(
        key: ValueKey(_accountRevision),
        prominent: true,
        onChanged: () => setState(() => _accountRevision++),
      ),
      const SizedBox(height: 14),
      const MembershipPlaceholder(),
      if (WristBoxAccountService().stored()?.role == 'admin') ...[
        const SizedBox(height: 14),
        _setting(
          Icons.campaign_outlined,
          '公告管理',
          '管理员 · 编写和发布弹窗公告',
          () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const AdminAnnouncementsPage(),
            ),
          ),
        ),
      ],
      const SizedBox(height: 14),
      _setting(
        Icons.verified_outlined,
        '已激活资源',
        '查看绑定手环 · 快捷安装与更新',
        () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const ActivatedResourcesPage(),
          ),
        ),
      ),
      const SizedBox(height: 26),
      const Text(
        '通用',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 12),
      _setting(
        Icons.system_update_rounded,
        '更新与公告',
        '检查新版本 · 查看发布公告',
        () => ClientReleaseHost.check(context),
      ),
      const SizedBox(height: 12),
      _setting(Icons.person_outline_rounded, '小米账号', '登录并同步设备与认证资料', _account),
      _setting(Icons.bluetooth_rounded, '蓝牙连接方式', '优先保留系统配对 · 兼容设置', () {
        if (backend.queue.busy) {
          _message('请等待当前连接或安装任务完成');
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const BluetoothConnectionSettings(),
          ),
        );
      }),
      _setting(
        Icons.folder_zip_outlined,
        '从日志导入 Key',
        '运动健康导出教程 · 仅在本地解析',
        _logImport,
      ),
      _setting(Icons.add_link_rounded, '手动添加设备', '输入设备连接资料', _manual),
      _setting(
        Icons.motion_photos_on_rounded,
        '动效预览',
        '查看连接与安装动画',
        () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const MotionPreview())),
      ),
      SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        secondary: const Icon(Icons.dark_mode_outlined),
        title: const Text('深色外观'),
        value: ref.watch(darkThemeProvider),
        onChanged: (_) => _guard(ref.read(darkThemeProvider.notifier).toggle),
      ),
      const SizedBox(height: 24),
      _setting(
        Icons.privacy_tip_outlined,
        '隐私与协议',
        '隐私政策 · 用户协议 · 安装风险说明',
        () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const PrivacyCenter())),
      ),
      _setting(
        Icons.info_outline_rounded,
        '关于 WristBox',
        '$clientVersion · Android',
        () => showAboutDialog(
          context: context,
          applicationName: 'WristBox',
          applicationVersion: '$clientVersion · Android',
          applicationLegalese: 'AGPL-3.0 · 基于 OronBox',
          children: const [
            SizedBox(height: 12),
            OpenSourceNotice(),
            SizedBox(height: 12),
            Text(
              '上游项目：\nhttps://github.com/zxor-org/OronBox\n\n单设备会话，支持多设备保存与串行切换。不同型号与固件的兼容性以实机测试为准。',
            ),
          ],
        ),
      ),
      const Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          '账号资料与设备密钥通过 Android Keystore 加密保存在本机。动效遵循系统的减少动画设置。',
          style: TextStyle(fontSize: 12, height: 1.7),
        ),
      ),
    ],
  );
  Widget _setting(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback action,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: action,
      ),
    ),
  );
}

class _ManualDeviceDialog extends StatefulWidget {
  const _ManualDeviceDialog();
  @override
  State<_ManualDeviceDialog> createState() => _ManualDeviceDialogState();
}

class _ManualDeviceDialogState extends State<_ManualDeviceDialog> {
  final _name = TextEditingController(),
      _mac = TextEditingController(),
      _key = TextEditingController();
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _name.dispose();
    _mac.dispose();
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('手动添加设备'),
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: '设备名称'),
            validator: (v) => v!.trim().isEmpty ? '请输入名称' : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _mac,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: '蓝牙 MAC 地址',
              hintText: 'AA:BB:CC:DD:EE:FF',
            ),
            validator: (v) =>
                RegExp(r'^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}$')
                    .hasMatch(v!.trim())
                ? null
                : '请输入完整蓝牙地址',
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _key,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: 'AuthKey'),
            validator: (v) => RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(v!.trim())
                ? null
                : '请输入 32 位十六进制 Key',
          ),
        ],
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
            Navigator.pop(
              context,
              MiWearState(
                name: _name.text.trim(),
                addr: _mac.text.trim().toUpperCase(),
                authkey: _key.text.trim(),
                connectType: 'spp',
                disconnected: true,
              ),
            );
          }
        },
        child: const Text('添加'),
      ),
    ],
  );
}
