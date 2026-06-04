// Path: lib/src/flutter_mappers.dart

import 'dart:ui' as ui;
import 'package:canvas_core/canvas_core_runtime.dart';

extension Vec2ToUi on Vec2 {
  ui.Offset get toUi => ui.Offset(x, y);
}

extension OffsetToCore on ui.Offset {
  Vec2 get toCore => Vec2(dx, dy);
}

extension Size2DToUi on Size2D {
  ui.Size get toUi => ui.Size(w, h);
}

extension SizeToCore on ui.Size {
  Size2D get toCore => Size2D(width, height);
}

// Rect2D is in core/geometry.dart
extension Rect2DToUi on Rect2D {
  ui.Rect get toUi => ui.Rect.fromLTRB(left, top, right, bottom);
}

extension Color32ToUi on Color32 {
  ui.Color get toUi => ui.Color(this); // assumes ARGB in Color32
}
