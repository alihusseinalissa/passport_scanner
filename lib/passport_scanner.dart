import 'dart:io';

import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:mrz_parser/mrz_parser.dart';
import 'package:path_provider/path_provider.dart';
import 'ml_kit_utils.dart';
import 'package:image/image.dart' as imglib;

class PassportScannerWidget extends StatefulWidget {
  final Function(MRZResult result, String? imagePath) onScanned;
  final Function(List<String> scannedLines)? onParsingFailed;
  final Function()? onNoMrzFound;
  final int precision;
  final bool showFlashButton;

  const PassportScannerWidget({
    super.key,
    required this.onScanned,
    this.onParsingFailed,
    this.onNoMrzFound,
    this.precision = 3,
    this.showFlashButton = false,
  });

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
  Map<MRZResult, int> results = {};
  String? savedImagePath;

  @override
  void dispose() {
    _textRecognizer.close();
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
            topActionsBuilder: (state) => widget.showFlashButton ? Row(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: IconButton(
                    icon: Icon(
                      Icons.flashlight_on_rounded,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      if (state.sensorConfig.flashMode == FlashMode.always) {
                        state.sensorConfig.setFlashMode(FlashMode.none);
                      } else {
                        state.sensorConfig.setFlashMode(FlashMode.always);
                      }
                    },
                  ),
                ),
              ],
            ) : Container(),
            theme: AwesomeTheme(
              bottomActionsBackgroundColor: Colors.transparent,
            ),
            previewDecoratorBuilder: (state, preview) {
              final scanArea = Rect.fromCenter(
                center: preview.rect.center,
                width: preview.rect.width * 0.9,
                height: preview.rect.height * 0.5,
              );
              return Positioned.fill(
                child: CustomPaint(
                  painter: BarcodeFocusAreaPainter(scanArea: scanArea.size),
                ),
              );
            },
            onImageForAnalysis: (img) => _processImageMrz(img),
            saveConfig: SaveConfig.photo(),
          ),
        ),
      ],
    );
  }

  Future _processImageMrz(AnalysisImage img) async {
    if (_hasScannedSuccessfully) return; // already done
    if (_isProcessingFrame) return; // drop frame if busy

    _isProcessingFrame = true;
    try {
      final inputImage = img.toInputImage();
      final RecognizedText recognizedText = await _textRecognizer.processImage(
        inputImage,
      );

      if (recognizedText.blocks.isEmpty) {
        widget.onNoMrzFound?.call();
      };

      final block = recognizedText.blocks.last;
      if (block.lines.length != 2) return;

      final scannedLine1 = block.lines[0].text
          .replaceAll(' ', '')
          .replaceAll('«', '<');
      final scannedLine2 = block.lines[1].text
          .replaceAll(' ', '')
          .replaceAll('«', '<');

      final mrz = [scannedLine1, scannedLine2];

      try {
        final result = MRZParser.parse(mrz);
        if (results.keys.contains(result)) {
          if (results[result]! < widget.precision) {
            results[result] = results[result]! + 1;
            debugPrint(
              "MRZ SCANNED SUCCESSFULLY, BUT NEED MORE PRECISION: ${results[result]} / $widget.precision",
            );
          } else {
            debugPrint("MRZ SCANNED SUCCESSFULLY");
            _hasScannedSuccessfully = true;

            savedImagePath = await saveImageAndGetPath(img);
            widget.onScanned(result, savedImagePath);
          }
        } else {
          results[result] = 1;
        }
      } on MRZException catch (e) {
        debugPrint(e.toString());
        widget.onParsingFailed?.call(mrz);
      }
    } finally {
      _isProcessingFrame = false;
    }
  }

  Future<String?> saveImageAndGetPath(AnalysisImage img) async {
    try {
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${directory.path}/passport_scan_$timestamp.jpg';

      // TODO: The following code is generated by AI, it must be tested and verified.
      imglib.Image? decodedImage = img.when(
        nv21: (image) {
          final int width = image.width;
          final int height = image.height;
          final bytes = image.bytes; // NV21: Y plane (W*H) then interleaved VU
          final int frameSize = width * height;
          final rgbImage = imglib.Image(width: width, height: height);
          for (int y = 0; y < height; y++) {
            final int yRow = y * width;
            final int uvRow = frameSize + (y >> 1) * width;
            for (int x = 0; x < width; x++) {
              final int yIndex = yRow + x;
              final int uvIndex = uvRow + (x & ~1);
              int Y = bytes[yIndex] & 0xff;
              int V = bytes[uvIndex] & 0xff;
              int U = bytes[uvIndex + 1] & 0xff;
              int C = Y - 16;
              if (C < 0) C = 0;
              int D = U - 128;
              int E = V - 128;
              int R = (298 * C + 409 * E + 128) >> 8;
              int G = (298 * C - 100 * D - 208 * E + 128) >> 8;
              int B = (298 * C + 516 * D + 128) >> 8;
              if (R < 0)
                R = 0;
              else if (R > 255)
                R = 255;
              if (G < 0)
                G = 0;
              else if (G > 255)
                G = 255;
              if (B < 0)
                B = 0;
              else if (B > 255)
                B = 255;
              rgbImage.setPixelRgb(x, y, R, G, B);
            }
          }
          return rgbImage;
        },
        bgra8888: (image) {
          final int width = image.width;
          final int height = image.height;
          final bytes = image.bytes;
          final rgbImage = imglib.Image(width: width, height: height);
          for (int y = 0; y < height; y++) {
            int base = y * width * 4;
            for (int x = 0; x < width; x++) {
              final int i = base + x * 4;
              final int b = bytes[i] & 0xff;
              final int g = bytes[i + 1] & 0xff;
              final int r = bytes[i + 2] & 0xff;
              rgbImage.setPixelRgb(x, y, r, g, b);
            }
          }
          return rgbImage;
        },
      );

      if (decodedImage == null) {
        debugPrint('Failed to decode image');
        return null;
      }

      decodedImage = imglib.copyRotate(decodedImage, angle: 90);

      final jpegBytes = imglib.encodeJpg(decodedImage, quality: 92);
      final file = File(filePath);
      await file.writeAsBytes(jpegBytes);
      return filePath;
    } catch (e) {
      debugPrint('Error saving image: $e');
      return null;
    }
  }
}

