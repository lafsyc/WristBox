import 'package:shared_preferences/shared_preferences.dart';
import 'package:oronbox/src/core/services/shared_prefs_service.dart';
import 'package:oronbox/steadylink/privacy_gate.dart';
import 'package:oronbox/steadylink/legal_documents.dart';

Future<void> acceptTestConsent() async {
  SharedPreferences.setMockInitialValues({});
  await SharedPrefsService.instance.init();
  await SharedPrefsService.instance.setString(consentPreference, legalVersion);
}

Future<void> noRuntime() async {}
