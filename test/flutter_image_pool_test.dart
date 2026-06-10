// Path: test/flutter_image_pool_test.dart

import 'dart:async';
import 'package:canvas_core/canvas_core_runtime.dart';
import 'package:canvas_renderer_flutter/src/images/flutter_image_intrinsics.dart';
import 'package:canvas_renderer_flutter/src/images/flutter_image_pool.dart';
import 'package:flutter_test/flutter_test.dart';

CanvasSceneDocument _sceneWithImages(List<String> sourceRefs) {
  return CanvasSceneDocument(
    artboardSize: const Size2D(300, 200),
    bgGradient: LinearGradientSpec.transparent,
    bgOpacity: 0,
    children: [
      for (var i = 0; i < sourceRefs.length; i++)
        Node.image(
          id: 'image-$i',
          data: ImageData(
            sourcePath: sourceRefs[i],
            size: const Size2D(100, 100),
          ),
        ),
    ],
  );
}

void main() {
  group('FlutterImagePool asset boundaries', () {
    test('passes opaque media refs to intrinsic resolver unchanged', () async {
      final requestedRefs = <String>[];

      final pool = FlutterImagePool(
        assetMetaResolver: (sourceRef) async {
          requestedRefs.add(sourceRef);
          return const Size2D(640, 480);
        },
      );

      final intrinsics = FlutterImageIntrinsics(pool.images);

      await pool.resolveSceneIntrinsics(
        _sceneWithImages(['media:abc123']),
        intrinsics: intrinsics,
      );

      expect(requestedRefs, ['media:abc123']);
      expect(intrinsics.intrinsicSize('image-0'), const Size2D(640, 480));

      intrinsics.dispose();
      pool.dispose();
    });

    test('passes opaque asset refs to intrinsic resolver unchanged', () async {
      final requestedRefs = <String>[];

      final pool = FlutterImagePool(
        assetMetaResolver: (sourceRef) async {
          requestedRefs.add(sourceRef);
          return const Size2D(1024, 1024);
        },
      );

      final intrinsics = FlutterImageIntrinsics(pool.images);

      await pool.resolveSceneIntrinsics(
        _sceneWithImages(['asset:assets/samples/sample_image.png']),
        intrinsics: intrinsics,
      );

      expect(requestedRefs, ['asset:assets/samples/sample_image.png']);
      expect(intrinsics.intrinsicSize('image-0'), const Size2D(1024, 1024));

      intrinsics.dispose();
      pool.dispose();
    });

    test(
      'passes original source refs to bulk URL resolver unchanged',
      () async {
        final requestedBatches = <List<String>>[];

        final pool = FlutterImagePool(
          assetUrlsResolver: (sourceRefs) async {
            requestedBatches.add(List<String>.from(sourceRefs));

            // Return an empty map on purpose. The test only verifies resolver
            // boundary behavior and avoids image decoding.
            return const <String, String>{};
          },
        );

        final intrinsics = FlutterImageIntrinsics(pool.images);

        await pool.preloadScene(
          _sceneWithImages([
            'media:abc123',
            'asset:assets/samples/sample_image.png',
          ]),
          intrinsics: intrinsics,
        );

        expect(requestedBatches, hasLength(1));
        expect(
          requestedBatches.single,
          unorderedEquals([
            'media:abc123',
            'asset:assets/samples/sample_image.png',
          ]),
        );

        intrinsics.dispose();
        pool.dispose();
      },
    );

    test(
      'does not guess unresolved opaque refs when a URL resolver exists',
      () async {
        final pool = FlutterImagePool(assetUrlResolver: (_) async => null);

        final intrinsics = FlutterImageIntrinsics(pool.images);

        await pool.preloadScene(
          _sceneWithImages(['media:missing']),
          intrinsics: intrinsics,
        );

        expect(pool.images['image-0'], isNull);

        intrinsics.dispose();
        pool.dispose();
      },
    );

    test('ignores late unresolved preload completion after dispose', () async {
      final resolver = Completer<Map<String, String>>();

      final pool = FlutterImagePool(assetUrlsResolver: (_) => resolver.future);
      final intrinsics = FlutterImageIntrinsics(pool.images);

      final future = pool.preloadScene(
        _sceneWithImages(['media:late']),
        intrinsics: intrinsics,
      );

      pool.dispose();

      resolver.complete(const <String, String>{});

      await expectLater(future, completes);
      expect(pool.images, isEmpty);

      intrinsics.dispose();
    });

    test('ignores late intrinsic metadata completion after dispose', () async {
      final resolver = Completer<Map<String, Size2D>>();

      final pool = FlutterImagePool(assetMetasResolver: (_) => resolver.future);
      final intrinsics = FlutterImageIntrinsics(pool.images);

      final future = pool.resolveSceneIntrinsics(
        _sceneWithImages(['media:late']),
        intrinsics: intrinsics,
      );

      pool.dispose();

      resolver.complete(const <String, Size2D>{'media:late': Size2D(640, 480)});

      await expectLater(future, completes);
      expect(intrinsics.intrinsicSize('image-0'), isNull);

      intrinsics.dispose();
    });
  });
}
