import 'dart:typed_data';

/// 一个插件目录条目（跨源统一模型）。
///
/// [id] 只在所属仓库内唯一，安装/下载时必须同时携带 [source]。
class PluginCatalogEntry {
  const PluginCatalogEntry({
    required this.source,
    required this.id,
    required this.installedId,
    required this.name,
    required this.version,
    required this.author,
    required this.description,
    required this.permissions,
    this.iconUrl,
    this.uploaderId,
    this.uploaderName,
    this.owned = false,
    this.moderationState,
    this.moderationReason,
    this.isLegacy = false,
  });

  final String source;
  final String id;

  /// 安装后 manifest 里的插件 ID，用于与已安装列表比对。
  final String installedId;

  final String name;
  final String version;
  final String author;
  final String description;
  final List<String> permissions;

  /// 图标 URL，可能为空；UI 直接按 URL 加载，不经命令通道传输。
  final String? iconUrl;

  /// 上传者（仅 OronBox 源有）。与当前登录用户一致时提供更新/下架。
  final String? uploaderId;
  final String? uploaderName;

  /// 当前登录用户即上传者（服务端判断，未登录时恒为 false）。
  final bool owned;

  /// 审核状态（仅 OronBox 源且 [owned] 时有值）：
  /// pending/listed/rejected/delisted。
  final String? moderationState;

  /// 拒绝或下架原因（仅 [owned] 时有值）。
  final String? moderationReason;

  /// 遗产插件（如 ABv1）：不做更新检测，仅区分安装/已安装。
  final bool isLegacy;

  Map<String, Object?> toJson() => {
    'source': source,
    'id': id,
    'installedId': installedId,
    'name': name,
    'version': version,
    'author': author,
    'description': description,
    'permissions': permissions,
    if (iconUrl != null) 'iconUrl': iconUrl,
    if (uploaderId != null) 'uploaderId': uploaderId,
    if (uploaderName != null) 'uploaderName': uploaderName,
    if (owned) 'owned': true,
    if (moderationState != null) 'state': moderationState,
    if (moderationReason != null) 'moderationReason': moderationReason,
    'legacy': isLegacy,
  };
}

/// 插件分发源。
///
/// 一个仓库对应一个可枚举、可下载的插件目录。实现必须可独立
/// 加载目录与下载插件包，安装本身由 [PluginManager] 统一处理。
abstract interface class PluginRepository {
  /// 源标识，跨进程传输时使用（如 `abv1`、`oronbox`）。
  String get id;

  /// 展示名。
  String get displayName;

  /// 是否为遗产插件源。
  bool get isLegacy;

  /// 加载目录。调用方应缓存结果，[force] 为 true 时强制刷新。
  Future<List<PluginCatalogEntry>> load({bool force = false});

  /// 下载插件包字节（.obp / .abp）。
  Future<Uint8List> download(PluginCatalogEntry entry);
}

int comparePluginVersions(String left, String right) {
  final leftVersion = _PluginVersion.parse(left);
  final rightVersion = _PluginVersion.parse(right);
  return leftVersion.compareTo(rightVersion);
}

class _PluginVersion implements Comparable<_PluginVersion> {
  const _PluginVersion(this.core, this.preRelease);

  final List<int> core;
  final List<String> preRelease;

  factory _PluginVersion.parse(String value) {
    var normalized = value.trim().toLowerCase();
    if (normalized.startsWith('v')) normalized = normalized.substring(1);
    normalized = normalized.split('+').first;
    final parts = normalized.split('-');
    final core = parts.first
        .split('.')
        .map(
          (part) => int.tryParse(RegExp(r'^\d+').stringMatch(part) ?? '') ?? 0,
        )
        .toList(growable: true);
    while (core.length < 3) {
      core.add(0);
    }
    final preRelease = parts.length <= 1
        ? const <String>[]
        : parts.skip(1).join('-').split('.');
    return _PluginVersion(core, preRelease);
  }

  @override
  int compareTo(_PluginVersion other) {
    final length = core.length > other.core.length
        ? core.length
        : other.core.length;
    for (var index = 0; index < length; index++) {
      final comparison = (index < core.length ? core[index] : 0).compareTo(
        index < other.core.length ? other.core[index] : 0,
      );
      if (comparison != 0) return comparison;
    }
    if (preRelease.isEmpty != other.preRelease.isEmpty) {
      return preRelease.isEmpty ? 1 : -1;
    }
    for (
      var index = 0;
      index < preRelease.length && index < other.preRelease.length;
      index++
    ) {
      final left = preRelease[index];
      final right = other.preRelease[index];
      final leftNumber = int.tryParse(left);
      final rightNumber = int.tryParse(right);
      final comparison = leftNumber != null && rightNumber != null
          ? leftNumber.compareTo(rightNumber)
          : leftNumber != null
          ? -1
          : rightNumber != null
          ? 1
          : left.compareTo(right);
      if (comparison != 0) return comparison;
    }
    return preRelease.length.compareTo(other.preRelease.length);
  }
}
