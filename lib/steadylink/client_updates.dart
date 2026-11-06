import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:oronbox/src/core/services/shared_prefs_service.dart';

import 'backend.dart';
import 'operation_queue.dart';
import 'wristbox_account.dart';
import 'network_error.dart';

const clientVersion = '0.14.12';
const clientBuild = 41;
const _native = MethodChannel('wristbox/updates');

String updateError(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['detail'] is String) {
      return data['detail'] as String;
    }
    return networkErrorMessage(error);
  }
  if (error is StateError) return error.message.toString();
  return '操作未完成，请检查网络、磁盘空间或安装权限后重试';
}

Future<Dio> updateClient() async {
  final service = WristBoxAccountService();
  final session = service.stored();
  return session == null
      ? service.publicClient()
      : service.authenticatedClient(session);
}

Future<bool> verifyUpdate(File file, int size, String hash) async =>
    await file.length() == size &&
    (await sha256.bind(file.openRead()).first).toString() == hash;

/// Shared policy for automatic prompts and offline recovery.
bool requiresUpdate(Map<String, dynamic> status, int build) =>
    status['mandatory'] == true &&
    status['release'] is Map &&
    (status['minimumBuild'] as num? ?? 0) > build &&
    (status['release']['build'] as num? ?? 0) > build;

class ClientReleaseHost extends ConsumerStatefulWidget {
  const ClientReleaseHost({
    super.key,
    required this.child,
    this.fetchStatus,
    this.queue,
  });
  final Widget child;
  final Future<Map<String, dynamic>> Function()? fetchStatus;
  final OperationQueue? queue;
  static void check(BuildContext context) => context
      .findAncestorStateOfType<ClientReleaseHostState>()
      ?.check(manual: true);
  @override
  ConsumerState<ClientReleaseHost> createState() => ClientReleaseHostState();
}

