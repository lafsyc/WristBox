import 'package:oronbox/src/device/core/xiaomi_wearable_catalog.dart';
import 'package:oronbox/src/features/resources/domain/creator_workspace.dart';

class CreatorBandBbsTarget {
  const CreatorBandBbsTarget({
    required this.categoryId,
    required this.categoryName,
    required this.prefixId,
    required this.packageId,
    required this.packageName,
    required this.deviceNames,
  });

  final int categoryId;
  final String categoryName;
  final int prefixId;
  final String packageId;
  final String packageName;
  final List<String> deviceNames;

  Map<String, Object?> toJson() => {
    'category_id': categoryId,
    'prefix_id': prefixId,
    'package_id': packageId,
  };
}

class CreatorPublicationPlan {
  const CreatorPublicationPlan({
    required this.deviceNames,
    required this.astroBoxDeviceIds,
    this.bandBbsTargets = const [],
    this.bandBbsProblem,
    this.unmappedDeviceNames = const [],
  });

  final List<String> deviceNames;
  final List<String> astroBoxDeviceIds;
  final List<CreatorBandBbsTarget> bandBbsTargets;
  final CreatorBandBbsPlanProblem? bandBbsProblem;
  final List<String> unmappedDeviceNames;

  bool get canPublishToBandBbs =>
      bandBbsTargets.isNotEmpty && bandBbsProblem == null;
}

enum CreatorBandBbsPlanProblem {
  noDevices,
  unmappedDevices,
  sharedCategoryArtifacts,
}

CreatorPublicationPlan buildCreatorPublicationPlan({
  required CreatorWorkspace workspace,
  required List<CreatorDevice> devices,
  required List<Map<String, Object?>> bandBbsCategories,
}) {
  final categories = _flattenCategories(bandBbsCategories);
  final deviceById = {for (final device in devices) device.id: device};
  final boundDeviceNames = <String>[];
  final unresolved = <String>[];
  final groups =
      <
        ({int id, String title}),
        ({CreatorArtifact artifact, List<String> deviceNames})
      >{};
  var sharedCategory = false;

  for (final artifact in workspace.artifacts) {
    for (final deviceId in artifact.devices) {
      final device = deviceById[deviceId];
      if (device == null) continue;
      boundDeviceNames.add(device.name);
      final codename = normalizeXiaomiWearableCodename(device.codename);
      final exact = categories.where(
        (category) =>
            xiaomiWearableCodenamesForTitle(category.title).contains(codename),
      );
      final matches = exact.isNotEmpty
          ? exact
          : categories.where(
              (category) =>
                  xiaomiWearableTitleCoversVariant(category.title, codename),
            );
      if (matches.isEmpty) {
        unresolved.add(device.name);
        continue;
      }
      final category = matches.first;
      final group = groups[category];
      if (group == null) {
        groups[category] = (artifact: artifact, deviceNames: [device.name]);
      } else if (group.artifact.id != artifact.id) {
        sharedCategory = true;
      } else {
        group.deviceNames.add(device.name);
      }
    }
  }

  CreatorBandBbsPlanProblem? problem;
  if (boundDeviceNames.isEmpty) {
    problem = CreatorBandBbsPlanProblem.noDevices;
  } else if (unresolved.isNotEmpty) {
    problem = CreatorBandBbsPlanProblem.unmappedDevices;
  } else if (sharedCategory) {
    problem = CreatorBandBbsPlanProblem.sharedCategoryArtifacts;
  }
  final prefixId = workspace.resource.kind == CreatorResourceKind.watchface
      ? 81
      : 82;
  return CreatorPublicationPlan(
    deviceNames: boundDeviceNames,
    astroBoxDeviceIds: [
      for (final artifact in workspace.artifacts)
        for (final deviceId in artifact.devices)
          if ((deviceById[deviceId]?.astroBoxId ?? '').isNotEmpty)
            deviceById[deviceId]!.astroBoxId,
    ],
    bandBbsTargets: problem == null
        ? [
            for (final entry in groups.entries)
              CreatorBandBbsTarget(
                categoryId: entry.key.id,
                categoryName: entry.key.title,
                prefixId: prefixId,
                packageId: entry.value.artifact.packageId,
                packageName: entry.value.artifact.name,
                deviceNames: entry.value.deviceNames,
              ),
          ]
        : const [],
    bandBbsProblem: problem,
    unmappedDeviceNames: unresolved,
  );
}

List<({int id, String title})> _flattenCategories(
  List<Map<String, Object?>> roots,
) {
  final result = <({int id, String title})>[];
  void visit(Map<String, Object?> node) {
    final id = (node['id'] as num?)?.toInt() ?? 0;
    final title = node['title']?.toString().trim() ?? '';
    final children = (node['children'] as List? ?? const []);
    if (id > 0 && title.isNotEmpty && children.isEmpty) {
      result.add((id: id, title: title));
    }
    for (final child in children) {
      if (child is Map) visit(child.cast<String, Object?>());
    }
  }

  for (final root in roots) {
    visit(root);
  }
  return result;
}
