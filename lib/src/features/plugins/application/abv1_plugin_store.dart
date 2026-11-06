import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:oronbox/src/core/network/github_cdn.dart';
import 'package:oronbox/src/features/plugins/application/plugin_repository.dart';
import 'package:oronbox/src/features/plugins/domain/plugin_package.dart';

const abV1PluginStoreIndexUrl =
    'https://raw.githubusercontent.com/AstralSightStudios/'
    'AstroBox-Plugin-Repo/refs/heads/main/index.txt';

class StorePlugin {
  const StorePlugin({
    required this.repositoryUrl,
    required this.folder,
    required this.name,
    required this.icon,
    required this.version,
    required this.description,
    required this.author,
    required this.website,
    required this.entry,
    required this.apiLevel,
    required this.permissions,
    required this.additionalFiles,
  });

  final Uri repositoryUrl;
  final String folder;
  final String name;
  final String icon;
  final String version;
  final String description;
  final String author;
  final String website;
  final String entry;
  final int apiLevel;
  final List<String> permissions;
  final List<String> additionalFiles;

  Uri fileUrl(String path) => repositoryUrl.resolve('$folder/$path');
  Uri get iconUrl => fileUrl(icon);
}

/// AstroBox v1 遗产插件源。
///
/// 该仓库已停止维护，仅保留只读的目录浏览与安装能力，
/// 不做任何版本更新检测。
class AbV1PluginRepository implements PluginRepository {
  AbV1PluginRepository(this._dio, {GitHubCdn Function()? readCdn})
    : _readCdn = readCdn ?? (() => GitHubCdn.raw);

  final Dio _dio;
  final GitHubCdn Function() _readCdn;

  List<StorePlugin>? _cache;
  final _byEntryId = <String, StorePlugin>{};

  @override
  String get id => 'abv1';

  @override
  String get displayName => 'AstroBox';

  @override
  bool get isLegacy => true;

  @override
  Future<List<PluginCatalogEntry>> load({bool force = false}) async {
    if (!force && _cache != null) return _entries(_cache!);
    final storePlugins = await _loadStorePlugins();
    _cache = storePlugins;
    _byEntryId
      ..clear()
      ..addEntries(
        storePlugins.map((plugin) => MapEntry(entryId(plugin), plugin)),
      );
    return _entries(storePlugins);
  }

  @override
  Future<Uint8List> download(PluginCatalogEntry entry) async {
    final plugin = await _findPlugin(entry.id);
    final files = <String>{
      'manifest.json',
      plugin.entry,
      plugin.icon,
      ...plugin.additionalFiles,
    };
    final archive = Archive();
    for (final path in files) {
      final bytes = await _getBytes(_cdnUri(plugin.fileUrl(path)));
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  Future<StorePlugin> _findPlugin(String id) async {
    await load();
    final plugin = _byEntryId[id];
    if (plugin == null) {
      throw StateError('Plugin not found in ABv1 repository: $id');
    }
    return plugin;
  }

  List<PluginCatalogEntry> _entries(List<StorePlugin> plugins) => plugins
      .map(
        (plugin) => PluginCatalogEntry(
          source: id,
          id: entryId(plugin),
          installedId: PluginPackageReader.legacyPluginId(plugin.name),
          name: plugin.name,
          version: plugin.version,
          author: plugin.author,
          description: plugin.description,
          permissions: plugin.permissions,
          iconUrl: _cdnUri(plugin.iconUrl).toString(),
          isLegacy: true,
        ),
      )
      .toList(growable: false);

  static String entryId(StorePlugin plugin) =>
      '${plugin.repositoryUrl}|${plugin.folder}';

  Uri _cdnUri(Uri uri) => rewriteGithubCdnUri(uri, _readCdn());

  Future<List<StorePlugin>> _loadStorePlugins() async {
    final repositories = _lines(
      await _getText(_cdnUri(Uri.parse(abV1PluginStoreIndexUrl))),
    );
    final entries = (await Future.wait(
      repositories.map((repository) async {
        final repositoryUrl = _directoryUri(repository);
        final folders = _lines(
          await _getText(_cdnUri(repositoryUrl.resolve('index.txt'))),
        );
        return folders
            .map((folder) => (repositoryUrl: repositoryUrl, folder: folder))
            .toList(growable: false);
      }),
    )).expand((entries) => entries).toList(growable: false);
    final plugins = await Future.wait(
      entries.map((entry) async {
        final repositoryUrl = entry.repositoryUrl;
        final folder = entry.folder;
        final manifestUri = _cdnUri(
          repositoryUrl.resolve('$folder/manifest.json'),
        );
        final response = await _dio.getUri<Object?>(manifestUri);
        final raw = response.data is String
            ? jsonDecode(response.data! as String)
            : response.data;
        if (raw is! Map) {
          throw FormatException('Invalid plugin manifest: $manifestUri');
        }
        return _parse(repositoryUrl, folder, raw.cast<String, Object?>());
      }),
    );
    plugins.sort((a, b) => a.name.compareTo(b.name));
    return List.unmodifiable(plugins);
  }

  StorePlugin _parse(
    Uri repositoryUrl,
    String folder,
    Map<String, Object?> json,
  ) {
    String requiredString(String key) {
      final value = json[key]?.toString().trim() ?? '';
      if (value.isEmpty) throw FormatException('Plugin $key is missing');
      return value;
    }

    List<String> strings(String key) =>
        (json[key] as List?)?.map((value) => value.toString()).toList() ??
        const [];

    return StorePlugin(
      repositoryUrl: repositoryUrl,
      folder: folder,
      name: requiredString('name'),
      icon: requiredString('icon'),
      version: requiredString('version'),
      description: json['description']?.toString() ?? '',
      author: json['author']?.toString() ?? '',
      website: json['website']?.toString() ?? '',
      entry: requiredString('entry'),
      apiLevel: (json['api_level'] as num?)?.toInt() ?? 0,
      permissions: strings('permissions'),
      additionalFiles: strings('additional_files'),
    );
  }

  Future<String> _getText(Uri uri) async {
    final response = await _dio.getUri<String>(
      uri,
      options: Options(responseType: ResponseType.plain),
    );
    return response.data ?? '';
  }

  Future<Uint8List> _getBytes(Uri uri) async {
    final response = await _dio.getUri<List<int>>(
      uri,
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data ?? const []);
  }

  List<String> _lines(String value) => value
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('#'))
      .toList(growable: false);

  Uri _directoryUri(String value) {
    final uri = Uri.parse(value);
    return uri.path.endsWith('/') ? uri : uri.replace(path: '${uri.path}/');
  }
}
