import 'package:flutter/foundation.dart';

/// Native file pickers return a cache path. Asking them to also return bytes
/// copies the complete file through MethodChannel and can exhaust Android's
/// application heap for firmware images.
bool get shouldLoadPickedFileData => kIsWeb;
