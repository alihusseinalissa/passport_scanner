import 'dart:math' show Rectangle;
import 'dart:ui' show Offset, Rect, Size;

/// Aspect ratio (width / height) of an ICAO 9303 ID-3 passport page:
/// 125 mm × 88 mm.
const passportAspectRatio = 125 / 88;

/// Fraction of the upright image's width (and, at most, height) that the
/// scan area spans.
const scanAreaFraction = 0.9;

/// The scan area inside an upright image of [size], in that image's pixels.
///
/// A passport-shaped rectangle centred in the image that spans
/// [scanAreaFraction] of the width. If that would be taller than
/// [scanAreaFraction] of the height (a landscape preview), it is shrunk to
/// fit that height instead, keeping the passport aspect ratio.
///
/// The same function positions the overlay on the preview and the crop in
/// the analysis frame, so what the user aims at is exactly what is scanned.
Rect scanAreaFor(Size size) {
  var width = size.width * scanAreaFraction;
  var height = width / passportAspectRatio;
  final maxHeight = size.height * scanAreaFraction;
  if (height > maxHeight) {
    height = maxHeight;
    width = height * passportAspectRatio;
  }
  return Rect.fromCenter(
    center: size.center(Offset.zero),
    width: width,
    height: height,
  );
}

/// Aspect ratio (width / height) of the field of view the preview shows, in
/// sensor (landscape) orientation. The widget fixes the preview to 4:3, which
/// is the native aspect of phone camera sensors, so the preview shows the
/// sensor's full field of view.
const previewAspectRatio = 4 / 3;

/// Where a raw analysis frame of [frameWidth] × [frameHeight] sits inside
/// the field of view the preview shows, in raw frame pixels.
///
/// Android and iOS hand out analysis frames whose aspect ratio need not match
/// the preview (CameraX picked a 1:1 stream on a Galaxy S20 FE for a 4:3
/// preview). Every stream is a centred crop of the sensor's full field of
/// view, so a frame with a wider aspect than [previewAspectRatio] spans the
/// full preview width and is missing rows top and bottom; a narrower one
/// spans the full height and is missing columns left and right. The
/// returned rectangle therefore extends beyond the frame on one axis: its
/// origin is at or below zero and its size is at least the frame's.
///
/// CameraX's viewport `cropRect` is deliberately not used: camerawesome
/// displays the whole preview buffer, so that crop does not describe what
/// the user sees.
Rectangle<int> previewFieldOfView(int frameWidth, int frameHeight) {
  final frameAspect = frameWidth / frameHeight;
  if (frameAspect >= previewAspectRatio) {
    final fovHeight = (frameWidth / previewAspectRatio).round();
    return Rectangle<int>(
      0,
      -((fovHeight - frameHeight) ~/ 2),
      frameWidth,
      fovHeight,
    );
  }
  final fovWidth = (frameHeight * previewAspectRatio).round();
  return Rectangle<int>(
    -((fovWidth - frameWidth) ~/ 2),
    0,
    fovWidth,
    frameHeight,
  );
}

/// Maps the scan area back into the raw analysis frame.
///
/// [visible] is the region the preview shows, in raw frame pixels — usually
/// [previewFieldOfView], which may extend beyond the frame. [uprightDegrees]
/// is the clockwise rotation that makes the raw frame upright — the same
/// value handed to ML Kit. [bounds] is the frame itself; the result is
/// clipped to it, so if the scan area reaches outside what the analysis
/// stream captures, only the captured part is returned.
///
/// The result is aligned to even coordinates and even dimensions so it can
/// be cut out of an NV21 buffer whose chroma plane is subsampled 2×2.
Rectangle<int> scanAreaInFrame({
  required Rectangle<int> visible,
  required int uprightDegrees,
  required Rectangle<int> bounds,
}) {
  final vw = visible.width.toDouble();
  final vh = visible.height.toDouble();
  final rotated = uprightDegrees == 90 || uprightDegrees == 270;
  final upright = scanAreaFor(rotated ? Size(vh, vw) : Size(vw, vh));

  // Inverse of a clockwise rotation of the visible region by uprightDegrees.
  final (double x0, double x1, double y0, double y1) = switch (uprightDegrees) {
    0 => (upright.left, upright.right, upright.top, upright.bottom),
    90 => (upright.top, upright.bottom, vh - upright.right, vh - upright.left),
    180 => (vw - upright.right, vw - upright.left, vh - upright.bottom, vh - upright.top),
    270 => (vw - upright.bottom, vw - upright.top, upright.left, upright.right),
    _ => throw ArgumentError.value(
        uprightDegrees, 'uprightDegrees', 'must be 0, 90, 180 or 270'),
  };

  int even(double v) => v.round() & ~1;
  final maxRight = bounds.right & ~1;
  final maxBottom = bounds.bottom & ~1;
  final left = even(visible.left + x0).clamp(bounds.left, maxRight);
  final top = even(visible.top + y0).clamp(bounds.top, maxBottom);
  final right = even(visible.left + x1).clamp(left, maxRight);
  final bottom = even(visible.top + y1).clamp(top, maxBottom);
  return Rectangle<int>(left, top, right - left, bottom - top);
}
