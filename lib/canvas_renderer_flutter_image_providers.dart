// Path: lib/canvas_renderer_flutter_image_providers.dart
//
// Optional ImageProvider helpers for canvas_renderer_flutter.
//
// The renderer core works with decoded images and host-provided resolvers.
// These helpers convert common string refs into Flutter ImageProviders for apps
// that want a simple loading path across mobile and web.

library;

export 'src/images/flutter_image_adapters.dart'
    show sourceToProvider, withSize, toUiImage;
