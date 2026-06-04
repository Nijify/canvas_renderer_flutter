// Path: lib/src/images/flutter_image_pool.dart

import 'dart:ui' as ui;

import 'package:canvas_core/canvas_core_runtime.dart';
import 'package:flutter/foundation.dart'
    show ValueNotifier, debugPrint, kDebugMode;
import 'package:flutter/widgets.dart' show ResizeImage;

import 'package:canvas_renderer_flutter/src/images/flutter_image_adapters.dart';
import 'package:canvas_renderer_flutter/src/images/flutter_image_intrinsics.dart';

typedef AssetUrlResolver = Future<String?> Function(String sourceRef);
typedef AssetUrlsResolver =
    Future<Map<String, String>> Function(List<String> sourceRefs);

/// Stable intrinsic metadata resolution (NO raster decode).
typedef AssetMetaResolver = Future<Size2D?> Function(String sourceRef);
typedef AssetMetasResolver =
    Future<Map<String, Size2D>> Function(List<String> sourceRefs);

void _dlog(String tag, Object msg) {
  if (!kDebugMode) return;
  debugPrint('[${DateTime.now().toIso8601String()}][$tag] $msg');
}

class _DecodeDims {
  const _DecodeDims(this.w, this.h);
  final int? w;
  final int? h;
}

/// Image pool that handles two independent responsibilities:
///
/// 1) Stable intrinsic metadata (layout-affecting in core; also used for crop math)
///    - resolveSceneIntrinsics() -> intrinsics.setIntrinsicSize()
///
/// 2) Raster decoding (paint-only)
///    - preloadScene() -> intrinsics.setImage() + revision bump
///
/// Important boundary:
/// - This renderer treats canvas image source refs as opaque strings.
/// - App-specific meanings such as `media:<id>` or `asset:<path>` belong to
///   the host-provided resolver callbacks.
class FlutterImagePool {
  FlutterImagePool({
    this.assetUrlResolver,
    this.assetUrlsResolver,
    this.assetMetaResolver,
    this.assetMetasResolver,
  });

  final Map<ElementId, ui.Image?> images = <ElementId, ui.Image?>{};

  final AssetUrlResolver? assetUrlResolver;
  final AssetUrlsResolver? assetUrlsResolver;

  final AssetMetaResolver? assetMetaResolver;
  final AssetMetasResolver? assetMetasResolver;

  // Cache: opaque canvas source ref -> resolved renderable source.
  final Map<String, String> _urlCache = <String, String>{};

  // Cache: opaque canvas source ref -> resolved intrinsic size.
  final Map<String, Size2D> _metaCache = <String, Size2D>{};

  // Cache: elementId -> load key (so we don't reload same thing unnecessarily).
  final Map<ElementId, String> _loadedKey = <ElementId, String>{};

  // In-flight key: elementId -> key of the most recent request.
  // Used to drop stale async completions (race-safe).
  final Map<ElementId, String> _inflightKey = <ElementId, String>{};

  /// Emits a new value whenever any image in [images] changes.
  /// Painters can listen to this to repaint without setState hacks.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  bool get _hasUrlResolver =>
      assetUrlResolver != null || assetUrlsResolver != null;

  void _bump() => revision.value++;

