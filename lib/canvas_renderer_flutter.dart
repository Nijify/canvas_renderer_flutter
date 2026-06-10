// Path: lib/canvas_renderer_flutter.dart
//
// ──────────────────────────────────────────────────────────────────────────────
// canvas_renderer_flutter – Public API (Flutter adapter)
// External packages should import *only* this file (no src/* imports).
//
// Manager-level map (+ mental models, with ROLES):
// • Draw paint ops on Flutter     → CanvasRenderer            // Replays core paint ops on a Canvas
// • Text measurement/painting     → FlutterText*              // Host text pipeline (measure + paint)
// • Images (decode/cache)         → FlutterImagePool          // ui.Image cache keyed by ElementId
// • Gradient adapter              → buildLinearShaderFlutter  // Core gradient → ui.Shader
// • Type mappers                  → *ToUi / *ToCore           // Core ↔ Flutter value adapters
//
// Optional ImageProvider helpers live in
// `canvas_renderer_flutter_image_providers.dart`.
// Layering rules:
// • Depends on canvas_core contracts.
// • No business logic. No schema, tokens, or z-order rules here.
// • Renderer = “how” to draw; core already decided “what” to draw.
// ──────────────────────────────────────────────────────────────────────────────

library;

// ============================================================================
// 1) Renderer façade
//    Mental model: take PaintOps from core, draw them onto a Flutter Canvas.
// ============================================================================
export 'src/flutter_canvas_renderer.dart'
    show CanvasRenderer, CanvasRendererOptions, MissingImageBehavior;

export 'package:canvas_core/canvas_core_runtime.dart'
    show CanvasFit, ContentBoundsPolicy;
export 'src/canvas_document_exporter.dart'
    show CanvasDocumentExporter, CanvasExportSpec;

// ============================================================================
// 2) Text pipeline (measurement + painting)
//    Mental model: host-provided text services for the core engine.
//    - Measurer implements canvas_core.TextMeasurer
//    - Pipeline provides measuring + painting utilities used by renderer
// ============================================================================
export 'src/flutter_text_measurer.dart' show FlutterTextMeasurer;
export 'src/flutter_text_pipeline.dart'
    show FlutterTextPipeline, TextSpec, TextMetrics, TextOriginKind;

// ============================================================================
// 3) Images (decode, cache, and intrinsic sizes)
//    Mental model: decode ImageProvider → ui.Image; cache by ElementId; answer intrinsic sizes.
// ============================================================================
export 'src/images/flutter_image_pool.dart' show FlutterImagePool;
export 'src/images/flutter_image_intrinsics.dart' show FlutterImageIntrinsics;

// ============================================================================
// 4) Gradients (adapter)
//    Mental model: core resolves gradient math; adapter builds ui.Shader.
// ============================================================================
export 'src/flutter_linear_shader.dart'
    show buildLinearShaderFlutter, buildLinearShaderFromResolved;

// ============================================================================
// 5) Value mappers (core ↔ Flutter)
//    Mental model: tiny extensions to bridge core PODs and ui types.
// ============================================================================
export 'src/flutter_mappers.dart'
    show
        Vec2ToUi,
        OffsetToCore,
        Size2DToUi,
        SizeToCore,
        Rect2DToUi,
        Color32ToUi;
