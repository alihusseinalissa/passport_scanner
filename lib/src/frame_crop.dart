import 'dart:math' show Rectangle;
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:image/image.dart' as imglib;

import 'scan_geometry.dart';

/// A packed, unrotated cut-out of an analysis frame.
///
/// [bytes] hold [width] × [height] pixels in [format] with no row padding:
/// NV21 is the Y plane followed by the interleaved VU plane; BGRA8888 is four
/// bytes per pixel. [uprightDegrees] is the clockwise rotation that makes
/// the pixels upright.
class CroppedFrame {
  const CroppedFrame({
    required this.bytes,
    required this.width,
    required this.height,
    required this.format,
    required this.uprightDegrees,
  }) : assert(
         format == InputAnalysisImageFormat.nv21 ||
             format == InputAnalysisImageFormat.bgra8888,
       );

  final Uint8List bytes;
  final int width;
  final int height;
  final InputAnalysisImageFormat format;
  final int uprightDegrees;

  bool get _isBgra => format == InputAnalysisImageFormat.bgra8888;

  /// Bytes per row of the packed buffer.
  int get bytesPerRow => _isBgra ? width * 4 : width;

  /// Wraps the buffer for ML Kit, which rotates it by [uprightDegrees]
  /// itself.
  InputImage toInputImage() => InputImage.fromBytes(
    bytes: bytes,
    metadata: InputImageMetadata(
      size: Size(width.toDouble(), height.toDouble()),
      rotation: _inputImageRotation(uprightDegrees),
      format: _isBgra ? InputImageFormat.bgra8888 : InputImageFormat.nv21,
      bytesPerRow: bytesPerRow,
    ),
  );

  /// Decodes the buffer to RGB and rotates it upright.
  imglib.Image toImage() {
    final decoded = _isBgra
        ? bgra8888ToImage(bytes, width, height)
        : nv21ToImage(bytes, width, height);
    return uprightDegrees == 0
        ? decoded
        : imglib.copyRotate(decoded, angle: uprightDegrees);
  }
}

InputImageRotation _inputImageRotation(int degrees) => switch (degrees) {
  0 => InputImageRotation.rotation0deg,
  90 => InputImageRotation.rotation90deg,
  180 => InputImageRotation.rotation180deg,
  270 => InputImageRotation.rotation270deg,
  _ => throw ArgumentError.value(degrees, 'degrees'),
};

/// Cuts [rect] out of a packed NV21 buffer of [srcWidth] × [srcHeight].
///
/// [rect] must have even position and size (chroma is subsampled 2×2).
Uint8List cropNv21(
  Uint8List src,
  int srcWidth,
  int srcHeight,
  Rectangle<int> rect,
) {
  assert(rect.left.isEven && rect.top.isEven, 'NV21 crop origin must be even');
  assert(
    rect.width.isEven && rect.height.isEven,
    'NV21 crop size must be even',
  );
  assert(
    rect.right <= srcWidth && rect.bottom <= srcHeight,
    'crop outside frame',
  );
  assert(src.length >= srcWidth * srcHeight * 3 ~/ 2, 'NV21 buffer too short');

  final w = rect.width;
  final h = rect.height;
  final out = Uint8List(w * h * 3 ~/ 2);

  for (var y = 0; y < h; y++) {
    final srcStart = (rect.top + y) * srcWidth + rect.left;
    out.setRange(y * w, y * w + w, src, srcStart);
  }

  final srcUv = srcWidth * srcHeight;
  final dstUv = w * h;
  for (var y = 0; y < h ~/ 2; y++) {
    final srcStart = srcUv + (rect.top ~/ 2 + y) * srcWidth + rect.left;
    out.setRange(dstUv + y * w, dstUv + y * w + w, src, srcStart);
  }
  return out;
}

