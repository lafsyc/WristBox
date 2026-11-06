import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LocalPackageFile {
  const LocalPackageFile({
    required this.id,
    required this.name,
    required this.directory,
    required this.size,
    required this.modified,
  });
  factory LocalPackageFile.fromMap(Map<dynamic, dynamic> value) =>
      LocalPackageFile(
        id: value['id'] as String,
        name: value['name'] as String,
        directory: value['directory'] as String? ?? '',
        size: (value['size'] as num? ?? 0).toInt(),
        modified: (value['modified'] as num? ?? 0).toInt(),
      );
  final String id, name, directory;
  final int size, modified;
  String get extension => name.split('.').last.toLowerCase();
}

enum LocalFileSort { recent, name, size }

List<LocalPackageFile> filterLocalFiles(
  List<LocalPackageFile> files, {
  String query = '',
  String extension = '',
  int days = 0,
  LocalFileSort sort = LocalFileSort.recent,
  DateTime? now,
}) {
  final cutoff = (now ?? DateTime.now())
      .subtract(Duration(days: days))
      .millisecondsSinceEpoch;
  final needle = query.trim().toLowerCase();
  final result = files
      .where(
        (file) =>
            (extension.isEmpty || file.extension == extension) &&
            (days == 0 || file.modified >= cutoff) &&
            '${file.name} ${file.directory}'.toLowerCase().contains(needle),
      )
      .toList();
  result.sort((a, b) {
    final primary = switch (sort) {
      LocalFileSort.recent => b.modified.compareTo(a.modified),
      LocalFileSort.name => a.name.toLowerCase().compareTo(
        b.name.toLowerCase(),
      ),
      LocalFileSort.size => b.size.compareTo(a.size),
    };
    return primary != 0 ? primary : a.id.compareTo(b.id);
  });
  return result;
}

class LocalFileService {
  static const channel = MethodChannel('wristbox/local_files');
  static Future<Map<dynamic, dynamic>> scan({bool foldersOnly = false}) async =>
      await channel.invokeMapMethod<dynamic, dynamic>('scan', {
        'foldersOnly': foldersOnly,
      }) ??
      {};
  static Future<String> prepare(String id) async =>
      (await channel.invokeMethod<String>('prepare', {'id': id}))!;
}

class LocalFilesPane extends StatefulWidget {
  const LocalFilesPane({
    super.key,
    required this.onInstall,
    required this.onPick,
    required this.bottomInset,
  });
  final Future<void> Function(LocalPackageFile) onInstall;
  final VoidCallback onPick;
  final double bottomInset;
  @override
  State<LocalFilesPane> createState() => _LocalFilesPaneState();
}

