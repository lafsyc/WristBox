import 'package:oronbox/src/features/plugins/domain/plugin_package.dart';
import 'package:oronbox/src/features/plugins/storage/plugin_storage.dart';
import 'plugin_runtime.dart';

// SteadyLink deliberately excludes plugin execution and its native runtimes.
PluginRuntime createPluginRuntime(PluginRuntimeType type, {required PluginStorage storage}) =>
    throw UnsupportedError('SteadyLink does not run plugins');
PluginRuntime createJavaScriptPluginRuntime() =>
    throw UnsupportedError('SteadyLink does not run app-side scripts');
