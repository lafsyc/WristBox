import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oronbox/src/core/constants/oronbox_server.dart';
import 'package:oronbox/src/core/network/app_http_transport.dart';

class OronBoxResourceAttribute {
  const OronBoxResourceAttribute({
    required this.id,
    required this.nameZh,
    required this.nameEn,
    required this.coefficient,
  });

  final String id;
  final String nameZh;
  final String nameEn;
  final double coefficient;

  String labelFor(Locale locale) {
    if (locale.languageCode == 'zh' || nameEn.trim().isEmpty) return nameZh;
    return nameEn;
  }

  factory OronBoxResourceAttribute.fromJson(Map<String, Object?> json) =>
      OronBoxResourceAttribute(
        id: json['id']?.toString() ?? '',
        nameZh: json['name_zh']?.toString() ?? '',
        nameEn: json['name_en']?.toString() ?? '',
        coefficient: (json['coefficient'] as num?)?.toDouble() ?? 1,
      );
}

class OronBoxResourceAttributeCatalog {
  OronBoxResourceAttributeCatalog({Dio? dio})
    : _dio =
          dio ??
          createAppHttpTransport(
            options: BaseOptions(baseUrl: oronBoxServerBaseUrl),
          );

  final Dio _dio;

  Future<List<OronBoxResourceAttribute>> load() async {
    final response = await _dio.get<Object?>('/api/resource-attributes');
    final root = (response.data as Map?)?.cast<String, Object?>() ?? const {};
    return (root['attributes'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) =>
              OronBoxResourceAttribute.fromJson(item.cast<String, Object?>()),
        )
        .where((item) => item.id.isNotEmpty && item.nameZh.isNotEmpty)
        .toList(growable: false);
  }
}

final oronBoxResourceAttributesProvider =
    FutureProvider.autoDispose<List<OronBoxResourceAttribute>>(
      (ref) => OronBoxResourceAttributeCatalog().load(),
    );
