// Path: lib/src/flutter_canvas_renderer.dart

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:canvas_core/canvas_core_runtime.dart';
import 'package:canvas_renderer_flutter/src/flutter_linear_shader.dart';
import 'package:canvas_renderer_flutter/src/flutter_mappers.dart';
import 'package:canvas_renderer_flutter/src/flutter_text_pipeline.dart';

enum CanvasDisplayQuality { thumbnail, preview, editor }

enum MissingImageBehavior { placeholder, skip }

class CanvasRendererOptions {
  const CanvasRendererOptions({
    required this.imageFilterQuality,
    required this.missingImageBehavior,
  });

  final ui.FilterQuality imageFilterQuality;
  final MissingImageBehavior missingImageBehavior;
}

abstract final class CanvasRendererProfiles {
  static const thumbnail = CanvasRendererOptions(
    imageFilterQuality: ui.FilterQuality.medium,
    missingImageBehavior: MissingImageBehavior.skip,
  );

  static const preview = CanvasRendererOptions(
    imageFilterQuality: ui.FilterQuality.none,
    missingImageBehavior: MissingImageBehavior.skip,
  );

  static const documentExport = CanvasRendererOptions(
    imageFilterQuality: ui.FilterQuality.none,
    missingImageBehavior: MissingImageBehavior.skip,
  );

  static const editor = CanvasRendererOptions(
    imageFilterQuality: ui.FilterQuality.none,
    missingImageBehavior: MissingImageBehavior.placeholder,
  );

  static CanvasRendererOptions forDisplayQuality(CanvasDisplayQuality quality) {
    return switch (quality) {
      CanvasDisplayQuality.thumbnail => thumbnail,
      CanvasDisplayQuality.preview => preview,
      CanvasDisplayQuality.editor => editor,
    };
  }
}

class CanvasRenderer {
  final Map<ElementId, ui.Image?> images;
  final FlutterTextPipeline text;

  /// Stable intrinsic metadata provider (width/height in intrinsic pixel space).
  /// Used to map DrawImageOp.src from intrinsic-space -> decoded image pixel-space.
  final ImageIntrinsics? intrinsics;

  final CanvasRendererOptions options;

  CanvasRenderer({
    Map<ElementId, ui.Image?>? images,
    FlutterTextPipeline? text,
    this.intrinsics,
    this.options = CanvasRendererProfiles.editor,
  }) : images = images ?? <ElementId, ui.Image?>{},
       text = text ?? FlutterTextPipeline();

  ui.Rect _mapSrcToDecoded({
    required ElementId id,
    required ui.Image img,
    required Rect2D srcIntrinsic,
  }) {
    final meta = intrinsics?.intrinsicSize(id);

    // If we don't know intrinsic meta, fall back to using src as-is.
    // (This may be imperfect for resized decodes, but keeps compatibility.)
    if (meta == null || meta.w <= 0 || meta.h <= 0) {
      return srcIntrinsic.toUi;
    }

    final iw = meta.w;
    final ih = meta.h;

    final dw = img.width.toDouble();
    final dh = img.height.toDouble();

    // Guard: if decoded looks invalid, fall back.
    if (dw <= 0 || dh <= 0) return srcIntrinsic.toUi;

    final sx = dw / iw;
    final sy = dh / ih;

    final s = srcIntrinsic.toUi;

    // Scale intrinsic-space rect into decoded pixel-space rect.
    var left = s.left * sx;
    var top = s.top * sy;
    var right = s.right * sx;
    var bottom = s.bottom * sy;

    // Clamp to decoded bounds to avoid backend-specific behavior when out of range.
    if (left.isNaN || top.isNaN || right.isNaN || bottom.isNaN) {
      return srcIntrinsic.toUi;
    }

    left = left.clamp(0.0, dw);
    top = top.clamp(0.0, dh);
    right = right.clamp(0.0, dw);
    bottom = bottom.clamp(0.0, dh);

    // Ensure non-negative extents (defensive).
    if (right < left) right = left;
    if (bottom < top) bottom = top;

    return ui.Rect.fromLTRB(left, top, right, bottom);
  }

