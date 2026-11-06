import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oronbox/src/core/network/app_http_transport.dart';
import 'package:oronbox/src/core/providers/app_settings_providers.dart';
import 'package:oronbox/src/features/accounts/services/bandbbs_auth_service.dart';
import 'package:oronbox/src/features/plugins/application/abv1_plugin_store.dart';
import 'package:oronbox/src/features/plugins/application/oronbox_plugin_repository.dart';
import 'package:oronbox/src/features/plugins/application/plugin_manager.dart';
import 'package:oronbox/src/features/plugins/application/plugin_repository.dart';
import 'package:oronbox/src/features/plugins/domain/plugin_package.dart';

/// daemon 侧的插件分发入口：持有全部插件源，统一目录浏览、
/// 下载安装与发布，UI 只通过命令总线访问。
class PluginRepositories {
  PluginRepositories({required this.manager, required this.container});

  final PluginManager manager;
  final ProviderContainer container;

  late final Map<String, PluginRepository> _repositories = {
    'oronbox': OronBoxPluginRepository(
      accessToken: () =>
          container.read(bandBbsAuthProvider).session?.accessToken,
    ),
    'abv1': AbV1PluginRepository(
      createAppHttpTransport(),
      readCdn: () => container.read(appSettingsProvider).effectiveCdn,
    ),
  };

  List<Map<String, Object?>> sources() => _repositories.values
      .map(
        (repository) => {
          'id': repository.id,
          'name': repository.displayName,
          'legacy': repository.isLegacy,
        },
      )
      .toList(growable: false);

  Future<List<Map<String, Object?>>> catalog(
    String source, {
    bool force = false,
  }) async {
    final repository = _requireRepository(source);
    final entries = await repository.load(force: force);
    final installed = <String, String>{
      for (final plugin in await manager.list(includeIcons: false))
        plugin['id'].toString(): plugin['version'].toString(),
    };
    return entries
        .map((entry) {
          final installedVersion = installed[entry.installedId];
          final updateAvailable =
              !entry.isLegacy &&
              installedVersion != null &&
              comparePluginVersions(entry.version, installedVersion) > 0;
          return {
            ...entry.toJson(),
            'installed': installedVersion != null && !updateAvailable,
            if (installedVersion != null) 'installedVersion': installedVersion,
            'updateAvailable': updateAvailable,
          };
        })
        .toList(growable: false);
  }

  Future<Map<String, Object?>> install(String source, String id) async {
    final repository = _requireRepository(source);
    final entry = await _findEntry(repository, id);
    final bytes = await repository.download(entry);
    return manager.install(bytes, includeIcon: false);
  }

  Future<Map<String, Object?>> upload(String source, Uint8List bytes) async {
    final repository = _requireRepository(source);
    if (repository is! OronBoxPluginRepository) {
      throw StateError('Repository does not support publishing: $source');
    }
    const PluginPackageReader().read(bytes);
    final result = await _publisher().upload(bytes);
    await repository.load(force: true);
    return result;
  }

  Future<void> remove(String source, String id) async {
    final repository = _requireRepository(source);
    if (repository is! OronBoxPluginRepository) {
      throw StateError('Repository does not support publishing: $source');
    }
    await _publisher().remove(id);
    await repository.load(force: true);
  }

  OronBoxPluginPublisher _publisher() => OronBoxPluginPublisher(
    sessions: container.read(bandBbsAuthProvider.notifier),
  );

  Future<PluginCatalogEntry> _findEntry(
    PluginRepository repository,
    String id,
  ) async {
    final entries = await repository.load();
    for (final entry in entries) {
      if (entry.id == id) return entry;
    }
    throw StateError('Plugin not found in ${repository.id} repository: $id');
  }

  PluginRepository _requireRepository(String source) {
    final repository = _repositories[source];
    if (repository == null) {
      throw StateError('Unknown plugin repository: $source');
    }
    return repository;
  }
}