/// Cuts [rect] out of a BGRA8888 buffer whose rows are [srcBytesPerRow]
/// apart (iOS pads rows), returning a packed buffer.
Uint8List cropBgra8888(Uint8List src, int srcBytesPerRow, Rectangle<int> rect) {
  assert(rect.left * 4 + rect.width * 4 <= srcBytesPerRow, 'crop outside row');
  assert(src.length >= rect.bottom * srcBytesPerRow, 'BGRA buffer too short');

  final rowBytes = rect.width * 4;
  final out = Uint8List(rowBytes * rect.height);
  for (var y = 0; y < rect.height; y++) {
    final srcStart = (rect.top + y) * srcBytesPerRow + rect.left * 4;
    out.setRange(y * rowBytes, y * rowBytes + rowBytes, src, srcStart);
  }
  return out;
}

/// Decodes a packed NV21 buffer (BT.601 limited range) to RGB.
imglib.Image nv21ToImage(Uint8List bytes, int width, int height) {
  final image = imglib.Image(width: width, height: height);
  final uvOffset = width * height;
  for (var y = 0; y < height; y++) {
    final yRow = y * width;
    final uvRow = uvOffset + (y >> 1) * width;
    for (var x = 0; x < width; x++) {
      final uvIndex = uvRow + (x & ~1);
      final c = (bytes[yRow + x] - 16).clamp(0, 255);
      final e = bytes[uvIndex] - 128; // V
      final d = bytes[uvIndex + 1] - 128; // U
      final r = ((298 * c + 409 * e + 128) >> 8).clamp(0, 255);
      final g = ((298 * c - 100 * d - 208 * e + 128) >> 8).clamp(0, 255);
      final b = ((298 * c + 516 * d + 128) >> 8).clamp(0, 255);
      image.setPixelRgb(x, y, r, g, b);
    }
  }
  return image;
}

/// Decodes a packed BGRA8888 buffer to RGB.
imglib.Image bgra8888ToImage(Uint8List bytes, int width, int height) {
  final image = imglib.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    final row = y * width * 4;
    for (var x = 0; x < width; x++) {
      final i = row + x * 4;
      image.setPixelRgb(x, y, bytes[i + 2], bytes[i + 1], bytes[i]);
    }
  }
  return image;
}

extension ScanAreaCrop on AnalysisImage {
  /// Clockwise rotation, in degrees, that makes this frame upright.
  ///
  /// Android reports it directly. iOS reports the device orientation
  /// instead, and its buffers arrive in sensor (landscape) orientation, so a
  /// portrait device needs a further 90°.
  int get uprightDegrees {
    final base = switch (rotation) {
      InputAnalysisImageRotation.rotation0deg => 0,
      InputAnalysisImageRotation.rotation90deg => 90,
      InputAnalysisImageRotation.rotation180deg => 180,
      InputAnalysisImageRotation.rotation270deg => 270,
    };
    return format == InputAnalysisImageFormat.bgra8888
        ? (base + 90) % 360
        : base;
  }

  /// Cuts the scan area (see [scanAreaFor]) out of this frame, or returns
  /// `null` for formats the scanner does not handle.
  CroppedFrame? cropToScanArea() {
    final degrees = uprightDegrees;
    final rect = scanAreaInFrame(
      visible: previewFieldOfView(width, height),
      uprightDegrees: degrees,
      bounds: Rectangle<int>(0, 0, width, height),
    );
    if (rect.width == 0 || rect.height == 0) return null;
    return when<CroppedFrame?>(
      nv21: (i) => CroppedFrame(
        bytes: cropNv21(i.bytes, width, height, rect),
        width: rect.width,
        height: rect.height,
        format: InputAnalysisImageFormat.nv21,
        uprightDegrees: degrees,
      ),
      bgra8888: (i) => CroppedFrame(
        bytes: cropBgra8888(i.bytes, i.planes.first.bytesPerRow, rect),
        width: rect.width,
        height: rect.height,
        format: InputAnalysisImageFormat.bgra8888,
        uprightDegrees: degrees,
      ),
    );
  }
}
