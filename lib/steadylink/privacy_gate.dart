import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:oronbox/src/core/logging/logging_service.dart';
import 'package:oronbox/src/core/services/shared_prefs_service.dart';

import 'backend.dart';
import 'legal_documents.dart';
import 'open_source.dart';

const consentPreference = 'wristbox.privacy.consent';
bool _runtimeReady = false;

Future<void> _startRuntime() async {
  if (_runtimeReady) return;
  final prefs = SharedPrefsService.instance;
  if (!prefs.isSecureStorageReady) await prefs.initializeSecureStorage();
  await initLogging();
  installGlobalErrorLogging();
  _runtimeReady = true;
}

Future<void> _exitApp() async {
  if (Platform.isWindows) {
    await windowManager.close();
  } else {
    await SystemNavigator.pop();
  }
}

class PrivacyGate extends StatefulWidget {
  const PrivacyGate({super.key, required this.child, this.initialize});
  final Widget child;
  final Future<void> Function()? initialize;
  @override
  State<PrivacyGate> createState() => PrivacyGateState();
}

class PrivacyGateState extends State<PrivacyGate> {
  bool _ready = false, _busy = false, _checked = false;
  final _read = <int>{};
  int? _document;
  String? _error;

  @override
  void initState() {
    super.initState();
    final prefs = SharedPrefsService.instance;
    if (prefs.isInitialized &&
        prefs.getString(consentPreference) == legalVersion) {
      _enter(save: false);
    }
  }

