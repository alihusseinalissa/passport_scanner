import 'dart:math' show Rectangle;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passport_scanner/src/frame_crop.dart';
import 'package:passport_scanner/src/scan_geometry.dart';

/// Packed NV21 buffer where Y(x, y) = (x + 3y) & 0xff, and each 2×2 chroma
/// block holds V = 100 + bx, U = 200 + by (bx, by = block coordinates).
Uint8List syntheticNv21(int w, int h) {
  final out = Uint8List(w * h * 3 ~/ 2);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      out[y * w + x] = (x + 3 * y) & 0xff;
    }
  }
  final uv = w * h;
  for (var by = 0; by < h ~/ 2; by++) {
    for (var bx = 0; bx < w ~/ 2; bx++) {
      out[uv + by * w + bx * 2] = (100 + bx) & 0xff;
      out[uv + by * w + bx * 2 + 1] = (200 + by) & 0xff;
    }
  }
  return out;
}

/// BGRA buffer with [pad] spare bytes per row, pixel (x, y) = B:x G:y R:7 A:255.
Uint8List syntheticBgra(int w, int h, {int pad = 0}) {
  final stride = w * 4 + pad;
  final out = Uint8List(stride * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * stride + x * 4;
      out[i] = x;
      out[i + 1] = y;
      out[i + 2] = 7;
      out[i + 3] = 255;
    }
  }
  return out;
}

