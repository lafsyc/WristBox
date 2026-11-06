import 'package:oronbox/src/app/generated/app_localizations.dart';

String blogTypeLabel(AppLocalizations l10n, String type) => switch (type) {
  'recommendation' => l10n.blogTypeRecommendation,
  'docs' => l10n.blogTypeDocs,
  _ => l10n.blogTypeAnnouncement,
};
