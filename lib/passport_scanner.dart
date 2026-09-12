import 'dart:io';

import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:mrz_parser/mrz_parser.dart';
import 'package:path_provider/path_provider.dart';
import 'src/frame_crop.dart';
import 'src/mrz_postprocess.dart';
import 'src/scan_geometry.dart';
import 'package:image/image.dart' as imglib;

export 'src/image_scan.dart';

/// Minimum interval between two consecutive [PassportScannerWidget.onNoMrzFound]
/// or [PassportScannerWidget.onParsingFailed] calls.
const _callbackThrottle = Duration(seconds: 2);

/// A full-screen camera view that reads a passport's machine-readable zone.
///
/// Frames are cropped to the outlined scan area and run through ML Kit text
/// recognition. Once [precision] consecutive frames yield the same
/// check-digit-validated MRZ, [onScanned] fires with the parsed result and a
/// JPEG of the scanned area, and scanning stops.
///
/// ```dart
/// PassportScannerWidget(
///   onScanned: (result, imagePath) => print(result.documentNumber),
/// )
/// ```
///
/// To scan a photo instead of a live camera feed, see
/// [scanPassportFromGallery] and [scanPassportImage].
class PassportScannerWidget extends StatefulWidget {
  /// Called once, when the MRZ has been read and confirmed.
  ///
  /// [imagePath] points to a JPEG of the scanned area in the temporary
  /// directory, or is `null` if the image could not be saved.
  final Function(MRZResult result, String? imagePath) onScanned;

  /// Called when MRZ-shaped lines were found but did not validate, even after
  /// look-alike arbitration. Receives the lines as fed to the parser.
  ///
  /// Throttled: called at most once every 2 seconds.
  final Function(List<String> scannedLines)? onParsingFailed;

  /// Called when an analyzed frame contains no MRZ-shaped lines.
  ///
  /// Throttled: called at most once every 2 seconds while no MRZ is visible.
  final Function()? onNoMrzFound;

  /// Number of identical, check-digit-validated reads required before
  /// [onScanned] fires. Must be at least 1.
  ///
  /// `1` accepts the first validated read; `2` (the default) waits for a
  /// second frame that yields exactly the same result, guarding against a
  /// consistently misread character that happens to pass every check digit.
  final int precision;

  /// Whether to show a button that toggles the camera torch. Defaults to
  /// `false`.
  final bool showFlashButton;

  /// Creates a passport scanner. [onScanned] is required; [precision] must be
  /// at least 1.
  const PassportScannerWidget({
    super.key,
    required this.onScanned,
    this.onParsingFailed,
    this.onNoMrzFound,
    this.precision = 2,
    this.showFlashButton = false,
  }) : assert(precision >= 1, 'precision must be at least 1');

  @override
  State<PassportScannerWidget> createState() => _PassportScannerWidgetState();
}

class _PassportScannerWidgetState extends State<PassportScannerWidget> {
  final _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  String txt = '';
  List data = [];
  Map<String, int> dataCounts = {};
  bool _isProcessingFrame = false;
  bool _hasScannedSuccessfully = false;
  bool _disposed = false;
  late final _confirmation = ConfirmationCounter(widget.precision);
  String? savedImagePath;
  DateTime? _lastNoMrz;
  DateTime? _lastParsingFailed;

  /// Returns true (and stamps [last]) when at least [_callbackThrottle] has
  /// elapsed since the previous accepted call.
  bool _throttle(DateTime? last, void Function(DateTime now) stamp) {
    final now = DateTime.now();
    if (last != null && now.difference(last) < _callbackThrottle) return false;
    stamp(now);
    return true;
  }

  void _reportNoMrz() {
    if (widget.onNoMrzFound == null) return;
    if (!_throttle(_lastNoMrz, (now) => _lastNoMrz = now)) return;
    if (mounted) widget.onNoMrzFound?.call();
  }

  void _reportParsingFailed(List<String> mrz) {
    if (widget.onParsingFailed == null) return;
    if (!_throttle(_lastParsingFailed, (now) => _lastParsingFailed = now)) {
      return;
    }
    if (mounted) widget.onParsingFailed?.call(mrz);
  }

