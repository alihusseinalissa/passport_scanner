import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as imglib;
import 'package:passport_scanner/passport_scanner.dart';

const _line1 = 'P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<';
const _line2 = 'L898902C36UTO7408122F1204159ZE184226B<<<<<10';

/// Shapes [lines] the way the ML Kit plugin hands recognized text back: one
/// block, one line per entry. Only `text` matters to the pipeline, but every
/// key the deserializer reads has to be present.
Map<String, dynamic> _recognizedText(List<String> lines) {
  const rect = {'left': 0, 'top': 0, 'right': 100, 'bottom': 20};
  return {
    'text': lines.join('\n'),
    'blocks': [
      {
        'text': lines.join('\n'),
        'rect': rect,
        'recognizedLanguages': <String>[],
        'points': <Map<String, int>>[],
        'lines': [
          for (final line in lines)
            {
              'text': line,
              'rect': rect,
              'recognizedLanguages': <String>[],
              'points': <Map<String, int>>[],
              'elements': <Map<String, dynamic>>[],
            },
        ],
      },
    ],
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const recognizer = MethodChannel('google_mlkit_text_recognizer');
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Directory workDir;

  /// Text the fake recognizer returns, one entry per call, so a test can make
  /// the first orientation fail and a later one succeed.
  late List<List<String>> responses;
  late int calls;

  setUp(() async {
    workDir = await Directory.systemTemp.createTemp('passport_scan_test');
    responses = [];
    calls = 0;

    messenger.setMockMethodCallHandler(recognizer, (call) async {
      if (call.method != 'vision#startTextRecognizer') return null;
      final lines = calls < responses.length
          ? responses[calls]
          : const <String>[];
      calls++;
      return _recognizedText(lines);
    });
    messenger.setMockMethodCallHandler(
      pathProvider,
      (call) async => workDir.path,
    );
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(recognizer, null);
    messenger.setMockMethodCallHandler(pathProvider, null);
    await workDir.delete(recursive: true);
  });

  /// Writes a real, decodable JPEG so the rotation fallback has something to
  /// work with — its content is irrelevant, the fake recognizer decides what
  /// is "read" from it.
  Future<String> writeImage() async {
    final path = '${workDir.path}/passport.jpg';
    await File(
      path,
    ).writeAsBytes(imglib.encodeJpg(imglib.Image(width: 32, height: 32)));
    return path;
  }

  test('reads a valid MRZ from an image file', () async {
    responses = [
      [_line1, _line2],
    ];
    final scanner = PassportImageScanner();
    final path = await writeImage();

    final scan = await scanner.scanFile(path);
    await scanner.dispose();

    expect(scan.isSuccess, isTrue);
    expect(scan.failure, isNull);
    expect(scan.imagePath, path);
    expect(scan.mrzLines, [_line1, _line2]);
    expect(scan.result!.documentNumber, 'L898902C3');
    expect(scan.result!.surnames, 'ERIKSSON');
    expect(calls, 1, reason: 'a first-pass success must not rotate');
  });

  test('restores filler runs that ML Kit collapsed', () async {
    // The specimen with an empty personal number, the way ML Kit returns it:
    // long filler runs shortened and the trailing check digits lost.
    responses = [
      ['P<UTOERIKSSON<<ANNA<MARIA<<<', 'L898902C36UTO7408122F1204159<<<'],
    ];

    final scan = await scanPassportImage(await writeImage());

    expect(scan.isSuccess, isTrue);
    expect(scan.mrzLines, [
      _line1,
      'L898902C36UTO7408122F1204159<<<<<<<<<<<<<<0<',
    ]);
    expect(scan.result!.documentNumber, 'L898902C3');
    expect(scan.result!.givenNames, 'ANNA MARIA');
    expect(scan.result!.personalNumber, '');
  });

  test('corrects look-alike characters before parsing', () async {
    // O/0 and I/1 confusions in the nationality, dates and document number.
    responses = [
      [_line1, 'LB98902C36UTO74O8I22F12O4I59ZE184226B<<<<<10'],
    ];

    final scan = await scanPassportImage(await writeImage());

    expect(scan.isSuccess, isTrue);
    expect(scan.result!.documentNumber, 'L898902C3');
    expect(scan.result!.birthDate, DateTime(1974, 8, 12));
  });

  test(
    'falls back to other orientations when the image reads as-is fails',
    () async {
      responses = [
        const [], // as stored: nothing MRZ-shaped
        [_line1, _line2], // rotated 90°
      ];

      final scan = await scanPassportImage(await writeImage());

      expect(scan.isSuccess, isTrue);
      expect(calls, 2);
    },
  );

  test('reports no MRZ when nothing MRZ-shaped is recognized', () async {
    responses = [
      const ['REPUBLIC OF UTOPIA', 'PASSPORT'],
    ];

    final scan = await scanPassportImage(
      await writeImage(),
      tryRotations: false,
    );

    expect(scan.isSuccess, isFalse);
    expect(scan.failure, PassportScanFailure.noMrzFound);
    expect(scan.mrzLines, isEmpty);
    expect(calls, 1, reason: 'tryRotations: false must not rotate');
  });

  test('reports an invalid MRZ, keeping the lines for diagnostics', () async {
    // Same specimen with a corrupted composite check digit, and no look-alike
    // to arbitrate — nothing can rescue it.
    const broken = 'L898902C36UTO7408122F1204159ZE184226B<<<<<19';
    responses = [
      [_line1, broken],
    ];

    final scan = await scanPassportImage(
      await writeImage(),
      tryRotations: false,
    );

    expect(scan.isSuccess, isFalse);
    expect(scan.failure, PassportScanFailure.invalidMrz);
    expect(scan.mrzLines, [_line1, broken]);
  });

  test('reports an unreadable image for a path that does not exist', () async {
    final scan = await scanPassportImage('${workDir.path}/absent.jpg');

    expect(scan.isSuccess, isFalse);
    expect(scan.failure, PassportScanFailure.unreadableImage);
    expect(calls, 0);
  });

  test('leaves no rotated temporaries behind', () async {
    responses = [const []]; // every orientation fails
    final path = await writeImage();

    await scanPassportImage(path);

    final left = workDir.listSync().map((e) => e.path).toList();
    expect(left, [path]);
  });
}
