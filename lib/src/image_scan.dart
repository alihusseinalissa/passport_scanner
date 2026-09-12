import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as imglib;
import 'package:image_picker/image_picker.dart';
import 'package:mrz_parser/mrz_parser.dart';
import 'package:path_provider/path_provider.dart';

import 'mrz_postprocess.dart';

/// Why a still-image scan produced no result.
enum PassportScanFailure {
  /// The picker was dismissed without choosing an image.
  cancelled,

  /// The file is missing, or could not be decoded and processed as an image.
  unreadableImage,

  /// Text was recognized but contained no two MRZ-shaped lines, in any of the
  /// orientations tried.
  noMrzFound,

  /// MRZ-shaped lines were found but failed check-digit validation, even after
  /// look-alike arbitration.
  invalidMrz,
}

/// Outcome of scanning a still image.
///
/// Exactly one of [result] and [failure] is non-null.
@immutable
class PassportScan {
  const PassportScan._({
    this.result,
    this.imagePath,
    this.mrzLines = const [],
    this.failure,
  });

  /// The verified MRZ, or `null` when the scan failed.
  final MRZResult? result;

  /// The image that was scanned. `null` only when the picker was cancelled.
  ///
  /// For a gallery scan this is image_picker's copy of the chosen photo, which
  /// lives in the app's cache directory.
  final String? imagePath;

  /// The MRZ-shaped lines as fed to the parser, best attempt first.
  ///
  /// Empty when no MRZ was found. Useful for diagnostics on an
  /// [PassportScanFailure.invalidMrz] result.
  final List<String> mrzLines;

  /// Why the scan produced no result, or `null` when it succeeded.
  final PassportScanFailure? failure;

  /// Whether a verified MRZ was read; equivalent to `result != null`.
  bool get isSuccess => result != null;
}

/// Orientations tried, in order, when the image as stored yields no MRZ.
///
/// A photo of a passport that is upside down or on its side is still readable
/// to a person, so it is worth a retry; ML Kit's Latin recognizer is not
/// rotation invariant.
const _fallbackAngles = [90, 270, 180];

/// Reads the MRZ from still images — a photo from the gallery, a scan on disk.
///
/// Runs the same pipeline as [PassportScannerWidget] (extract → cleanup →
/// filler restoration → position-aware normalization → parse with check-digit
/// arbitration), minus
/// the multi-frame confirmation step, which has no meaning for a single image:
/// every returned result is check-digit validated.
///
/// Holds a ML Kit recognizer, so reuse one instance to scan several images and
/// [dispose] it when done. For a one-off scan use [scanPassportFromGallery] or
/// [scanPassportImage], which manage the instance for you.
///
/// ```dart
/// final scan = await scanPassportFromGallery();
/// if (scan.isSuccess) print(scan.result!.documentNumber);
/// ```
class PassportImageScanner {
  /// Creates a scanner holding its own ML Kit recognizer; call [dispose] when
  /// done with it.
  PassportImageScanner();

  final _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  final _picker = ImagePicker();

  /// Opens the system photo picker and scans the chosen image.
  ///
  /// Returns [PassportScanFailure.cancelled] when the user backs out without
  /// picking. The picker itself asks for whatever permission the platform
  /// requires, so no permission handling is needed on the caller's side.
  Future<PassportScan> scanFromGallery({bool tryRotations = true}) async {
    final XFile? picked;
    try {
      picked = await _picker.pickImage(source: ImageSource.gallery);
    } catch (e) {
      debugPrint('Gallery pick failed: $e');
      return const PassportScan._(failure: PassportScanFailure.unreadableImage);
    }
    if (picked == null) {
      return const PassportScan._(failure: PassportScanFailure.cancelled);
    }
    return scanFile(picked.path, tryRotations: tryRotations);
  }

