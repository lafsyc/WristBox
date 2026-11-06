import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'admin_api.dart';
import 'client_updates.dart';

class AdminAnnouncementsPage extends StatefulWidget {
  const AdminAnnouncementsPage({super.key, this.connect});
  final Future<AdminApi> Function()? connect;
  @override
  State<AdminAnnouncementsPage> createState() => _AdminAnnouncementsPageState();
}

class _AdminAnnouncementsPageState extends State<AdminAnnouncementsPage> {
  AdminApi? _api;
  String? _error;
  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    setState(() => _error = null);
    try {
      final api = await (widget.connect ?? AdminApi.connectAnnouncements)();
      if (!mounted) {
        api.dio.close();
        return;
      }
      setState(() => _api = api);
    } catch (e) {
      if (mounted) setState(() => _error = updateError(e));
    }
  }

  @override
  void dispose() {
    _api?.dio.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _api != null
      ? AdminReleasesPage(api: _api!, announcementsOnly: true)
      : Scaffold(
          appBar: AppBar(title: const Text('公告管理')),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: _connect,
                          child: const Text('重新检查权限'),
                        ),
                      ],
                    ),
            ),
          ),
        );
}

class AdminReleasesPage extends StatefulWidget {
  const AdminReleasesPage({
    super.key,
    required this.api,
    this.announcementsOnly = false,
  });
  final AdminApi api;
  final bool announcementsOnly;
  @override
  State<AdminReleasesPage> createState() => _AdminReleasesPageState();
}

