# canvas_renderer_flutter

`canvas_renderer_flutter` is the Flutter rendering adapter for `canvas_core`. It replays renderer-agnostic paint operations onto a Flutter `Canvas`, provides Flutter-backed text measurement and painting, manages decoded image caches, and exports canvas scenes to PNG.

## Features

- `CanvasRenderer` for drawing `PaintOp` lists on a `dart:ui` canvas.
- `FlutterTextMeasurer` and `FlutterTextPipeline` for `canvas_core` text measurement and text paint support.
- `FlutterImagePool` and `FlutterImageIntrinsics` helpers for decoded images and stable image metadata.
- `CanvasDocumentExporter` for PNG export from a `CanvasSceneDocument` or scene JSON.
- Core-to-Flutter value mappers for colors, rects, sizes, offsets, and gradients.
- Optional ImageProvider helpers for apps that want to convert common image refs into Flutter `ImageProvider`s.

## Installation

Add the package to a Flutter app or package:

```bash
flutter pub add canvas_renderer_flutter canvas_core
```

## Imports

Use the main renderer barrel for core rendering, export, text, image-cache, gradient, and mapper APIs:

```dart
import 'package:canvas_core/canvas_core_runtime.dart';
import 'package:canvas_renderer_flutter/canvas_renderer_flutter.dart';
```

Do not import files under `package:canvas_renderer_flutter/src/`; use the public barrels.

Optional image-provider helpers live behind a separate import:

```dart
import 'package:canvas_renderer_flutter/canvas_renderer_flutter_image_providers.dart';
```

Use that optional import only when your app wants to convert string image refs such as `asset:`, `data:`, `http(s):`, `blob:`, or platform-supported `file:` refs into Flutter `ImageProvider`s.

## Render paint operations in a CustomPainter

```dart
import 'dart:ui' as ui;

import 'package:canvas_core/canvas_core_runtime.dart';
import 'package:canvas_renderer_flutter/canvas_renderer_flutter.dart';
import 'package:flutter/widgets.dart';

class ScenePainter extends CustomPainter {
  ScenePainter({required this.ops, required this.images});

  final List<PaintOp> ops;
  final Map<ElementId, ui.Image?> images;

  @override
  void paint(Canvas canvas, Size size) {
    CanvasRenderer(images: images).replay(canvas, ops);
  }

  @override
  bool shouldRepaint(ScenePainter oldDelegate) {
    return oldDelegate.ops != ops || oldDelegate.images != images;
  }
}
```

Build `ops` with `canvas_core`:

```dart
final services = CoreServices(tm: FlutterTextMeasurer());
final computed = computeScene(document, services);
final ops = buildPaintOpsFromScene(document, computed);
```

## Export a scene to PNG

```dart
// Use CanvasDocumentExporter to export a document to PNG bytes:
Future<void> exportExample(CanvasSceneDocument document) async {
  final exporter = CanvasDocumentExporter();

  final pngBytes = await exporter.exportPng(
    document: document,
    resolveImage: (id) async => imageCache[id],
    resolveIntrinsicSize: (id) async => intrinsicSizes[id],
    spec: const CanvasExportSpec(widthPx: 1080, heightPx: 1080),
  );
}
```

The exporter accepts decoded images separately from intrinsic image sizes. Use stable metadata for layout, and use decoded `ui.Image` objects only for painting.

## Optional ImageProvider helpers

The core renderer works with decoded `ui.Image` objects and host-provided resolvers. Apps that want a simple loading path can import the optional image-provider helpers:

```dart
import 'package:canvas_renderer_flutter/canvas_renderer_flutter_image_providers.dart';

Future<void> loadingExample() async {
  final provider = sourceToProvider('https://example.com/image.png');
  final image = await toUiImage(provider);
}
```

These helpers support common refs such as:

```text
asset:assets/samples/image_01.png
assets/samples/image_01.png
packages/my_package/assets/image_01.png
data:image/png;base64,...
https://example.com/image.png
blob:https://example.com/...
file:///tmp/image.png
```

Platform notes:

* `asset:`, Flutter asset paths, `data:`, and `http(s):` refs are supported where Flutter supports the corresponding `ImageProvider`.
* `blob:` refs are mainly useful on web and depend on the current Flutter platform’s image loading support.
* `file:` refs and raw local file paths are IO-platform only.
* Web hosts should resolve file-backed or app-specific media refs to `asset:`, `data:`, `blob:`, or `http(s):` before rendering.

## Image source boundaries

`canvas_renderer_flutter` treats canvas image source refs as opaque renderer inputs. App-specific meanings belong outside this package.

For example, the renderer should not know what these mean:

```text
media:abc123
myapp://image/42
db:image-row-id
```

Host apps should resolve those refs before rendering, usually by providing resolver callbacks to `FlutterImagePool` or by passing decoded images directly to export/render APIs.

A typical flow is:

```text
Canvas document image ref
  -> host/app resolver
  -> renderable ref or decoded ui.Image
  -> canvas_renderer_flutter
```

## Boundaries

* This package may use Flutter painting APIs and `dart:ui`.
* It depends on `canvas_core` contracts and does not depend on editor UI.
* The renderer core does not know app storage, repositories, auth, media IDs, product concepts, or persistence flows.
* Hosts provide images, fonts, and metadata through adapters or decoded inputs.
* Optional ImageProvider helpers are available from `canvas_renderer_flutter_image_providers.dart` for apps that want to convert common string refs into Flutter image providers.
* It is stateless and deterministic: paint operations plus viewport/image/text inputs produce canvas calls.
* Gestures, selection, undo, editor state, and application workflows belong in an editor or app layer.

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE).

Copyright 2026 Nijify.
