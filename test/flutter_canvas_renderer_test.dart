// Path: test/flutter_canvas_renderer_test.dart

import 'dart:ui' as ui;

import 'package:canvas_core/canvas_core_runtime.dart';
import 'package:canvas_renderer_flutter/canvas_renderer_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

class _CapturingTextPipeline extends FlutterTextPipeline {
  ui.Color? lastSolid;
  ui.Shader? lastShader;

  @override
  void paint(
    ui.Canvas canvas,
    ui.Offset origin,
    TextSpec s, {
    ui.Color? solid,
    ui.Shader? shader,
    double shadowOffset = 0,
    TextOriginKind originKind = TextOriginKind.baseline,
  }) {
    lastSolid = solid;
    lastShader = shader;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('passes solid color to text pipeline even when shader is set', () {
    final pipeline = _CapturingTextPipeline();
    final renderer = CanvasRenderer(text: pipeline);

    final gradient = ResolvedLinearGradient(
      const Vec2(0, 0),
      const Vec2(10, 0),
      const [0xFF0000FF, 0xFF00FF00],
      const [0.0, 1.0],
    );

    const solid = 0xFFAA8844;

    final op = DrawTextOp(
      text: 'Hi',
      family: 'Inter',
      weight: 400,
      size: 20,
      originBaselineCenter: const Vec2(10, 10),
      gradient: gradient,
      solid: solid,
      shadowOffset: 1,
    );

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    renderer.replay(canvas, [op]);

    final picture = recorder.endRecording();
    picture.dispose();

    expect(pipeline.lastSolid, const ui.Color(solid));
    expect(pipeline.lastShader, isNotNull);
  });

  test('display quality profiles map to expected renderer options', () {
    expect(
      CanvasRendererProfiles.forDisplayQuality(
        CanvasDisplayQuality.thumbnail,
      ).imageFilterQuality,
      ui.FilterQuality.medium,
    );

    expect(
      CanvasRendererProfiles.forDisplayQuality(
        CanvasDisplayQuality.thumbnail,
      ).missingImageBehavior,
      MissingImageBehavior.skip,
    );

    expect(
      CanvasRendererProfiles.forDisplayQuality(
        CanvasDisplayQuality.preview,
      ).imageFilterQuality,
      ui.FilterQuality.none,
    );

    expect(
      CanvasRendererProfiles.forDisplayQuality(
        CanvasDisplayQuality.preview,
      ).missingImageBehavior,
      MissingImageBehavior.skip,
    );

    expect(
      CanvasRendererProfiles.forDisplayQuality(
        CanvasDisplayQuality.editor,
      ).imageFilterQuality,
      ui.FilterQuality.none,
    );

    expect(
      CanvasRendererProfiles.forDisplayQuality(
        CanvasDisplayQuality.editor,
      ).missingImageBehavior,
      MissingImageBehavior.placeholder,
    );
  });
}
