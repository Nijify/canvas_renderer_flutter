// Path: lib/src/images/flutter_image_adapters.dart
// Flutter ImageProvider adapter utilities.
//
// These helpers are shared by FlutterImagePool and the optional public
// canvas_renderer_flutter_image_providers.dart barrel.

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:canvas_core/canvas_core_runtime.dart'
    show
        CanvasBlobUrlAssetRef,
        CanvasDataUriAssetRef,
        CanvasFileAssetRef,
        CanvasRawAssetRef,
        CanvasSchemeAssetRef,
        CanvasUrlAssetRef,
        parseCanvasAssetRef;
import 'package:canvas_renderer_flutter/src/images/flutter_file_image_provider.dart'
    show fileImageProvider;
import 'package:flutter/widgets.dart';

bool _looksLikeFlutterAssetPath(String source) {
  return source.startsWith('assets/') || source.startsWith('packages/');
}

/// Converts common canvas image refs into Flutter [ImageProvider]s.
///
/// App-specific refs such as `media:...` should be resolved by the host before
/// reaching this helper.
ImageProvider<Object> sourceToProvider(String source) {
  final ref = parseCanvasAssetRef(source);

  if (ref is CanvasUrlAssetRef || ref is CanvasBlobUrlAssetRef) {
    return NetworkImage(ref.raw);
  }

  if (ref is CanvasDataUriAssetRef) {
    final data = Uri.parse(ref.raw).data;
    final bytes = data?.contentAsBytes() ?? const <int>[];
    return MemoryImage(Uint8List.fromList(bytes));
  }

  if (ref is CanvasSchemeAssetRef && ref.scheme == 'asset') {
    return AssetImage(ref.payload);
  }

  if (ref is CanvasFileAssetRef) {
    return fileImageProvider(ref.path);
  }

  if (ref is CanvasRawAssetRef && _looksLikeFlutterAssetPath(ref.raw)) {
    return AssetImage(ref.raw);
  }

  // Unknown raw refs are treated as local file paths only on IO platforms.
  // Web hosts should resolve opaque refs before calling sourceToProvider.
  return fileImageProvider(ref.raw);
}

ImageProvider<Object> withSize(
  ImageProvider<Object> base, {
  int? width,
  int? height,
}) {
  if (width == null && height == null) return base;

  // IMPORTANT: never pass both; it can distort aspect ratio across platforms.
  if (width != null && height != null) {
    final side = math.max(width, height);
    return ResizeImage(base, width: side);
  }

  return ResizeImage(base, width: width, height: height);
}

Future<ui.Image?> toUiImage(ImageProvider<Object> provider) {
  final c = Completer<ui.Image?>();
  final stream = provider.resolve(const ImageConfiguration());
  late final ImageStreamListener l;
  l = ImageStreamListener(
    (ImageInfo info, _) {
      c.complete(info.image);
      stream.removeListener(l);
    },
    onError: (error, stack) {
      debugPrint('toUiImage error: $error\n$stack');
      c.complete(null);
      stream.removeListener(l);
    },
  );
  stream.addListener(l);
  return c.future;
}