class BarcodeFocusAreaPainter extends CustomPainter {
  final Size scanArea;

  BarcodeFocusAreaPainter({required this.scanArea});

  @override
  void paint(Canvas canvas, Size size) {
    final clippedRect = getClippedRect(size);
    // Draw a semi-transparent overlay outside of the scan area
    canvas.drawPath(clippedRect, Paint()..color = Colors.black38);
    // canvas.drawLine(
    //   Offset(size.width / 2 - scanArea.width / 2, size.height / 2),
    //   Offset(size.width / 2 + scanArea.width / 2, size.height / 2),
    //   Paint()
    //     ..color = Colors.red
    //     ..strokeWidth = 2,
    // );
    // Add border around the scan area
    canvas.drawPath(
      getInnerRect(size),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.white70
        ..strokeWidth = 3,
    );

    // We apply the canvas transformation to the canvas so that the barcode
    // rect is drawn in the correct orientation. (Android only)
    // if (canvasTransformation != null) {
    //   canvas.save();
    //   canvas.applyTransformation(canvasTransformation!, size);
    // }
  }

  Path getInnerRect(Size size) {
    return Path()..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          (size.width - scanArea.width) / 2,
          (size.height - scanArea.height) / 3,
          scanArea.width,
          scanArea.height,
        ),
        const Radius.circular(16),
      ),
    );
  }

  Path getClippedRect(Size size) {
    final fullRect = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final innerRect = getInnerRect(size);
    // Substract innerRect from fullRect
    return Path.combine(PathOperation.difference, fullRect, innerRect);
  }

  @override
  bool shouldRepaint(covariant BarcodeFocusAreaPainter oldDelegate) {
    return scanArea != oldDelegate.scanArea;
  }
}
