// Path: lib/src/flutter_text_measurer.dart

import 'package:canvas_core/canvas_core_runtime.dart';
import 'package:canvas_renderer_flutter/src/flutter_text_pipeline.dart';

class FlutterTextMeasurer implements TextMeasurer {
  final FlutterTextPipeline pipeline;
  FlutterTextMeasurer([FlutterTextPipeline? pipeline])
    : pipeline = pipeline ?? FlutterTextPipeline();

  @override
  Size2D measure({
    required String text,
    required String fontFamily,
    required int fontWeight,
    required double fontSize,
    required int letterSpacing,
  }) {
    assert(letterSpacing == 0, 'letterSpacing must be pre-applied by core');
    final m = pipeline.measure(
      TextSpec(text, fontFamily, fontWeight, fontSize, letterSpacingApplied: 0),
    );
    return Size2D(m.width, m.height);
  }
}
