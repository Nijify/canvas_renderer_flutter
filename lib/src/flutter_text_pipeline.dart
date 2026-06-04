// Path: lib/src/flutter_text_pipeline.dart

import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

class TextSpec {
  final String text;
  final String family;
  final int weight; // 100..900
  final double size;
  // letterSpacing must be pre-applied in core; keep for sanity checks.
  final int letterSpacingApplied; // expect 0
  const TextSpec(
    this.text,
    this.family,
    this.weight,
    this.size, {
    this.letterSpacingApplied = 0,
  });
}

class TextMetrics {
  final double width, height, baseline; // alphabetic baseline
  const TextMetrics(this.width, this.height, this.baseline);
}

class FlutterTextPipeline {
  FlutterTextPipeline({
    int maxEntries = 4096,
    Iterable<String> fallbackFontFamilies = const <String>[],
  }) : assert(maxEntries > 0),
       _maxEntries = maxEntries,
       _fallbackFontFamilies = List<String>.unmodifiable(
         fallbackFontFamilies
             .map((family) => family.trim())
             .where((family) => family.isNotEmpty),
       );

  final int _maxEntries;
  final List<String> _fallbackFontFamilies;

  List<String> _fallbackFor(String primary) {
    final cleanPrimary = primary.trim();
    return _fallbackFontFamilies
        .where((family) => family != cleanPrimary)
        .toList(growable: false);
  }

  // LRU: touch moves entry to end (most-recent).
  final LinkedHashMap<_Key, _CacheEntry> _cache =
      LinkedHashMap<_Key, _CacheEntry>();

  int get cacheSize => _cache.length;

  /// Clears all cached layout-only entries.
  void clearCache() => _cache.clear();

  TextMetrics measure(TextSpec s) {
    final entry = _getOrCreateLayoutEntry(s);
    _ensureLaidOut(entry);
    return entry.metrics!;
  }

  // Paint with either a solid color or a prebuilt shader (for gradients).
  void paint(
    ui.Canvas canvas,
    ui.Offset origin, // choose semantic via `originKind`
    TextSpec s, {
    ui.Color? solid,
    ui.Shader? shader,
    double shadowOffset = 0,
    TextOriginKind originKind = TextOriginKind.baseline, // baseline or center
  }) {
    final fgPaint = (shader != null)
        ? (ui.Paint()..shader = shader)
        : null; // null ⇒ use `solid` color in style

    // Shadow first (uncached painter with solid color)
    if (shadowOffset != 0) {
      final tpShadow = _buildPainterUncached(
        s,
        color: solid ?? const ui.Color(0xFF000000),
      );
      tpShadow.layout();
      final o = _resolveOrigin(tpShadow, origin, originKind);
      tpShadow.paint(
        canvas,
        ui.Offset(o.dx + shadowOffset, o.dy + shadowOffset),
      );
    }

    // Fast path: layout-only variant (no shader/foreground, no explicit solid)
    // Reuse cached painter + cached metrics and avoid re-layout.
    if (fgPaint == null && solid == null) {
      final entry = _getOrCreateLayoutEntry(s);
      _ensureLaidOut(entry);
      final tp = entry.painter;
      tp.paint(canvas, _resolveOrigin(tp, origin, originKind));
      return;
    }

    // Foreground / colored variants are not cached (metrics are identical).
    final tp = _buildPainterUncached(s, color: solid, foreground: fgPaint);
    tp.layout();
    tp.paint(canvas, _resolveOrigin(tp, origin, originKind));
  }

  ui.Offset _resolveOrigin(TextPainter tp, ui.Offset origin, TextOriginKind k) {
    if (k == TextOriginKind.center) {
      // Center on BOTH axes: match core's local rect (-w/2..+w/2, -h/2..+h/2)
      return ui.Offset(origin.dx - tp.width / 2, origin.dy - tp.height / 2);
    }
    // Alphabetic baseline origin: y is baseline, so move up by ascent.
    final baseline = tp.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    return ui.Offset(origin.dx, origin.dy - baseline);
  }

  _CacheEntry _getOrCreateLayoutEntry(TextSpec s) {
    assert(
      s.letterSpacingApplied == 0,
      'letterSpacing must be pre-applied by canvas_core.spacedText()',
    );

    final key = _Key(s.text, s.family, s.weight, s.size);

    // Touch for LRU: remove+reinsert.
    final existing = _cache.remove(key);
    if (existing != null) {
      _cache[key] = existing;
      return existing;
    }

    final painter = _buildPainterUncached(s);
    final entry = _CacheEntry(painter);
    _cache[key] = entry;
    _evictIfNeeded();
    return entry;
  }

  void _ensureLaidOut(_CacheEntry entry) {
    if (entry.metrics != null) return;
    final tp = entry.painter;
    tp.layout();
    final baseline = tp.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    entry.metrics = TextMetrics(tp.width, tp.height, baseline.toDouble());
  }

  void _evictIfNeeded() {
    while (_cache.length > _maxEntries) {
      // Remove least-recently used (front of LinkedHashMap).
      _cache.remove(_cache.keys.first);
    }
  }

  TextPainter _buildPainterUncached(
    TextSpec s, {
    ui.Paint? foreground,
    ui.Color? color,
  }) {
    assert(
      s.letterSpacingApplied == 0,
      'letterSpacing must be pre-applied by canvas_core.spacedText()',
    );

    final fw = FontWeight.values.firstWhere(
      (w) => w.value == s.weight,
      orElse: () => FontWeight.w400,
    );

    final style = TextStyle(
      fontFamily: s.family,
      fontFamilyFallback: _fallbackFor(s.family),
      fontWeight: fw,
      fontSize: s.size,
      // If a shader is provided, it must go into foreground.
      foreground: foreground,
      color: foreground == null ? (color ?? const ui.Color(0xFF000000)) : null,
    );

    return TextPainter(
      text: TextSpan(text: s.text, style: style),
      textDirection: ui.TextDirection.ltr,
    );
  }
}

enum TextOriginKind { baseline, center }

class _CacheEntry {
  _CacheEntry(this.painter);
  final TextPainter painter;
  TextMetrics? metrics;
}

class _Key {
  final String t, f;
  final int w;
  final double s;
  const _Key(this.t, this.f, this.w, this.s);

  @override
  int get hashCode => Object.hash(t, f, w, s);

  @override
  bool operator ==(Object o) =>
      o is _Key && t == o.t && f == o.f && w == o.w && s == o.s;
}
