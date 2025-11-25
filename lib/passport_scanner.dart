import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:mrz_parser/mrz_parser.dart';
import 'ml_kit_utils.dart';

class PassportScannerWidget extends StatefulWidget {
  final Function(MRZResult result) onScanned;
  final Function(List<String> scannedLines)? onParsingFailed;
  final int precision;

  const PassportScannerWidget({
    super.key,
    required this.onScanned,
    this.onParsingFailed,
    this.precision = 3,
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
            topActionsBuilder: (state) => Container(),
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
            onImageForAnalysis: (img) => _processImageBarcode(img),
            saveConfig: SaveConfig.photo(),
          ),
        ),
      ],
    );
  }

  Future _processImageBarcode(AnalysisImage img) async {
    if (_hasScannedSuccessfully) return; // already done
    if (_isProcessingFrame) return; // drop frame if busy

    _isProcessingFrame = true;
    try {
      final inputImage = img.toInputImage();
      final RecognizedText recognizedText = await _textRecognizer.processImage(
        inputImage,
      );

      if (recognizedText.blocks.isEmpty) return;

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
            widget.onScanned(result);
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