  Future<void> _enter({bool save = true}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (save) {
        final prefs = SharedPrefsService.instance;
        if (!await prefs.setString(consentPreference, legalVersion)) {
          throw StateError('无法保存确认记录，请重试');
        }
        await prefs.setInt(
          'wristbox.privacy.confirmedAt',
          DateTime.now().millisecondsSinceEpoch,
        );
      }
      await (widget.initialize ?? _startRuntime)();
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _error = '初始化失败，请重试；你的设备与账号资料不会因此删除。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> withdraw() async {
    final prefs = SharedPrefsService.instance;
    if (!await prefs.remove(consentPreference)) throw StateError('撤回未保存，请重试');
    await prefs.remove('wristbox.privacy.confirmedAt');
    if (mounted) {
      setState(() {
        _ready = false;
        _checked = false;
        _read.clear();
        _document = null;
      });
    }
    await _exitApp();
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.child;
    final index = _document;
    if (index != null) {
      return LegalReader(
        document: legalDocuments[index],
        onClose: (read) {
          setState(() {
            if (read) _read.add(index);
            _document = null;
          });
        },
      );
    }
    final colors = Theme.of(context).colorScheme;
    final allRead = _read.length == legalDocuments.length;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(28),
              children: [
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Icon(
                      Icons.shield_outlined,
                      size: 40,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  '开始之前',
                  style: Theme.of(context).textTheme.headlineLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                const Text(
                  '欢迎使用 WristBox。请分别阅读以下说明，再决定是否继续。',
                  style: TextStyle(height: 1.7),
                ),
                const SizedBox(height: 16),
                const OpenSourceNotice(compact: true),
                const SizedBox(height: 24),
                for (var i = 0; i < legalDocuments.length; i++) ...[
                  Card(
                    elevation: 0,
                    color: colors.surfaceContainerLow,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      leading: Icon(
                        _read.contains(i)
                            ? Icons.check_circle_rounded
                            : Icons.article_outlined,
                        color: colors.primary,
                      ),
                      title: Text(legalDocuments[i].title),
                      subtitle: Text(
                        _read.contains(i)
                            ? '已阅读，可再次查看'
                            : legalDocuments[i].summary,
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _busy ? null : () => setState(() => _document = i),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _checked,
                  onChanged: allRead && !_busy
                      ? (v) => setState(() => _checked = v!)
                      : null,
                  title: const Text(
                    '我已阅读并同意上述协议与说明',
                    style: TextStyle(fontSize: 14),
                  ),
                  subtitle: allRead ? null : const Text('请依次打开并阅读至文末'),
                ),
                if (_error != null)
                  Text(_error!, style: TextStyle(color: colors.error)),
                const SizedBox(height: 16),
                AnimatedConsentButton(
                  enabled: allRead && _checked && !_busy,
                  busy: _busy,
                  onPressed: () => _enter(),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy ? null : _exitApp,
                  child: const Text('暂不同意，退出'),
                ),
                const SizedBox(height: 12),
                Text(
                  '账号为可选功能。系统权限在使用对应功能时申请。\n你可以随时在“隐私与协议”中查看或撤回同意。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.7,
                    color: colors.onSurfaceVariant,
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

class AnimatedConsentButton extends StatelessWidget {
  const AnimatedConsentButton({
    super.key,
    required this.enabled,
    required this.busy,
    required this.onPressed,
  });
  final bool enabled, busy;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return AnimatedContainer(
      duration: Duration(milliseconds: reduced ? 0 : 350),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          if (enabled)
            BoxShadow(
              color: colors.primary.withValues(alpha: .22),
              blurRadius: 22,
              offset: const Offset(0, 7),
            ),
        ],
      ),
      child: FilledButton(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(58),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
        onPressed: enabled ? onPressed : null,
        child: AnimatedSwitcher(
          duration: Duration(milliseconds: reduced ? 0 : 250),
          child: busy
              ? const SizedBox(
                  key: ValueKey('busy'),
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Row(
                  key: ValueKey(enabled),
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(enabled ? '同意并进入 WristBox' : '阅读并确认后继续'),
                    const SizedBox(width: 10),
                    Icon(
                      enabled
                          ? Icons.arrow_forward_rounded
                          : Icons.lock_outline_rounded,
                      size: 20,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class LegalReader extends StatefulWidget {
  const LegalReader({super.key, required this.document, required this.onClose});
  final LegalDocument document;
  final void Function(bool read) onClose;
  @override
  State<LegalReader> createState() => _LegalReaderState();
}

class _LegalReaderState extends State<LegalReader> {
  final _scroll = ScrollController();
  bool _end = false;
  @override
  void initState() {
    super.initState();
    _scroll.addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  void _check() {
    if (mounted &&
        !_end &&
        _scroll.hasClients &&
        _scroll.position.extentAfter < 24) {
      setState(() => _end = true);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) widget.onClose(_end);
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.document.title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => widget.onClose(_end),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                widget.document.summary,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Text(
                '版本 $legalVersion',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              for (final section in widget.document.sections) ...[
                const SizedBox(height: 28),
                Text(
                  section.$1,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                SelectableText(
                  section.$2,
                  style: const TextStyle(height: 1.8, fontSize: 15),
                ),
              ],
              const SizedBox(height: 36),
              const Text('— 全文结束 —', textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: FilledButton(
            onPressed: _end ? () => widget.onClose(true) : null,
            child: Text(_end ? '已阅读，返回' : '请阅读至文末'),
          ),
        ),
      ),
    ),
  );
}

class PrivacyCenter extends ConsumerWidget {
  const PrivacyCenter({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('隐私与协议')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        for (final document in legalDocuments)
          ListTile(
            title: Text(document.title),
            subtitle: Text(document.summary),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (routeContext) => LegalReader(
                  document: document,
                  onClose: (_) => Navigator.pop(routeContext),
                ),
              ),
            ),
          ),
        const Divider(height: 32),
        const ListTile(
          title: Text('联系开发者 / 个人信息请求'),
          subtitle: SelectableText(
            '$legalOperator\n$legalContact\n查询、删除、账号注销或授权售后可通过邮箱联系。',
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: () async {
            final backend = ref.read(steadyBackendProvider);
            if (backend.queue.busy) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('请等待当前设备操作完成，再撤回同意。')),
              );
              return;
            }
            final confirm = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('撤回同意并退出？'),
                content: const Text(
                  '应用将断开设备并退出，下次启动会重新询问。此操作不会自动删除本地资料或云端激活记录；如需删除或注销，请联系开发者。',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('取消'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('撤回并退出'),
                  ),
                ],
              ),
            );
            if (confirm != true || !context.mounted) return;
            if (backend.queue.busy) return;
            try {
              try {
                await backend.manager.disconnect().timeout(
                  const Duration(seconds: 5),
                );
              } catch (_) {
                // A broken Bluetooth connection must not prevent withdrawal.
              }
              if (context.mounted) {
                await context
                    .findAncestorStateOfType<PrivacyGateState>()
                    ?.withdraw();
              }
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('操作未完成，请稍后重试。')));
              }
            }
          },
          child: const Text('撤回同意并退出'),
        ),
      ],
    ),
  );
}
