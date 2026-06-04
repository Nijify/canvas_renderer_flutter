// Path: lib/src/flutter_linear_shader.dart
//
// Flutter adapter ONLY: take resolved data from canvas_core and
// build a ui.Shader. No angle/stop/opacity math here.

import 'dart:ui' as ui;
import 'package:canvas_core/canvas_core_runtime.dart'; // resolveLinearGradient, Size2D, LinearGradientSpec

ui.Shader buildLinearShaderFlutter(
  ui.Size size,
  LinearGradientSpec spec, {
  double opacity = 1.0,
}) {
  // All math (angle → start/end, width → stops, alpha merge) happens in core:
  final r = resolveLinearGradient(
    spec,
    Size2D(size.width, size.height),
    opacity: opacity,
  );

  // Adapt core types → Flutter types and build the shader:
  final start = ui.Offset(r.start.x, r.start.y);
  final end = ui.Offset(r.end.x, r.end.y);
  final colors = List<ui.Color>.unmodifiable(r.colors.map((c) => ui.Color(c)));

  return ui.Gradient.linear(start, end, colors, r.stops);
}

// (Optional convenience overload if you already carry ResolvedLinearGradient)
ui.Shader buildLinearShaderFromResolved(ResolvedLinearGradient r) {
  final start = ui.Offset(r.start.x, r.start.y);
  final end = ui.Offset(r.end.x, r.end.y);
  final colors = List<ui.Color>.unmodifiable(r.colors.map((c) => ui.Color(c)));
  return ui.Gradient.linear(start, end, colors, r.stops);
}
