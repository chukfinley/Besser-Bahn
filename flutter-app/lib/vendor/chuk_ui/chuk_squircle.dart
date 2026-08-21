// Vendored from chuk_ui — git@github.com:chukfinley/chuk_ui.git
// Source: lib/src/shape/chuk_squircle.dart @ commit 3ae5a1e (v0.4.2).
//
// COPIED, NOT A DEPENDENCY: the IzzyOnDroid reproducible build must not gain a
// new external (Git) dependency — see BUILDING.md. Only the slice the nav bar
// needs is vendored, not the whole package.
//
// Edits here are LOCAL and do NOT flow back to chuk_ui. Re-sync by hand against
// upstream and re-apply the deltas noted below.
//
// Delta vs upstream: the unused ClipSquircle / ClipAppIcon convenience
// widgets at the end of the file are not vendored — the nav bar only needs
// SquircleBorder.

import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';

/// Continuously-curved corners ("squircle"), like iOS/macOS.
///
/// A normal [BorderRadius] replaces the corner with a quarter circle: the
/// curvature jumps from 0 to 1/r at the seam (a G1 transition). Here the corner
/// is instead built from `bezier → (short) arc → bezier`, so curvature ramps up
/// smoothly (a G2 transition).
///
/// Parameters map 1:1 to Figma's "Corner Smoothing":
///   smoothing = 0.0  → classic circular rounding
///   smoothing = 0.6  → iOS app-icon look (Apple default)
///   smoothing = 1.0  → maximally soft
///
/// The iOS icon radius is about 22.37% of the edge length.
const double kAppleCornerSmoothing = 0.6;
const double kAppleIconRadiusRatio = 0.2237;

// ---------------------------------------------------------------------------
// Geometry
// ---------------------------------------------------------------------------

class _CornerParams {
  const _CornerParams({
    required this.a,
    required this.b,
    required this.c,
    required this.d,
    required this.p,
    required this.arcLength,
    required this.radius,
  });

  /// Lengths of the two cubic bezier segments.
  final double a, b, c, d;

  /// Distance from the corner point where the rounding begins.
  final double p;

  /// Chord length of the remaining circular arc.
  final double arcLength;

  final double radius;

  static const _CornerParams zero = _CornerParams(
    a: 0,
    b: 0,
    c: 0,
    d: 0,
    p: 0,
    arcLength: 0,
    radius: 0,
  );
}

double _rad(double deg) => deg * math.pi / 180.0;

/// Computes the bezier control distances for a corner.
///
/// [budget] is the maximum space the corner may take along an edge (for a
/// uniform radius: min(w, h) / 2).
_CornerParams _cornerParams(double radius, double smoothing, double budget) {
  final double r = math.min(radius, budget);
  if (r <= 0) return _CornerParams.zero;

  // Reduce smoothing enough that the corner fits within the budget.
  final double maxSmoothing = (budget / r) - 1.0;
  final double s = smoothing
      .clamp(0.0, 1.0)
      .toDouble()
      .clamp(0.0, math.max(0.0, maxSmoothing));
  final double p = math.min((1.0 + s) * r, budget);

  // The arc shrinks from 90° (s = 0) to 0° (s = 1).
  final double arcMeasure = 90.0 * (1.0 - s);
  final double arcLength = math.sin(_rad(arcMeasure / 2)) * r * math.sqrt2;

  final double alpha = (90.0 - arcMeasure) / 2.0;
  final double p3ToP4 = r * math.tan(_rad(alpha / 2));

  final double beta = 45.0 * s;
  final double c = p3ToP4 * math.cos(_rad(beta));
  final double d = c * math.tan(_rad(beta));

  final double b = (p - arcLength - c - d) / 3.0;
  final double a = 2.0 * b;

  return _CornerParams(
    a: a,
    b: b,
    c: c,
    d: d,
    p: p,
    arcLength: arcLength,
    radius: r,
  );
}

