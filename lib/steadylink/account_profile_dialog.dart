import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'wristbox_account.dart';
import 'avatar_crop.dart';

class AccountAvatar extends StatelessWidget {
  const AccountAvatar({super.key, required this.session, this.radius = 36});
  final WristBoxSession? session;
  final double radius;

  @override
  Widget build(BuildContext context) {
    Uint8List? bytes;
    try {
      if (session?.avatar != null) bytes = base64Decode(session!.avatar!);
    } on FormatException {
      // A stale or malformed local cache must not prevent opening the account.
    }
    final colors = Theme.of(context).colorScheme;
    return ClipOval(
      child: SizedBox.square(
        dimension: radius * 2,
        child: bytes == null
            ? ColoredBox(
                color: colors.primaryContainer,
                child: Icon(
                  Icons.person_outline_rounded,
                  color: colors.onPrimaryContainer,
                  size: radius,
                ),
              )
            : Image.memory(
                bytes,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) =>
                    Icon(Icons.person_outline_rounded, size: radius),
              ),
      ),
    );
  }
}

class AccountProfileDialog extends StatefulWidget {
  const AccountProfileDialog({
    super.key,
    required this.service,
    required this.session,
  });
  final WristBoxAccountService service;
  final WristBoxSession session;
  @override
  State<AccountProfileDialog> createState() => _AccountProfileDialogState();
}

class _AccountProfileDialogState extends State<AccountProfileDialog> {
  late WristBoxSession _session;
  late final TextEditingController _nickname;
  bool _busy = false;
  String? _error, _status;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _nickname = TextEditingController(text: _session.nickname);
    _run(() async {
      final fresh = await widget.service.refresh(_session);
      if (!mounted) return;
      _session = fresh;
      _nickname.text = fresh.nickname;
    });
  }

  @override
  void dispose() {
    _nickname.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) _error = accountError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _avatar() => _run(() async {
    final source = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (Platform.isAndroid)
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('从相册选择'),
                onTap: () => Navigator.pop(context, 'gallery'),
              ),
            ListTile(
              leading: const Icon(Icons.folder_open_rounded),
              title: const Text('从文件选择'),
              onTap: () => Navigator.pop(context, 'file'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    Uint8List? original;
    if (source == 'gallery') {
      try {
        original = await const MethodChannel('wristbox/avatar_picker')
            .invokeMethod<Uint8List>('pick');
      } on PlatformException catch (error) {
        throw StateError(error.message ?? '无法打开相册，请改用从文件选择');
      }
    } else {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      );
      if (files.isEmpty || !mounted) return;
      final path = files.first.path;
      if (path == null) throw StateError('无法读取图片，请保存到本机后重试');
      original = await readAvatarFile(path);
    }
    if (original == null || !mounted) return;
    final preview = await decodeAvatarPreview(original);
    Uint8List? data;
    try {
      if (!mounted) return;
      data = await showDialog<Uint8List>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AvatarCropDialog(image: preview),
      );
    } finally {
      preview.dispose();
    }
    if (data == null || !mounted) return;
    final updated = await widget.service.updateAvatar(_session, data);
    if (!mounted) return;
    _session = updated;
    _status = '头像已更新';
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('账号资料'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: AccountAvatar(session: _session, radius: 40)),
                const SizedBox(height: 10),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: _busy ? null : _avatar,
                      icon: const Icon(Icons.photo_library_outlined, size: 18),
                      label: const Text('更换头像'),
                    ),
                    if (_session.avatar != null)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _run(() async {
                                final updated = await widget.service
                                    .updateAvatar(_session, null);
                                if (mounted) {
                                  _session = updated;
                                  _status = '已恢复默认头像';
                                }
                              }),
                        child: const Text('恢复默认'),
                      ),
                  ],
                ),
                Text(
                  '支持最大 20 MB 图片 · 自动压缩上传',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: SelectableText('ID  ${_session.id ?? '待同步'}'),
                    ),
                    if (_session.id != null)
                      IconButton(
                        tooltip: '复制账号 ID',
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: '${_session.id}'),
                          );
                          if (mounted) setState(() => _status = 'ID 已复制');
                        },
                        icon: const Icon(Icons.copy_rounded, size: 18),
                      ),
                  ],
                ),
                Text(
                  _session.role == 'admin'
                      ? '管理员账号 · ID 为固定标识'
                      : 'ID 为固定标识，不随昵称修改而改变',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _nickname,
                  enabled: !_busy,
                  maxLength: 24,
                  maxLines: 1,
                  decoration: const InputDecoration(
                    labelText: '昵称',
                    hintText: '输入昵称',
                  ),
                  onSubmitted: (_) {
                    if (!_busy) _saveNickname();
                  },
                ),
                const SizedBox(height: 4),
                Text(
                  '登录邮箱',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(_session.email),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: LinearProgressIndicator(),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!, style: TextStyle(color: colors.error)),
                  ),
                if (_status != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _status!,
                      style: TextStyle(color: colors.primary),
                    ),
                  ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          await widget.service.logout(_session);
                          if (context.mounted) Navigator.pop(context);
                        }),
                  child: const Text('退出登录'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: _busy ? null : _saveNickname,
            child: const Text('保存昵称'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveNickname() => _run(() async {
    final name = _nickname.text.trim();
    if (name.isEmpty) throw StateError('请输入昵称');
    final updated = await widget.service.updateProfile(_session, name);
    if (!mounted) return;
    _session = updated;
    _nickname.text = updated.nickname;
    _status = '昵称已保存';
  });
}
