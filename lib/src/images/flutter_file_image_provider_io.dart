// Path: lib/src/images/flutter_file_image_provider_io.dart
// IO-platform file-backed ImageProvider implementation.

import 'dart:io' show File;

import 'package:flutter/widgets.dart';

ImageProvider<Object> fileImageProvider(String path) {
  return FileImage(File(path));
}