/// Builds the path of a squircle rectangle.
///
/// With [smoothing] == 0 the result is identical to a classic RRect with
/// [radius].
Path squirclePath(Rect rect, double radius, double smoothing) {
  final double w = rect.width;
  final double h = rect.height;
  if (w <= 0 || h <= 0) return Path();

  final double budget = math.min(w, h) / 2.0;
  final k = _cornerParams(radius, smoothing, budget);
  final path = Path();

  if (k.radius <= 0) {
    return path..addRect(rect);
  }

  final double a = k.a, b = k.b, c = k.c, d = k.d;
  final double p = k.p, arc = k.arcLength;
  final Radius r = Radius.circular(k.radius);

  // Start: top edge, left of the top-right corner.
  path.moveTo(rect.left + p, rect.top);
  path.lineTo(rect.right - p, rect.top);

  // Top-right
  path.relativeCubicTo(a, 0, a + b, 0, a + b + c, d);
  path.relativeArcToPoint(Offset(arc, arc), radius: r, clockwise: true);
  path.relativeCubicTo(d, c, d, b + c, d, a + b + c);

  path.lineTo(rect.right, rect.bottom - p);

  // Bottom-right
  path.relativeCubicTo(0, a, 0, a + b, -d, a + b + c);
  path.relativeArcToPoint(Offset(-arc, arc), radius: r, clockwise: true);
  path.relativeCubicTo(-c, d, -(b + c), d, -(a + b + c), d);

  path.lineTo(rect.left + p, rect.bottom);

  // Bottom-left
  path.relativeCubicTo(-a, 0, -(a + b), 0, -(a + b + c), -d);
  path.relativeArcToPoint(Offset(-arc, -arc), radius: r, clockwise: true);
  path.relativeCubicTo(-d, -c, -d, -(b + c), -d, -(a + b + c));

  path.lineTo(rect.left, rect.top + p);

  // Top-left
  path.relativeCubicTo(0, -a, 0, -(a + b), d, -(a + b + c));
  path.relativeArcToPoint(Offset(arc, -arc), radius: r, clockwise: true);
  path.relativeCubicTo(c, -d, b + c, -d, a + b + c, -d);

  path.close();
  return path;
}

// ---------------------------------------------------------------------------
// ShapeBorder
// ---------------------------------------------------------------------------

/// An [OutlinedBorder] with continuously-curved corners.
///
/// Works anywhere Flutter accepts a [ShapeBorder]: `ShapeDecoration(shape: ...)`,
/// `ClipPath` via [ShapeBorderClipper], `ButtonStyle(shape: ...)`, etc.
@immutable
class SquircleBorder extends OutlinedBorder {
  const SquircleBorder({
    this.radius = 12.0,
    this.smoothing = kAppleCornerSmoothing,
    super.side = BorderSide.none,
  }) : assert(radius >= 0),
       assert(smoothing >= 0.0 && smoothing <= 1.0);

  final double radius;
  final double smoothing;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  ShapeBorder scale(double t) => SquircleBorder(
    radius: radius * t,
    smoothing: smoothing,
    side: side.scale(t),
  );

  @override
  SquircleBorder copyWith({
    BorderSide? side,
    double? radius,
    double? smoothing,
  }) {
    return SquircleBorder(
      side: side ?? this.side,
      radius: radius ?? this.radius,
      smoothing: smoothing ?? this.smoothing,
    );
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return squirclePath(rect, radius, smoothing);
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return squirclePath(
      rect.deflate(side.width),
      math.max(0.0, radius - side.width),
      smoothing,
    );
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    final Rect inner = rect.deflate(side.width / 2);
    final Path path = squirclePath(
      inner,
      math.max(0.0, radius - side.width / 2),
      smoothing,
    );
    canvas.drawPath(path, side.toPaint());
  }

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    if (a is SquircleBorder) {
      return SquircleBorder(
        side: BorderSide.lerp(a.side, side, t),
        radius: lerpDouble(a.radius, radius, t)!,
        smoothing: lerpDouble(a.smoothing, smoothing, t)!,
      );
    }
    return super.lerpFrom(a, t);
  }

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) {
    if (b is SquircleBorder) {
      return SquircleBorder(
        side: BorderSide.lerp(side, b.side, t),
        radius: lerpDouble(radius, b.radius, t)!,
        smoothing: lerpDouble(smoothing, b.smoothing, t)!,
      );
    }
    return super.lerpTo(b, t);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SquircleBorder &&
          other.side == side &&
          other.radius == radius &&
          other.smoothing == smoothing;

  @override
  int get hashCode => Object.hash(side, radius, smoothing);

  @override
  String toString() =>
      'SquircleBorder(radius: $radius, smoothing: $smoothing, side: $side)';
}
