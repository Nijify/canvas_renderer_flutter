// Path: lib/src/images/flutter_file_image_provider.dart
// Conditional file-backed ImageProvider bridge.

import 'package:canvas_renderer_flutter/src/images/flutter_file_image_provider_unsupported.dart'
    if (dart.library.io) 'package:canvas_renderer_flutter/src/images/flutter_file_image_provider_io.dart'
    as impl;
import 'package:flutter/widgets.dart';

/// Returns a platform file image provider.
///
/// File-backed image refs are IO-platform only. Web hosts should resolve
/// file/media refs to asset:, data:, blob:, or http(s): refs before calling
/// sourceToProvider.
ImageProvider<Object> fileImageProvider(String path) {
  return impl.fileImageProvider(path);
}