class ClientReleaseHostState extends ConsumerState<ClientReleaseHost>
    with WidgetsBindingObserver {
  final _prefs = SharedPrefsService.instance;
  Map<String, dynamic> _status = {};
  Map<String, dynamic>? _release, _notice;
  OperationQueue? _queue;
  Timer? _timer;
  bool _checking = false, _working = false, _force = false, _manual = false;
  double? _progress;
  String? _message;
  int _build = clientBuild;
  final Set<String> _viewed = {};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    _queue = widget.queue ?? ref.read(steadyBackendProvider).queue;
    _queue!.addListener(_offer);
    if (Platform.isAndroid) {
      try {
        _build =
            (await _native.invokeMapMethod<String, dynamic>(
                  'version',
                ))!['build']
                as int;
      } catch (_) {}
    }
    try {
      _status = (jsonDecode(
        _prefs.getString('client.update.cache') ?? '{}',
      ) as Map).cast<String, dynamic>();
    } catch (_) {}
    if (!mounted) return;
    if (requiresUpdate(_status, _build)) _offer();
    await check();
    if (mounted) {
      _timer = Timer.periodic(const Duration(minutes: 15), (_) => check());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) check();
  }

  Future<void> check({bool manual = false}) async {
    if (_checking || _working) return;
    _checking = true;
    if (manual) {
      _manual = true;
      _viewed.clear();
    }
    Dio? dio;
    try {
      Map<String, dynamic> status;
      if (widget.fetchStatus != null) {
        status = await widget.fetchStatus!();
      } else {
        dio = await updateClient();
        final response = await dio.get<dynamic>(
          'v1/client/status',
          queryParameters: {
            'platform': Platform.isAndroid ? 'android' : 'windows',
            'build': _build,
          },
        );
        status = (response.data as Map).cast<String, dynamic>();
      }
      if (!mounted) return;
      _status = status;
      await _prefs.setString('client.update.cache', jsonEncode(_status));
      if (!mounted) return;
      _message = null;
      _offer();
      if (manual &&
          _release == null &&
          _notice == null &&
          _queue?.busy != true) {
        setState(() => _message = '当前已是最新版本，暂无发布公告');
      } else if (manual && _queue?.busy == true) {
        setState(() => _message = '正在连接或安装，任务完成后显示更新与公告');
      }
    } catch (error) {
      if (mounted && (manual || _force)) {
        setState(() => _message = '检查更新失败，请稍后重试。${updateError(error)}');
      }
    } finally {
      dio?.close();
      _checking = false;
    }
  }

  void _offer() {
    if (!mounted || _queue?.busy == true || _working) return;
    final latest = _status['release'];
    _force = requiresUpdate(_status, _build);
    _release =
        latest is Map &&
            (latest['build'] as num) > _build &&
            (_force ||
                _manual ||
                _prefs.getInt('client.update.dismissed') != latest['build'])
        ? latest.cast<String, dynamic>()
        : null;
    _notice = null;
    if (_release == null) {
      for (final item in (_status['announcements'] as List? ?? [])) {
        final key = '${item['id']}:${item['revision']}';
        if (!_viewed.contains(key) &&
            (_manual || _prefs.getBool('client.notice.$key') != true)) {
          _notice = (item as Map).cast<String, dynamic>();
          break;
        }
      }
    }
    setState(() {});
  }

  Future<void> _later() async {
    await _prefs.setInt('client.update.dismissed', _release!['build'] as int);
    _manual = false;
    _message = null;
    _offer();
  }

  Future<void> _read() async {
    final key = '${_notice!['id']}:${_notice!['revision']}';
    _viewed.add(key);
    await _prefs.setBool('client.notice.$key', true);
    _message = null;
    _offer();
  }

  Future<void> _install() async {
    final release = Map<String, dynamic>.of(_release!);
    setState(() {
      _working = true;
      _progress = 0;
      _message = null;
    });
    Dio? dio;
    File? partial;
    try {
      final id = release['packageId'] as String;
      final size = release['size'] as int;
      final hash = release['sha256'] as String;
      if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id) ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) ||
          size <= 0 ||
          size > 128 * 1024 * 1024) {
        throw StateError('更新包信息无效');
      }
      final dir = Directory(
        '${(await getTemporaryDirectory()).path}/wristbox-updates',
      );
      await dir.create(recursive: true);
      final file = File(
        '${dir.path}/$id.${Platform.isAndroid ? 'apk' : 'zip'}',
      );
      if (!await file.exists() || !await verifyUpdate(file, size, hash)) {
        dio = await updateClient();
        partial = File('${file.path}.part');
        final response = await dio.get<ResponseBody>(
          'v1/client/packages/$id',
          options: Options(
            responseType: ResponseType.stream,
            receiveTimeout: const Duration(seconds: 60),
          ),
        );
        final sink = partial.openWrite();
        var received = 0;
        try {
          await for (final chunk in response.data!.stream) {
            received += chunk.length;
            if (received > size) throw StateError('更新包大小异常');
            sink.add(chunk);
            if (mounted) setState(() => _progress = received / size);
          }
        } finally {
          await sink.close();
        }
        if (!await verifyUpdate(partial, size, hash)) {
          throw StateError('更新包校验失败，请重新下载');
        }
        if (await file.exists()) await file.delete();
        await partial.rename(file.path);
      }
      if (Platform.isAndroid) {
        final result = await _native.invokeMethod<String>('install', {
          'path': file.path,
          'build': release['build'],
        });
        _message = result == 'permission_required'
            ? '请允许 WristBox 安装应用，返回后再次点击安装。'
            : '系统安装界面已打开。完成安装后请重新打开 WristBox。';
      } else {
        final destination = await FilePicker.saveFile(
          bytes: await file.readAsBytes(),
          dialogTitle: '保存已校验的更新包',
          fileName: 'WristBox-${release['version']}-windows-x64.zip',
        );
        if (destination != null) {
          _message = '更新包已保存。请关闭 WristBox，解压后运行新版 WristBox.exe。';
        }
      }
    } catch (error) {
      _message = error is PlatformException
          ? (error.message ?? '无法打开安装器')
          : updateError(error);
    } finally {
      dio?.close();
      if (partial != null && await partial.exists()) await partial.delete();
      if (mounted) {
        setState(() {
          _working = false;
          _progress = null;
        });
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _queue?.removeListener(_offer);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _release != null || _notice != null || _message != null;
    return Stack(
      children: [
        ExcludeFocus(
          excluding: visible,
          child: AbsorbPointer(absorbing: visible, child: widget.child),
        ),
        if (visible) ...[
          const ModalBarrier(dismissible: false, color: Colors.black54),
          Center(
            child: PopScope(
              canPop: false,
              child: Dialog(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _release != null
                              ? Icons.system_update_rounded
                              : Icons.campaign_outlined,
                          size: 36,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 18),
                        Text(
                          _release?['title'] ?? _notice?['title'] ?? '更新与公告',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        if (_release != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              'v${_release!['version']} · ${_force ? '需要更新后继续使用' : '发现新版本'}',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),
                        if (_release != null || _notice != null)
                          Text(
                            _release?['notes'] ?? _notice?['body'] ?? '',
                            style: const TextStyle(height: 1.65),
                          ),
                        if (_progress != null) ...[
                          const SizedBox(height: 24),
                          LinearProgressIndicator(
                            value: _progress,
                            borderRadius: BorderRadius.circular(8),
                            minHeight: 7,
                          ),
                          const SizedBox(height: 8),
                          Text('下载并校验更新包 · ${(_progress! * 100).round()}%'),
                        ],
                        if (_message != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(_message!),
                          ),
                        const SizedBox(height: 24),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (_release != null) ...[
                              FilledButton.icon(
                                onPressed: _working ? null : _install,
                                icon: const Icon(Icons.download_rounded),
                                label: Text(
                                  _working
                                      ? '正在下载'
                                      : Platform.isAndroid
                                      ? '下载并安装'
                                      : '下载更新包',
                                ),
                              ),
                              if (!_force)
                                TextButton(
                                  onPressed: _working ? null : _later,
                                  child: const Text('稍后再说'),
                                ),
                              TextButton(
                                onPressed: _working
                                    ? null
                                    : () => check(manual: true),
                                child: const Text('重新检查'),
                              ),
                            ] else
                              TextButton(
                                onPressed: _notice != null
                                    ? _read
                                    : () => setState(() => _message = null),
                                child: const Text('知道了'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