class _AdminReleasesPageState extends State<AdminReleasesPage> {
  List<dynamic> _releases = [], _notices = [];
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final notices = await widget.api.get('announcements');
      final releases = widget.announcementsOnly
          ? <String, dynamic>{'items': <dynamic>[]}
          : await widget.api.get('client-releases');
      if (mounted) {
        setState(() {
          _releases = releases['items'] as List;
          _notices = notices['items'] as List;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = updateError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _published(Map row) => row['published'] == true || row['published'] == 1;
  String _platform(dynamic value) => switch (value) {
    'android' => 'Android',
    'windows' => 'Windows · 仅管理员',
    _ => '全部平台',
  };
  Future<void> _publish(Map row, bool release) async {
    final publish = !_published(row);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(publish ? '确认发布？' : '撤回发布？'),
        content: Text(
          publish
              ? '${row['title']}\n目标：${_platform(row['platform'])}\n${release && row['mandatory'] == true ? '此版本为强制更新，低版本用户更新后才能继续使用。' : '用户下次打开应用、返回前台或检查更新时，会收到弹窗。'}'
              : release
              ? '客户端下次成功检查时生效；已缓存强制更新的离线设备需联网后解除。'
              : '联网客户端下次检查时不再展示这条公告。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(publish ? '发布' : '撤回'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.api.change(
        'POST',
        '${release ? 'client-releases' : 'announcements'}/${row['id']}/publication',
        {'published': publish},
      );
      if (mounted) await _load();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = updateError(e);
        });
      }
    }
  }

  Future<void> _edit(bool release, [Map? row]) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ReleaseEditor(
        api: widget.api,
        release: release,
        row: row,
        defaultPlatform: widget.announcementsOnly ? 'android' : 'all',
      ),
    );
    if (mounted) await _load();
  }

  Widget _list(bool release) {
    final rows = release ? _releases : _notices;
    return ListView(
      padding: EdgeInsets.all(widget.announcementsOnly ? 16 : 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                release ? '客户端版本' : '发布公告',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            FilledButton.icon(
              onPressed: _busy ? null : () => _edit(release),
              icon: const Icon(Icons.add),
              label: Text(release ? '新建版本' : '新建公告'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          release
              ? '上传安装包 → 保存草稿 → 确认发布。强制更新按版本码判断，较新的非强制版本不会绕过先前的强制版本。'
              : '支持全部平台或指定平台。用户读过后不重复弹出；修改正文后需重新发布。',
        ),
        const SizedBox(height: 24),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(36),
            child: Center(child: Text('暂无内容，点击右上角创建')),
          ),
        for (final row in rows)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Chip(label: Text(_platform(row['platform']))),
                      Chip(label: Text(_published(row) ? '已发布' : '草稿')),
                      if (release)
                        Chip(
                          label: Text(
                            row['mandatory'] == true ? '强制更新' : '可选更新',
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    row['title'] as String,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (release)
                    Text(
                      'v${row['version']} · 版本码 ${row['build']} · ${(row['size'] / 1048576).toStringAsFixed(1)} MB',
                    ),
                  const SizedBox(height: 10),
                  SelectableText((row[release ? 'notes' : 'body']) as String),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => _edit(release, row as Map),
                        child: const Text('编辑'),
                      ),
                      FilledButton.tonal(
                        onPressed: _busy
                            ? null
                            : () => _publish(row as Map, release),
                        child: Text(_published(row) ? '撤回' : '发布'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.announcementsOnly ? '公告管理' : '版本与公告'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: widget.announcementsOnly
            ? null
            : const TabBar(
                tabs: [
                  Tab(text: '版本更新'),
                  Tab(text: '发布公告'),
                ],
              ),
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
          Expanded(
            child: widget.announcementsOnly
                ? _list(false)
                : TabBarView(children: [_list(true), _list(false)]),
          ),
        ],
      ),
    ),
  );
}

class _ReleaseEditor extends StatefulWidget {
  const _ReleaseEditor({
    required this.api,
    required this.release,
    this.row,
    this.defaultPlatform = 'all',
  });
  final AdminApi api;
  final bool release;
  final Map? row;
  final String defaultPlatform;
  @override
  State<_ReleaseEditor> createState() => _ReleaseEditorState();
}

class _ReleaseEditorState extends State<_ReleaseEditor> {
  late final _title = TextEditingController(
    text: widget.row?['title'] as String? ?? '',
  );
  late final _body = TextEditingController(
    text: widget.row?[widget.release ? 'notes' : 'body'] as String? ?? '',
  );
  final _version = TextEditingController(), _build = TextEditingController();
  late String _platform =
      widget.row?['platform'] as String? ??
      (widget.release ? 'android' : widget.defaultPlatform);
  late bool _mandatory = widget.row?['mandatory'] == true;
  bool _busy = false;
  String? _path, _packageId, _error;
  double? _progress;
  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _version.dispose();
    _build.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: [_platform == 'android' ? 'apk' : 'zip'],
    );
    if (files.isNotEmpty && mounted) {
      setState(() {
        _path = files.single.path;
        _packageId = null;
      });
    }
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty || _body.text.trim().isEmpty) {
      setState(() => _error = '请填写标题和正文');
      return;
    }
    if (widget.release &&
        widget.row == null &&
        (_path == null ||
            !RegExp(r'^\d{1,4}\.\d{1,4}\.\d{1,4}$')
                .hasMatch(_version.text.trim()) ||
            (int.tryParse(_build.text) ?? 0) < 1)) {
      setState(() => _error = '请选择安装包，并填写版本名称（如 0.9.0）和正整数版本码');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.release && widget.row == null && _packageId == null) {
        final file = File(_path!);
        final size = await file.length();
        if (size < 1 || size > 128 * 1024 * 1024) {
          throw StateError('安装包不能超过 128 MB');
        }
        final response = await widget.api.dio.post<dynamic>(
          'v1/admin/client-packages',
          queryParameters: {'platform': _platform},
          data: file.openRead(),
          options: Options(
            contentType: 'application/octet-stream',
            headers: {Headers.contentLengthHeader: size},
            sendTimeout: const Duration(minutes: 10),
            receiveTimeout: const Duration(minutes: 2),
          ),
          onSendProgress: (done, total) {
            if (mounted) setState(() => _progress = done / size);
          },
        );
        _packageId = response.data['id'] as String;
      }
      final body = <String, dynamic>{
        'title': _title.text.trim(),
        if (widget.release) ...{
          'notes': _body.text.trim(),
          'mandatory': _mandatory,
        } else ...{
          'platform': _platform,
          'body': _body.text.trim(),
        },
      };
      if (widget.release && widget.row == null) {
        body.addAll({
          'platform': _platform,
          'version': _version.text.trim(),
          'build': int.parse(_build.text),
          'packageId': _packageId,
        });
      }
      await widget.api.change(
        widget.row == null ? 'POST' : 'PATCH',
        '${widget.release ? 'client-releases' : 'announcements'}${widget.row == null ? '' : '/${widget.row!['id']}'}',
        body,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = updateError(e);
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(
        '${widget.row == null ? '新建' : '编辑'}${widget.release ? '版本' : '公告'}',
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.row == null || !widget.release)
                DropdownButtonFormField<String>(
                  initialValue: _platform,
                  decoration: const InputDecoration(labelText: '目标平台'),
                  items: [
                    if (!widget.release)
                      const DropdownMenuItem(value: 'all', child: Text('全部平台')),
                    const DropdownMenuItem(
                      value: 'android',
                      child: Text('Android'),
                    ),
                    const DropdownMenuItem(
                      value: 'windows',
                      child: Text('Windows'),
                    ),
                  ],
                  onChanged: _busy
                      ? null
                      : (v) => setState(() {
                          _platform = v!;
                          _path = null;
                          _packageId = null;
                        }),
                ),
              if (widget.release && widget.row == null) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _version,
                        enabled: !_busy,
                        decoration: const InputDecoration(
                          labelText: '版本名称，如 0.9.0',
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _build,
                        enabled: !_busy,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '版本码，如 17',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pick,
                  icon: const Icon(Icons.upload_file),
                  label: Text(
                    _path?.replaceAll('\\', '/').split('/').last ??
                        '选择完整 APK / Windows ZIP',
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _title,
                enabled: !_busy,
                maxLength: 100,
                decoration: const InputDecoration(labelText: '标题'),
              ),
              TextField(
                controller: _body,
                enabled: !_busy,
                minLines: 5,
                maxLines: 10,
                maxLength: 4000,
                decoration: InputDecoration(
                  labelText: widget.release ? '更新说明' : '公告正文',
                ),
              ),
              if (widget.release)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('强制更新'),
                  subtitle: const Text('开启后，低版本用户需要更新才能继续使用'),
                  value: _mandatory,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _mandatory = v),
                ),
              if (widget.row?['published'] == true ||
                  widget.row?['published'] == 1)
                Text(
                  widget.release
                      ? '此版本已发布，修改更新说明和强制模式将立即生效。'
                      : '修改后会转为草稿，需要重新发布。',
                ),
              if (_progress != null) LinearProgressIndicator(value: _progress),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (!widget.release)
          TextButton(
            onPressed: _busy
                ? null
                : () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(
                        _title.text.trim().isEmpty
                            ? '公告标题预览'
                            : _title.text.trim(),
                      ),
                      content: SingleChildScrollView(
                        child: Text(
                          _body.text.trim().isEmpty
                              ? '在这里展示公告正文。此预览不会发送给用户。'
                              : _body.text.trim(),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('关闭预览'),
                        ),
                      ],
                    ),
                  ),
            child: const Text('预览弹窗'),
          ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(
            _busy
                ? '正在保存…'
                : widget.row == null
                ? '保存草稿'
                : '保存修改',
          ),
        ),
      ],
    ),
  );
}