void main() {
  group('cropNv21', () {
    test('copies the Y and VU planes of the rectangle', () {
      final src = syntheticNv21(16, 8);
      const rect = Rectangle<int>(4, 2, 6, 4);
      final out = cropNv21(src, 16, 8, rect);

      expect(out.length, 6 * 4 * 3 ~/ 2);
      for (var y = 0; y < 4; y++) {
        for (var x = 0; x < 6; x++) {
          expect(out[y * 6 + x], ((4 + x) + 3 * (2 + y)) & 0xff);
        }
      }
      final uv = 6 * 4;
      for (var by = 0; by < 2; by++) {
        for (var bx = 0; bx < 3; bx++) {
          expect(out[uv + by * 6 + bx * 2], 100 + 2 + bx, reason: 'V');
          expect(out[uv + by * 6 + bx * 2 + 1], 200 + 1 + by, reason: 'U');
        }
      }
    });

    test('the full frame is an identity crop', () {
      final src = syntheticNv21(8, 6);
      expect(cropNv21(src, 8, 6, const Rectangle(0, 0, 8, 6)), src);
    });
  });

  group('cropBgra8888', () {
    test('honours the source row stride and packs the output', () {
      final src = syntheticBgra(10, 5, pad: 24);
      const rect = Rectangle<int>(3, 1, 4, 3);
      final out = cropBgra8888(src, 10 * 4 + 24, rect);

      expect(out.length, 4 * 3 * 4);
      for (var y = 0; y < 3; y++) {
        for (var x = 0; x < 4; x++) {
          final i = (y * 4 + x) * 4;
          expect(out[i], 3 + x, reason: 'B');
          expect(out[i + 1], 1 + y, reason: 'G');
          expect(out[i + 2], 7, reason: 'R');
        }
      }
    });
  });

  group('decoders', () {
    test('bgra8888ToImage swaps channels', () {
      final img = bgra8888ToImage(syntheticBgra(3, 2), 3, 2);
      final p = img.getPixel(2, 1);
      expect([p.r, p.g, p.b], [7, 1, 2]);
    });

    test('nv21ToImage maps mid grey and saturated red', () {
      // Two 2×2 blocks: left grey (Y 128, U/V 128), right red-ish.
      final bytes = Uint8List.fromList([
        128, 128, 81, 81, //
        128, 128, 81, 81, //
        128, 128, 240, 90, // VU: block 0 = (128,128), block 1 = (V 240, U 90)
      ]);
      final img = nv21ToImage(bytes, 4, 2);
      final grey = img.getPixel(0, 0);
      expect([grey.r, grey.g, grey.b], [130, 130, 130]);
      final red = img.getPixel(3, 1);
      expect(red.r, greaterThan(220));
      expect(red.g, lessThan(30));
      expect(red.b, lessThan(30));
    });
  });

  group('CroppedFrame', () {
    test('toImage rotates upright', () {
      // 4×2 frame whose blue channel is x; rotated 90° CW it becomes 2×4 and
      // the former left column (x=0) ends up along the top row.
      final frame = CroppedFrame(
        bytes: syntheticBgra(4, 2),
        width: 4,
        height: 2,
        format: InputAnalysisImageFormat.bgra8888,
        uprightDegrees: 90,
      );
      final img = frame.toImage();
      expect(img.width, 2);
      expect(img.height, 4);
      expect(img.getPixel(0, 0).b, 0); // was (x=0, y=1)
      expect(img.getPixel(1, 0).b, 0); // was (x=0, y=0)
      expect(img.getPixel(0, 3).b, 3); // was (x=3, y=1)
      expect(img.getPixel(0, 0).g, 1);
      expect(img.getPixel(1, 0).g, 0);
    });

    test('toInputImage describes a packed buffer', () {
      final frame = CroppedFrame(
        bytes: syntheticNv21(8, 4),
        width: 8,
        height: 4,
        format: InputAnalysisImageFormat.nv21,
        uprightDegrees: 270,
      );
      final input = frame.toInputImage();
      expect(input.metadata!.bytesPerRow, 8);
      expect(input.metadata!.size.width, 8);
      expect(input.metadata!.rotation.name, 'rotation270deg');
      expect(input.metadata!.format.name, 'nv21');
    });
  });

  group('AnalysisImage.cropToScanArea', () {
    test('Android NV21 uses cropRect and the reported rotation', () {
      final img = Nv21Image(
        bytes: syntheticNv21(640, 480),
        cropRect: const Rect.fromLTWH(0, 0, 640, 480),
        width: 640,
        height: 480,
        planes: const [],
        format: InputAnalysisImageFormat.nv21,
        rotation: InputAnalysisImageRotation.rotation90deg,
      );
      expect(img.uprightDegrees, 90);
      final frame = img.cropToScanArea()!;
      final expected = scanAreaInFrame(
        visible: const Rectangle(0, 0, 640, 480),
        uprightDegrees: 90,
        bounds: const Rectangle(0, 0, 640, 480),
      );
      expect(frame.width, expected.width);
      expect(frame.height, expected.height);
      expect(frame.bytes.length, frame.width * frame.height * 3 ~/ 2);
      // First Y byte is the frame's pixel at the crop origin.
      expect(frame.bytes[0], (expected.left + 3 * expected.top) & 0xff);
      final upright = frame.toImage();
      expect(upright.width, expected.height);
      expect(upright.height, expected.width);
    });

    test('a square Android stream is placed in the 4:3 field of view', () {
      final img = Nv21Image(
        bytes: syntheticNv21(1088, 1088),
        cropRect: const Rect.fromLTWH(0, 136, 1088, 816), // viewport, ignored
        width: 1088,
        height: 1088,
        planes: const [],
        format: InputAnalysisImageFormat.nv21,
        rotation: InputAnalysisImageRotation.rotation90deg,
      );
      final frame = img.cropToScanArea()!;
      final expected = scanAreaInFrame(
        visible: previewFieldOfView(1088, 1088),
        uprightDegrees: 90,
        bounds: const Rectangle(0, 0, 1088, 1088),
      );
      expect(frame.width, expected.width);
      expect(frame.height, expected.height);
      // Wider than the viewport crop would have allowed.
      expect(frame.height, greaterThan(816 * 0.9));
    });

    test('iOS BGRA adds 90° to the device orientation and reads the stride',
        () {
      const w = 64, h = 48, pad = 32;
      final img = Bgra8888Image(
        width: w,
        height: h,
        planes: [
          ImagePlane(
            bytes: syntheticBgra(w, h, pad: pad),
            bytesPerRow: w * 4 + pad,
            bytesPerPixel: 4,
            height: h,
            width: w,
          ),
        ],
        format: InputAnalysisImageFormat.bgra8888,
        rotation: InputAnalysisImageRotation.rotation0deg, // portrait device
      );
      expect(img.uprightDegrees, 90);
      final frame = img.cropToScanArea()!;
      final expected = scanAreaInFrame(
        visible: const Rectangle(0, 0, w, h),
        uprightDegrees: 90,
        bounds: const Rectangle(0, 0, w, h),
      );
      expect(frame.width, expected.width);
      expect(frame.bytesPerRow, expected.width * 4);
      // Pixel (0,0) of the crop is frame pixel (left, top): B = x, G = y.
      expect(frame.bytes[0], expected.left);
      expect(frame.bytes[1], expected.top);
      // Last pixel of the first row is still on that row (stride honoured).
      final last = (frame.width - 1) * 4;
      expect(frame.bytes[last], expected.right - 1);
      expect(frame.bytes[last + 1], expected.top);
    });
  });
}