  /// Scans the image at [path].
  ///
  /// The image is first read as stored — ML Kit applies its EXIF orientation —
  /// and, when that yields nothing and [tryRotations] is set, again at 90°,
  /// 270° and 180°. Rotation work happens on a background isolate; the original
  /// file is never modified.
  Future<PassportScan> scanFile(String path, {bool tryRotations = true}) async {
    if (!await File(path).exists()) {
      return PassportScan._(
        imagePath: path,
        failure: PassportScanFailure.unreadableImage,
      );
    }

    try {
      final direct = await _recognize(path);
      if (direct.result != null) return _success(direct, path);

      var lines = direct.lines;
      if (tryRotations) {
        final bytes = await File(path).readAsBytes();
        for (final angle in _fallbackAngles) {
          final attempt = await _recognizeRotated(bytes, angle);
          if (attempt == null) continue;
          if (attempt.result != null) return _success(attempt, path);
          if (lines.isEmpty) lines = attempt.lines;
        }
      }

      return PassportScan._(
        imagePath: path,
        mrzLines: lines,
        failure: lines.isEmpty
            ? PassportScanFailure.noMrzFound
            : PassportScanFailure.invalidMrz,
      );
    } catch (e) {
      debugPrint('Failed to scan $path: $e');
      return PassportScan._(
        imagePath: path,
        failure: PassportScanFailure.unreadableImage,
      );
    }
  }

  /// Releases the underlying ML Kit recognizer.
  Future<void> dispose() => _textRecognizer.close();

  PassportScan _success(_Attempt attempt, String path) => PassportScan._(
    result: attempt.result,
    imagePath: path,
    mrzLines: attempt.lines,
  );

  /// Runs the full pipeline over the image file at [path].
  Future<_Attempt> _recognize(String path) async {
    final recognized = await _textRecognizer.processImage(
      InputImage.fromFilePath(path),
    );
    final lines = extractMrzLines(recognized).map(cleanup).toList();
    if (lines.isEmpty) return const _Attempt(null, []);

    final mrz = normalizeTd3(restoreFillers(lines));
    return _Attempt(parseWithArbitration(mrz), mrz);
  }

  /// Rotates [bytes] by [angle] into a temporary file and scans that.
  ///
  /// Returns `null` when the image could not be decoded — no orientation of an
  /// undecodable image will fare any better.
  Future<_Attempt?> _recognizeRotated(Uint8List bytes, int angle) async {
    final rotated = await compute(_rotateToJpeg, (bytes, angle));
    if (rotated == null) return null;

    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}/passport_rotate_'
      '${DateTime.now().microsecondsSinceEpoch}_$angle.jpg',
    );
    try {
      await file.writeAsBytes(rotated);
      return await _recognize(file.path);
    } finally {
      try {
        await file.delete();
      } catch (_) {
        // A leftover file in the cache directory is not worth failing a scan.
      }
    }
  }
}

/// One pass of the pipeline over one orientation of an image.
@immutable
class _Attempt {
  const _Attempt(this.result, this.lines);

  final MRZResult? result;
  final List<String> lines;
}

/// Decodes [request]'s bytes, applies their EXIF orientation and rotates by the
/// requested angle. Runs on a background isolate via [compute].
Uint8List? _rotateToJpeg((Uint8List, int) request) {
  final (bytes, angle) = request;
  final decoded = imglib.decodeImage(bytes);
  if (decoded == null) return null;
  final upright = imglib.bakeOrientation(decoded);
  return imglib.encodeJpg(
    imglib.copyRotate(upright, angle: angle),
    quality: 92,
  );
}

/// Picks an image from the gallery and scans it, managing the recognizer.
///
/// Convenience wrapper over [PassportImageScanner.scanFromGallery] for callers
/// that scan one image at a time.
Future<PassportScan> scanPassportFromGallery({bool tryRotations = true}) async {
  final scanner = PassportImageScanner();
  try {
    return await scanner.scanFromGallery(tryRotations: tryRotations);
  } finally {
    await scanner.dispose();
  }
}

/// Scans the image at [path], managing the recognizer.
///
/// Convenience wrapper over [PassportImageScanner.scanFile].
Future<PassportScan> scanPassportImage(
  String path, {
  bool tryRotations = true,
}) async {
  final scanner = PassportImageScanner();
  try {
    return await scanner.scanFile(path, tryRotations: tryRotations);
  } finally {
    await scanner.dispose();
  }
}