  @override
  void dispose() {
    _disposed = true;
    // Frames arrive asynchronously; closing the recognizer while a
    // processImage call is in flight throws a platform exception. If a frame
    // is mid-flight, the finally block in _processImageMrz closes it instead.
    if (!_isProcessingFrame) _textRecognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Align(
          alignment: Alignment.center,
          child: CameraAwesomeBuilder.awesome(
            imageAnalysisConfig: AnalysisConfig(
              androidOptions: const AndroidAnalysisOptions.nv21(width: 640),
              maxFramesPerSecond: 3,
              autoStart: true,
            ),
            sensorConfig: SensorConfig.single(
              sensor: Sensor.position(SensorPosition.back),
              flashMode: FlashMode.none,
              aspectRatio: CameraAspectRatios.ratio_4_3,
            ),
            previewFit: CameraPreviewFit.fitWidth,
            middleContentBuilder: (state) => Container(),
            bottomActionsBuilder: (state) => Container(),
            topActionsBuilder: (state) => widget.showFlashButton
                ? Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: IconButton(
                          icon: Icon(
                            Icons.flashlight_on_rounded,
                            color: Colors.white,
                          ),
                          onPressed: () {
                            if (state.sensorConfig.flashMode ==
                                FlashMode.always) {
                              state.sensorConfig.setFlashMode(FlashMode.none);
                            } else {
                              state.sensorConfig.setFlashMode(FlashMode.always);
                            }
                          },
                        ),
                      ),
                    ],
                  )
                : Container(),
            theme: AwesomeTheme(
              bottomActionsBackgroundColor: Colors.transparent,
            ),
            previewDecoratorBuilder: (state, preview) => Positioned.fill(
              child: CustomPaint(
                painter: ScanAreaPainter(previewSize: preview.previewSize),
              ),
            ),
            onImageForAnalysis: (img) => _processImageMrz(img),
            saveConfig: SaveConfig.photo(),
          ),
        ),
      ],
    );
  }

  Future<void> _processImageMrz(AnalysisImage img) async {
    if (_disposed) return; // widget gone; recognizer is (or will be) closed
    if (_hasScannedSuccessfully) return; // already done
    if (_isProcessingFrame) return; // drop frame if busy

    _isProcessingFrame = true;
    try {
      // Only the scan area is recognized, so the overlay is what is scanned.
      final frame = img.cropToScanArea();
      if (frame == null) return;

      final RecognizedText recognizedText = await _textRecognizer.processImage(
        frame.toInputImage(),
      );

      final lines = extractMrzLines(recognizedText).map(cleanup).toList();

      if (lines.isEmpty) {
        _reportNoMrz();
        return;
      }

      final mrz = normalizeTd3(restoreFillers(lines));
      final result = parseWithArbitration(mrz);

      if (result == null) {
        debugPrint("MRZ lines found but failed check-digit validation");
        _reportParsingFailed(mrz);
        return;
      }

      if (!_confirmation.record(result)) {
        debugPrint(
          "MRZ SCANNED SUCCESSFULLY, BUT NEED MORE PRECISION: ${_confirmation.countOf(result)} / ${widget.precision}",
        );
        return;
      }

      debugPrint("MRZ SCANNED SUCCESSFULLY");
      _hasScannedSuccessfully = true;

      savedImagePath = await saveImageAndGetPath(frame);
      if (!mounted) return;
      widget.onScanned(result, savedImagePath);
    } finally {
      _isProcessingFrame = false;
      // dispose() ran while this frame was in flight: close the recognizer
      // now that no call is using it.
      if (_disposed) _textRecognizer.close();
    }
  }

  /// Writes [frame] — the scan area, rotated upright — as a JPEG in the
  /// temporary directory and returns its path, or `null` if that failed.
  Future<String?> saveImageAndGetPath(CroppedFrame frame) async {
    try {
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${directory.path}/passport_scan_$timestamp.jpg';
      final jpegBytes = imglib.encodeJpg(frame.toImage(), quality: 92);
      await File(filePath).writeAsBytes(jpegBytes);
      return filePath;
    } catch (e) {
      debugPrint('Error saving image: $e');
      return null;
    }
  }
}

/// Dims everything outside the scan area and outlines it.
///
/// The painter fills the whole camera widget while the preview is centred
/// inside it at [previewSize] (camerawesome's default `previewAlignment`),
/// so the scan area is computed for the preview and shifted to where the
/// preview sits. It uses [scanAreaFor], the same geometry that crops the
/// analysis frame, so the outline shows exactly what gets scanned.
class ScanAreaPainter extends CustomPainter {
  /// Size of the camera preview centred inside the painted area.
  final Size previewSize;

  /// Creates a painter for a preview of [previewSize].
  ScanAreaPainter({required this.previewSize});

  /// The scan area in this painter's coordinates.
  Rect scanRect(Size size) {
    final previewOrigin = Offset(
      (size.width - previewSize.width) / 2,
      (size.height - previewSize.height) / 2,
    );
    return scanAreaFor(previewSize).shift(previewOrigin);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final inner = Path()
      ..addRRect(
        RRect.fromRectAndRadius(scanRect(size), const Radius.circular(16)),
      );
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      inner,
    );
    canvas.drawPath(outside, Paint()..color = Colors.black38);
    canvas.drawPath(
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.white70
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant ScanAreaPainter oldDelegate) =>
      previewSize != oldDelegate.previewSize;
}
