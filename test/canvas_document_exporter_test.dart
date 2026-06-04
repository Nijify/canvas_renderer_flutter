// Path: test/canvas_document_exporter_test.dart
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:canvas_core/canvas_core_runtime.dart';
import 'package:canvas_renderer_flutter/canvas_renderer_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  CanvasSceneDocument sceneWithBg({required Size2D size, required int color}) {
    return CanvasSceneDocument(
      artboardSize: size,
      bgOpacity: 1,
      bgGradient: LinearGradientSpec(color1: color, color2: color),
    );
  }

  Future<int> pixelAt(ui.Image image, int x, int y) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) {
      throw StateError('Pixel read failed');
    }
    final i = (y * image.width + x) * 4;
    final r = data.getUint8(i);
    final g = data.getUint8(i + 1);
    final b = data.getUint8(i + 2);
    final a = data.getUint8(i + 3);
    return (a << 24) | (r << 16) | (g << 8) | b;
  }

  Future<ui.Image> decodeImage(Uint8List bytes) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, (image) => completer.complete(image));
    return completer.future;
  }

  test('applies pixel ratio, bleed, and background fill', () async {
    final scene = sceneWithBg(size: const Size2D(40, 20), color: 0xFF00FF00);
    final exporter = CanvasDocumentExporter();

    final bytes = await exporter.exportPng(
      document: scene,
      resolveImage: (_) async => null,
      resolveIntrinsicSize: (_) async => null,
      spec: const CanvasExportSpec(
        widthPx: 100,
        heightPx: 50,
        bleedPx: 8,
        pixelRatio: 2.5,
        transparent: false,
        fit: CanvasFit.contain,
      ),
    );

    final image = await decodeImage(bytes);
    expect(image.width, ((100 + 16) * 2.5).round());
    expect(image.height, ((50 + 16) * 2.5).round());

    final bg = await pixelAt(image, 1, 1);
    expect(bg, 0xFFFFFFFF);

    image.dispose();
  });

  test('contain fit centers artboard within target bounds', () async {
    final scene = sceneWithBg(size: const Size2D(100, 50), color: 0xFFFF0000);
    final exporter = CanvasDocumentExporter();

    final bytes = await exporter.exportPng(
      document: scene,
      resolveImage: (_) async => null,
      resolveIntrinsicSize: (_) async => null,
      spec: const CanvasExportSpec(
        widthPx: 200,
        heightPx: 200,
        pixelRatio: 1.0,
        transparent: false,
        fit: CanvasFit.contain,
      ),
    );

    final image = await decodeImage(bytes);
    expect(image.width, 200);
    expect(image.height, 200);

    final topMarginPixel = await pixelAt(image, 10, 10);
    final artboardPixel = await pixelAt(image, 10, 60);
    final bottomMarginPixel = await pixelAt(image, 10, 180);

    expect(topMarginPixel, 0xFFFFFFFF);
    expect(artboardPixel, 0xFFFF0000);
    expect(bottomMarginPixel, 0xFFFFFFFF);

    image.dispose();
  });
}