  void replay(ui.Canvas canvas, List<PaintOp> ops) {
    for (final op in ops) {
      switch (op) {
        case SaveOp():
          canvas.save();

        case RestoreOp():
          canvas.restore();

        case SetTransformOp(
          :final a,
          :final b,
          :final c,
          :final d,
          :final e,
          :final f,
        ):
          canvas.transform(_m(a, b, c, d, e, f));

        case FillRectOp(:final r, :final color):
          canvas.drawRect(r.toUi, ui.Paint()..color = ui.Color(color));

        case FillPathOp(:final path):
          final uiPath = _buildUiPath(path);
          uiPath.fillType = switch (path.style.fillRule) {
            FillRule.evenOdd => ui.PathFillType.evenOdd,
            FillRule.nonZero => ui.PathFillType.nonZero,
          };
          final fill = path.style.fill;
          if (fill != null) {
            canvas.drawPath(
              uiPath,
              ui.Paint()
                ..style = ui.PaintingStyle.fill
                ..color = ui.Color(fill),
            );
          }

        case StrokePathOp(:final path):
          final style = path.style;
          if (style.stroke != null && style.strokeWidth > 0) {
            final uiPath = _buildUiPath(path);
            final paint = ui.Paint()
              ..style = ui.PaintingStyle.stroke
              ..color = ui.Color(style.stroke!)
              ..strokeWidth = style.strokeWidth
              ..strokeCap = _mapCap(style.strokeCap)
              ..strokeJoin = _mapJoin(style.strokeJoin)
              ..strokeMiterLimit = style.miterLimit;

            canvas.drawPath(uiPath, paint);
          }

        case DrawImageOp(:final id, :final src, :final dst):
          final img = images[id];
          final dstRect = dst.toUi;

          if (img == null) {
            if (options.missingImageBehavior == MissingImageBehavior.skip) {
              continue;
            }

            _drawMissingImagePlaceholder(canvas, dstRect);
            continue;
          }

          // PaintOp src is in intrinsic-space pixels; Flutter expects
          // decoded-space pixels.
          final srcRect = _mapSrcToDecoded(id: id, img: img, srcIntrinsic: src);

          final paint = ui.Paint()..filterQuality = options.imageFilterQuality;

          canvas.drawImageRect(img, srcRect, dstRect, paint);

        case DrawTextOp t:
          _drawText(canvas, t);

        case FillRectGradientOp(:final r, :final gradient):
          final paint = ui.Paint()
            ..shader = buildLinearShaderFromResolved(gradient);
          canvas.drawRect(r.toUi, paint);

        case FillPathGradientOp(:final path, :final gradient):
          final uiPath = _buildUiPath(path);
          uiPath.fillType = switch (path.style.fillRule) {
            FillRule.evenOdd => ui.PathFillType.evenOdd,
            FillRule.nonZero => ui.PathFillType.nonZero,
          };
          final paint = ui.Paint()
            ..style = ui.PaintingStyle.fill
            ..shader = buildLinearShaderFromResolved(gradient);
          canvas.drawPath(uiPath, paint);
      }
    }
  }

  static void _drawMissingImagePlaceholder(ui.Canvas canvas, ui.Rect dstRect) {
    final border = ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const ui.Color(0xFF9CA3AF);

    canvas.drawRect(dstRect, border);

    if (dstRect.width <= 20 || dstRect.height <= 20) return;

    final cross = ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const ui.Color(0xFFB0B6C2);

    final r = dstRect.deflate(6.0);
    canvas.drawLine(r.topLeft, r.bottomRight, cross);
    canvas.drawLine(r.bottomLeft, r.topRight, cross);
  }

  // --- helpers --------------------------------------------------------------

  static ui.Path _buildUiPath(PathIR ir) {
    final p = ui.Path();
    for (final cmd in ir.cmds) {
      switch (cmd.verb) {
        case PathVerb.moveTo:
          p.moveTo(cmd.p.x, cmd.p.y);
        case PathVerb.lineTo:
          p.lineTo(cmd.p.x, cmd.p.y);
        case PathVerb.quadTo:
          final c = cmd.c1!;
          p.quadraticBezierTo(c.x, c.y, cmd.p.x, cmd.p.y);
        case PathVerb.cubicTo:
          final c1 = cmd.c1!, c2 = cmd.c2!;
          p.cubicTo(c1.x, c1.y, c2.x, c2.y, cmd.p.x, cmd.p.y);
        case PathVerb.close:
          p.close();
      }
    }
    return p;
  }

  static ui.StrokeCap _mapCap(StrokeCap c) => switch (c) {
    StrokeCap.butt => ui.StrokeCap.butt,
    StrokeCap.square => ui.StrokeCap.square,
    StrokeCap.round => ui.StrokeCap.round,
  };

  static ui.StrokeJoin _mapJoin(StrokeJoin j) => switch (j) {
    StrokeJoin.miter => ui.StrokeJoin.miter,
    StrokeJoin.bevel => ui.StrokeJoin.bevel,
    StrokeJoin.round => ui.StrokeJoin.round,
  };

  void _drawText(ui.Canvas canvas, DrawTextOp t) {
    if (t.text.isEmpty) return;

    final spec = TextSpec(
      t.text,
      t.family,
      t.weight,
      t.size,
      letterSpacingApplied: 0,
    );

    ui.Shader? shader;
    if (t.gradient != null) {
      shader = buildLinearShaderFromResolved(t.gradient!);
    }

    final solidColor = t.solid != null
        ? ui.Color(t.solid!)
        : const ui.Color(0xFF000000);

    text.paint(
      canvas,
      t.originBaselineCenter.toUi,
      spec,
      solid: solidColor,
      shader: shader,
      shadowOffset: t.shadowOffset.toDouble(),
      originKind: TextOriginKind.center,
    );
  }

  static Float64List _m(
    double a,
    double b,
    double c,
    double d,
    double e,
    double f,
  ) => Float64List.fromList([a, b, 0, 0, c, d, 0, 0, 0, 0, 1, 0, e, f, 0, 1]);
}
