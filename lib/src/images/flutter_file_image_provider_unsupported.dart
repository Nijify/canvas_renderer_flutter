// Path: lib/src/images/flutter_file_image_provider_unsupported.dart
// Web/default file-backed ImageProvider implementation.

import 'package:flutter/widgets.dart';

ImageProvider<Object> fileImageProvider(String path) {
  throw UnsupportedError(
    'file: image sources and raw local file paths are not supported on this '
    'platform. Resolve file/media refs to asset:, data:, blob:, or http(s): '
    'refs before calling sourceToProvider. Ref: $path',
  );
}