  /// Stable renderer-local key for cache maps.
  ///
  /// This deliberately does not parse schemes. `media:abc`, `asset:foo.png`,
  /// URLs, file refs, and future custom schemes are all opaque host refs here.
  String? _sourceKeyFromRaw(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  /// Preferred decode constraint is a single "max side" (keeps aspect consistent).
  /// When stable metadata is available, we decode with both width+height derived
  /// from that metadata to avoid platform-specific aspect drift.
  int? _decodeSide(int? w, int? h) {
    if (w == null && h == null) return null;
    if (w == null) return h;
    if (h == null) return w;
    return (w > h) ? w : h;
  }

  _DecodeDims _decodeDimsFromMeta(int? side, Size2D? meta) {
    if (side == null) return const _DecodeDims(null, null);
    if (meta == null || meta.w <= 0 || meta.h <= 0) {
      // Fallback: single-side decode.
      return _DecodeDims(side, null);
    }

    final maxSide = (meta.w > meta.h) ? meta.w : meta.h;
    final scale = side / maxSide;

    var w = (meta.w * scale).round();
    var h = (meta.h * scale).round();

    if (w < 1) w = 1;
    if (h < 1) h = 1;

    return _DecodeDims(w, h);
  }

  Future<void> _primeUrlCache(Set<String> sourceRefs) async {
    if (sourceRefs.isEmpty) return;
    if (!_hasUrlResolver) return;

    final missing = <String>[
      for (final ref in sourceRefs)
        if (!_urlCache.containsKey(ref)) ref,
    ];
    if (missing.isEmpty) return;

    if (assetUrlsResolver != null) {
      final resolvedByRef = await assetUrlsResolver!(missing);
      for (final ref in missing) {
        final resolved = resolvedByRef[ref]?.trim();
        if (resolved != null && resolved.isNotEmpty) {
          _urlCache[ref] = resolved;
        } else {
          _urlCache.remove(ref);
        }
      }
      return;
    }

    if (assetUrlResolver != null) {
      await Future.wait(
        missing.map((ref) async {
          try {
            final resolved = (await assetUrlResolver!(ref))?.trim();
            if (resolved != null && resolved.isNotEmpty) {
              _urlCache[ref] = resolved;
            } else {
              _urlCache.remove(ref);
            }
          } catch (_) {
            _urlCache.remove(ref);
          }
        }),
      );
    }
  }

  Future<void> _primeMetaCache(Set<String> sourceRefs) async {
    if (sourceRefs.isEmpty) return;
    if (assetMetaResolver == null && assetMetasResolver == null) return;

    final missing = <String>[
      for (final ref in sourceRefs)
        if (!_metaCache.containsKey(ref)) ref,
    ];
    if (missing.isEmpty) return;

    if (assetMetasResolver != null) {
      final resolvedByRef = await assetMetasResolver!(missing);
      for (final ref in missing) {
        final size = resolvedByRef[ref];
        if (size != null) {
          _metaCache[ref] = size;
        } else {
          _metaCache.remove(ref);
        }
      }
      return;
    }

    if (assetMetaResolver != null) {
      await Future.wait(
        missing.map((ref) async {
          try {
            final size = await assetMetaResolver!(ref);
            if (size != null) {
              _metaCache[ref] = size;
            } else {
              _metaCache.remove(ref);
            }
          } catch (_) {
            _metaCache.remove(ref);
          }
        }),
      );
    }
  }

  String? _normalizedSourceSync(String raw) {
    final key = _sourceKeyFromRaw(raw);
    if (key == null) return null;

    final resolved = _urlCache[key];
    if (resolved != null && resolved.trim().isNotEmpty) {
      return resolved.trim();
    }

    // If a host resolver was provided, unresolved refs should not be guessed by
    // the renderer. This prevents opaque refs such as `media:abc` from falling
    // through to FileImage/CachedNetworkImage behavior.
    if (_hasUrlResolver) return null;

    // Backward-compatible fallback for renderer-only use with direct renderable
    // refs such as URLs, data URIs, file refs, or Flutter asset paths.
    return key;
  }

  /// Resolve stable intrinsic sizes (metadata) and publish to [intrinsics].
  ///
  /// Intrinsic size must represent the asset’s natural size, even when
  /// ImageData.size is explicitly set.
  Future<void> resolveSceneIntrinsics(
    CanvasSceneDocument scene, {
    required FlutterImageIntrinsics intrinsics,
    bool includeHidden = true,
  }) async {
    final imagesInScene = _collectImageNodes(
      scene,
      includeHidden: includeHidden,
    );

    final sourceRefs = <String>{};
    final sourceRefByElement = <ElementId, String?>{};

    for (final img in imagesInScene) {
      final sourceRef = _sourceKeyFromRaw(img.data.sourcePath);
      sourceRefByElement[img.id] = sourceRef;

      if (sourceRef != null) {
        sourceRefs.add(sourceRef);
      }
    }

    await _primeMetaCache(sourceRefs);

    for (final entry in sourceRefByElement.entries) {
      final sourceRef = entry.value;
      final meta = sourceRef == null ? null : _metaCache[sourceRef];
      intrinsics.setIntrinsicSize(entry.key, meta);
    }
  }

  /// Decode raster images for paint.
  ///
  /// - MUST NOT update intrinsic sizes.
  /// - MUST only cause repaint via [revision].
  Future<void> preloadScene(
    CanvasSceneDocument scene, {
    int? targetW,
    int? targetH,
    FlutterImageIntrinsics? intrinsics,
    bool includeHidden = true,
  }) async {
    final imagesInScene = _collectImageNodes(
      scene,
      includeHidden: includeHidden,
    );

    final sourceRefs = <String>{};

    for (final img in imagesInScene) {
      final sourceRef = _sourceKeyFromRaw(img.data.sourcePath);
      if (sourceRef != null) {
        sourceRefs.add(sourceRef);
      }
    }

    await _primeUrlCache(sourceRefs);
    await _primeMetaCache(sourceRefs);

    final side = _decodeSide(targetW, targetH);

    final tasks = <Future<void>>[];
    for (final img in imagesInScene) {
      tasks.add(() async {
        final raw = img.data.sourcePath;
        final sourceRef = _sourceKeyFromRaw(raw);
        final src = (raw == null) ? null : _normalizedSourceSync(raw);

        _dlog(
          'POOL_PRELOAD',
          'el=${img.id} raw="$raw" sourceRef=$sourceRef normalized="$src"',
        );

        void setImage(ui.Image? next) {
          images[img.id] = next;
          intrinsics?.setImage(img.id, next);
          _bump();
        }

        if (src == null || src.isEmpty) {
          _inflightKey.remove(img.id);
          _loadedKey.remove(img.id);
          setImage(null);
          return;
        }

        final meta = sourceRef == null ? null : _metaCache[sourceRef];
        final dims = _decodeDimsFromMeta(side, meta);

        final key = '$src@${dims.w ?? 0}x${dims.h ?? 0}';

        if (_loadedKey[img.id] == key && images[img.id] != null) {
          return;
        }

        _inflightKey[img.id] = key;

        try {
          final base = sourceToProvider(src);

          final prov = (dims.w != null && dims.h != null)
              ? ResizeImage(base, width: dims.w!, height: dims.h!)
              : withSize(base, width: side, height: null);

          final uiImg = await toUiImage(prov);

          _dlog('POOL_DECODE', 'el=${img.id} ok=${uiImg != null} key="$key"');

          if (_inflightKey[img.id] != key) return;

          if (uiImg == null) {
            _inflightKey.remove(img.id);
            _loadedKey.remove(img.id);
            setImage(null);
            return;
          }

          _inflightKey.remove(img.id);
          _loadedKey[img.id] = key;
          setImage(uiImg);
        } catch (e) {
          _dlog('POOL_DECODE', 'el=${img.id} exception=$e key="$key"');
          if (_inflightKey[img.id] == key) {
            _inflightKey.remove(img.id);
            _loadedKey.remove(img.id);
            setImage(null);
          }
        }
      }());
    }

    if (tasks.isNotEmpty) await Future.wait(tasks);
  }

  void dispose() {
    revision.dispose();
    images.clear();
    _loadedKey.clear();
    _inflightKey.clear();
    _urlCache.clear();
    _metaCache.clear();
  }
}

List<ImageNode> _collectImageNodes(
  CanvasSceneDocument scene, {
  required bool includeHidden,
}) {
  final out = <ImageNode>[];

  visitSceneNodes(
    scene,
    includeHidden: includeHidden,
    visit: (node) {
      if (node is ImageNode) out.add(node);
    },
  );

  return out;
}
