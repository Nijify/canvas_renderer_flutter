// Path: lib/src/images/flutter_image_intrinsics.dart
import 'dart:async';
import 'dart:ui' as ui;
import 'package:canvas_core/canvas_core_runtime.dart';

/// Image intrinsics that are **stable** and **surface-independent**.
///
/// Hard rule:
/// - Layout-affecting intrinsic size MUST NOT come from decoded ui.Image sizes.
/// - Decoded images are paint-only and MUST NOT trigger relayout.
class FlutterImageIntrinsics implements ImageIntrinsics {
  FlutterImageIntrinsics([Map<ElementId, ui.Image?>? initial])
    : _images = initial ?? <ElementId, ui.Image?>{};

  /// Paint-only decoded rasters (surface-specific decode sizes).
  final Map<ElementId, ui.Image?> _images;

  /// Stable, layout-affecting intrinsic sizes (metadata).
  final Map<ElementId, Size2D> _intrinsicById = <ElementId, Size2D>{};

  /// Broadcast so multiple consumers (engine, inspector, etc.) can listen.
  final StreamController<ElementId> _intrinsicUpdatedCtrl =
      StreamController<ElementId>.broadcast();

  @override
  Size2D? intrinsicSize(ElementId id) => _intrinsicById[id];

  @override
  Stream<ElementId> get onIntrinsicUpdated => _intrinsicUpdatedCtrl.stream;

  /// Layout-affecting: updates stable intrinsic metadata and MAY trigger relayout.
  ///
  /// This is the ONLY method allowed to emit [onIntrinsicUpdated].
  void setIntrinsicSize(ElementId id, Size2D? size) {
    final prev = _intrinsicById[id];
    if (prev == size) return;

    if (size == null) {
      _intrinsicById.remove(id);
    } else {
      _intrinsicById[id] = size;
    }

    if (!_intrinsicUpdatedCtrl.isClosed) {
      _intrinsicUpdatedCtrl.add(id);
    }
  }

  /// Paint-only: decoded raster for rendering quality.
  /// MUST NOT trigger relayout.
  void setImage(ElementId id, ui.Image? image) {
    _images[id] = image;
  }

  /// Dispose when your renderer is torn down.
  void dispose() {
    _intrinsicUpdatedCtrl.close();
  }
}
