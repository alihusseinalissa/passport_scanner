import 'dart:math' show Rectangle;
import 'dart:ui' show Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:passport_scanner/src/scan_geometry.dart';

void main() {
  group('scanAreaFor', () {
    test('is passport-shaped, centred, 90% of the width in portrait', () {
      final area = scanAreaFor(const Size(480, 640));
      expect(area.width, closeTo(432, 1e-9));
      expect(area.width / area.height, closeTo(passportAspectRatio, 1e-9));
      expect(area.center.dx, closeTo(240, 1e-9));
      expect(area.center.dy, closeTo(320, 1e-9));
    });

    test('shrinks to 90% of the height in landscape, keeping the aspect', () {
      final area = scanAreaFor(const Size(640, 200));
      expect(area.height, closeTo(180, 1e-9));
      expect(area.width / area.height, closeTo(passportAspectRatio, 1e-9));
      expect(area.center.dx, closeTo(320, 1e-9));
      expect(area.center.dy, closeTo(100, 1e-9));
    });

    test('scales with the image, so preview and frame agree', () {
      final preview = scanAreaFor(const Size(1080, 1440));
      final frame = scanAreaFor(const Size(480, 640));
      Rect norm(Rect r, Size s) => Rect.fromLTRB(
            r.left / s.width,
            r.top / s.height,
            r.right / s.width,
            r.bottom / s.height,
          );
      final a = norm(preview, const Size(1080, 1440));
      final b = norm(frame, const Size(480, 640));
      expect(a.left, closeTo(b.left, 1e-9));
      expect(a.top, closeTo(b.top, 1e-9));
      expect(a.right, closeTo(b.right, 1e-9));
      expect(a.bottom, closeTo(b.bottom, 1e-9));
    });
  });

  group('scanAreaInFrame', () {
    const landscape = Rectangle<int>(0, 0, 640, 480);

    /// Rotates a raw-frame point clockwise by [degrees] into upright space.
    ({double x, double y}) upright(
      double fx,
      double fy,
      Rectangle<int> v,
      int degrees,
    ) =>
        switch (degrees) {
          0 => (x: fx, y: fy),
          90 => (x: v.height - fy, y: fx),
          180 => (x: v.width - fx, y: v.height - fy),
          270 => (x: fy, y: v.width - fx),
          _ => throw ArgumentError(degrees),
        };

    for (final degrees in [0, 90, 180, 270]) {
      test('rotation $degrees maps the crop onto the upright scan area', () {
        final crop = scanAreaInFrame(
          visible: landscape,
          uprightDegrees: degrees,
          bounds: landscape,
        );
        final rotated = degrees == 90 || degrees == 270;
        final expected = scanAreaFor(
          rotated ? const Size(480, 640) : const Size(640, 480),
        );

        // Every crop corner lands on (within rounding of) an expected corner.
        final corners = [
          (crop.left, crop.top),
          (crop.right, crop.top),
          (crop.left, crop.bottom),
          (crop.right, crop.bottom),
        ].map((c) => upright(c.$1.toDouble(), c.$2.toDouble(), landscape, degrees));
        for (final c in corners) {
          expect(
            (c.x - expected.left).abs() < 2 || (c.x - expected.right).abs() < 2,
            isTrue,
            reason: 'x=${c.x} not near ${expected.left}/${expected.right}',
          );
          expect(
            (c.y - expected.top).abs() < 2 || (c.y - expected.bottom).abs() < 2,
            isTrue,
            reason: 'y=${c.y} not near ${expected.top}/${expected.bottom}',
          );
        }
      });
    }

    test('portrait Android frame (640×480, 90°) crops the central band', () {
      final crop = scanAreaInFrame(
        visible: landscape,
        uprightDegrees: 90,
        bounds: landscape,
      );
      // Upright 480×640: x 24..456, y ≈168..472 → frame x ≈168..472, y 24..456.
      expect(crop.left, 168);
      expect(crop.right, 472);
      expect(crop.top, 24);
      expect(crop.bottom, 456);
    });

    test('is even-aligned and inside the visible region', () {
      const visible = Rectangle<int>(3, 5, 631, 471);
      for (final degrees in [0, 90, 180, 270]) {
        final crop = scanAreaInFrame(
          visible: visible,
          uprightDegrees: degrees,
          bounds: visible,
        );
        expect(crop.left.isEven && crop.top.isEven, isTrue);
        expect(crop.width.isEven && crop.height.isEven, isTrue);
        expect(crop.width, greaterThan(0));
        expect(crop.height, greaterThan(0));
        expect(visible.containsRectangle(crop), isTrue, reason: '$degrees');
      }
    });

    test('clips to the frame when the visible region extends beyond it', () {
      // 1:1 analysis stream on a 4:3 preview, portrait: the frame spans the
      // full preview height but only 75% of its width.
      const frame = Rectangle<int>(0, 0, 1088, 1088);
      final fov = previewFieldOfView(1088, 1088);
      final crop = scanAreaInFrame(
        visible: fov,
        uprightDegrees: 90,
        bounds: frame,
      );
      expect(frame.containsRectangle(crop), isTrue);
      // The passport box (90% × 67.5% of the preview) fits inside the
      // captured band, so nothing is actually lost.
      final upright = scanAreaFor(const Size(1088, 1451));
      expect(crop.width, closeTo(upright.height, 2));
      expect(crop.height, closeTo(upright.width, 2));
      // Centred on the frame.
      expect((crop.left + crop.right) / 2, closeTo(544, 2));
      expect((crop.top + crop.bottom) / 2, closeTo(544, 2));
    });

    test('a visible region wider than the frame is clipped on both sides', () {
      const frame = Rectangle<int>(0, 0, 100, 100);
      const visible = Rectangle<int>(-200, 0, 500, 100);
      final crop = scanAreaInFrame(
        visible: visible,
        uprightDegrees: 0,
        bounds: frame,
      );
      expect(crop.left, 0);
      expect(crop.right, 100);
    });

    test('rejects other angles', () {
      expect(
        () => scanAreaInFrame(
          visible: landscape,
          uprightDegrees: 45,
          bounds: landscape,
        ),
        throwsArgumentError,
      );
    });
  });

  group('previewFieldOfView', () {
    test('a 4:3 frame is the whole field of view', () {
      expect(previewFieldOfView(640, 480), const Rectangle(0, 0, 640, 480));
      expect(previewFieldOfView(1440, 1080), const Rectangle(0, 0, 1440, 1080));
    });

    test('a 1:1 frame spans the full height and misses columns', () {
      // Galaxy S20 FE: 1088×1088 analysis next to a 1440×1080 preview.
      final fov = previewFieldOfView(1088, 1088);
      expect(fov.height, 1088);
      expect(fov.width, 1451);
      expect(fov.left, -181);
      expect(fov.top, 0);
    });

    test('a 16:9 frame spans the full width and misses rows', () {
      final fov = previewFieldOfView(1280, 720);
      expect(fov.width, 1280);
      expect(fov.height, 960);
      expect(fov.left, 0);
      expect(fov.top, -120);
    });
  });
}