class _LocalFilesPaneState extends State<LocalFilesPane>
    with WidgetsBindingObserver {
  List<LocalPackageFile> _files = [];
  String _query = '', _extension = '';
  int _days = 0, _folders = 0;
  LocalFileSort _sort = LocalFileSort.recent;
  bool _loading = false,
      _allFiles = false,
      _canAllFiles = false,
      _limited = false;
  int _inaccessible = 0;
  bool _foldersOnly = false;
  String? _error, _preparing;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scan();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        mounted &&
        TickerMode.valuesOf(context).enabled) {
      _scan();
    }
  }

  String _errorText(Object error) =>
      error is PlatformException &&
          RegExp(r'[\u4e00-\u9fff]').hasMatch(error.message ?? '')
      ? error.message!
      : '无法读取本地文件，请检查文件访问权限后重试';
  Future<void> _scan() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await LocalFileService.scan(foldersOnly: _foldersOnly);
      if (!mounted) return;
      setState(() {
        _files = [
          for (final item in result['files'] as List? ?? [])
            LocalPackageFile.fromMap(item as Map),
        ];
        _allFiles = result['allFiles'] == true;
        _canAllFiles = result['canAllFiles'] == true;
        _folders = (result['folders'] as num? ?? 0).toInt();
        _limited = result['limited'] == true;
        _inaccessible = (result['inaccessible'] as num? ?? 0).toInt();
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _files = [];
          _error = _errorText(error);
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _access(String method) async {
    try {
      final result = await LocalFileService.channel.invokeMethod<Object?>(
        method,
      );
      if (!mounted) return;
      if (method == 'addFolder' && result == true) _foldersOnly = true;
      if (method == 'grantAllFiles') _foldersOnly = false;
      if (mounted && method != 'grantAllFiles') await _scan();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_errorText(error))));
      }
    }
  }

  Future<void> _install(LocalPackageFile file) async {
    setState(() => _preparing = file.id);
    try {
      await widget.onInstall(file);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_errorText(error))));
      }
    } finally {
      if (mounted) setState(() => _preparing = null);
    }
  }

  String _size(int value) => value >= 1048576
      ? '${(value / 1048576).toStringAsFixed(1)} MB'
      : '${(value / 1024).ceil()} KB';
  String _date(int value) {
    if (value == 0) return '时间未知';
    final d = DateTime.fromMillisecondsSinceEpoch(value);
    return '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final files = filterLocalFiles(
      _files,
      query: _query,
      extension: _extension,
      days: _days,
      sort: _sort,
    );
    final access = (!_foldersOnly && _allFiles) || _folders > 0;
    return RefreshIndicator(
      onRefresh: _scan,
      child: CustomScrollView(
        key: const PageStorageKey('local-files'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList.list(
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '本地安装包',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '刷新本地文件',
                      onPressed: _loading ? null : _scan,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                    PopupMenuButton<String>(
                      tooltip: '文件来源',
                      onSelected: (value) {
                        if (value == 'pick') {
                          widget.onPick();
                        } else if (value == 'foldersOnly' || value == 'phone') {
                          setState(() => _foldersOnly = value == 'foldersOnly');
                          _scan();
                        } else {
                          _access(value);
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'pick',
                          child: Text('系统选择文件'),
                        ),
                        const PopupMenuItem(
                          value: 'addFolder',
                          child: Text('添加扫描文件夹'),
                        ),
                        if (_canAllFiles)
                          const PopupMenuItem(
                            value: 'grantAllFiles',
                            child: Text('手机文件访问设置'),
                          ),
                        if (_folders > 0)
                          const PopupMenuItem(
                            value: 'forgetFolders',
                            child: Text('清除文件夹授权'),
                          ),
                        if (_allFiles)
                          const PopupMenuItem(
                            value: 'phone',
                            child: Text('扫描手机共享存储'),
                          ),
                        if (_folders > 0)
                          const PopupMenuItem(
                            value: 'foldersOnly',
                            child: Text('仅扫描已授权文件夹'),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    hintText: '搜索文件名或文件夹',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final entry in {
                      '': '全部格式',
                      'rpk': 'RPK',
                      'bin': 'BIN',
                    }.entries)
                      ChoiceChip(
                        label: Text(entry.value),
                        selected: _extension == entry.key,
                        onSelected: (_) =>
                            setState(() => _extension = entry.key),
                      ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final entry in {
                      0: '全部时间',
                      7: '最近 7 天',
                      30: '最近 30 天',
                    }.entries)
                      ChoiceChip(
                        label: Text(entry.value),
                        selected: _days == entry.key,
                        onSelected: (_) => setState(() => _days = entry.key),
                      ),
                  ],
                ),
                if (!access && !_loading)
                  Container(
                    margin: const EdgeInsets.only(top: 16),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '查找手机中的安装包',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '授权后可查找下载目录等位置的 RPK、BIN 文件。只在本机读取文件列表，不会上传。也可以只添加指定文件夹。',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.6,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (_canAllFiles)
                          FilledButton.icon(
                            onPressed: () => _access('grantAllFiles'),
                            icon: const Icon(Icons.folder_open_rounded),
                            label: const Text('开启手机文件访问'),
                          ),
                        TextButton(
                          onPressed: () => _access('addFolder'),
                          child: const Text('添加文件夹'),
                        ),
                        TextButton(
                          onPressed: widget.onPick,
                          child: const Text('系统选择文件'),
                        ),
                      ],
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Text(_error!, style: TextStyle(color: colors.error)),
                  ),
                if (_limited || _inaccessible > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _limited
                          ? '本次扫描达到数量或时间上限，请指定较小的文件夹查找。'
                          : '部分目录无法访问，可通过系统选择文件或重新授权文件夹。',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: LinearProgressIndicator(),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '找到 ${files.length} 个文件',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    PopupMenuButton<LocalFileSort>(
                      tooltip: '文件排序',
                      initialValue: _sort,
                      onSelected: (value) => setState(() => _sort = value),
                      itemBuilder: (_) => [
                        for (final value in LocalFileSort.values)
                          PopupMenuItem(
                            value: value,
                            child: Text(switch (value) {
                              LocalFileSort.recent => '最新优先',
                              LocalFileSort.name => '按名称',
                              LocalFileSort.size => '大文件优先',
                            }),
                          ),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          switch (_sort) {
                            LocalFileSort.recent => '最新优先 ↓',
                            LocalFileSort.name => '按名称 ↓',
                            LocalFileSort.size => '按大小 ↓',
                          },
                          style: TextStyle(fontSize: 12, color: colors.primary),
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  '时间按文件最后修改时间排列，BIN 类型以内容识别为准。',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                if (access && !_loading && files.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Text('没有找到匹配文件，可调整筛选或添加文件夹。'),
                  ),
              ],
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList.builder(
              itemCount: files.length,
              itemBuilder: (context, index) {
                final file = files[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(18),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      leading: Icon(
                        file.extension == 'rpk'
                            ? Icons.widgets_outlined
                            : Icons.description_outlined,
                        color: colors.primary,
                      ),
                      title: Text(
                        file.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '${_size(file.size)} · ${_date(file.modified)}\n${file.directory}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, height: 1.6),
                      ),
                      trailing: _preparing == file.id
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download_rounded, size: 20),
                      onTap: _preparing == null ? () => _install(file) : null,
                    ),
                  ),
                );
              },
            ),
          ),
          SliverToBoxAdapter(child: SizedBox(height: 24 + widget.bottomInset)),
        ],
      ),
    );
  }
}
