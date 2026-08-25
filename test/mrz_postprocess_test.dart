import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:passport_scanner/src/mrz_postprocess.dart';

// ICAO 9303 TD3 specimen.
const specimenLine1 = 'P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<';
const specimenLine2 = 'L898902C36UTO7408122F1204159ZE184226B<<<<<10';

TextLine line(String text) => TextLine(
      text: text,
      elements: const [],
      boundingBox: Rect.zero,
      recognizedLanguages: const [],
      cornerPoints: const <Point<int>>[],
      confidence: null,
      angle: null,
    );

TextBlock block(List<String> lines) => TextBlock(
      text: lines.join('\n'),
      lines: lines.map(line).toList(),
      boundingBox: Rect.zero,
      recognizedLanguages: const [],
      cornerPoints: const <Point<int>>[],
    );

RecognizedText recognized(List<TextBlock> blocks) => RecognizedText(
      text: blocks.map((b) => b.text).join('\n'),
      blocks: blocks,
    );

void main() {
  group('extractMrzLines', () {
    test('accepts genuine TD3 lines', () {
      final text = recognized([
        block([specimenLine1, specimenLine2]),
      ]);
      expect(extractMrzLines(text), [specimenLine1, specimenLine2]);
    });

    test('rejects prose', () {
      final text = recognized([
        block([
          'PASSPORT',
          'Surname: ERIKSSON',
          'This line of prose is long enough to be forty-four characters.',
        ]),
      ]);
      expect(extractMrzLines(text), isEmpty);
    });

    test('picks MRZ lines out of a multi-block page', () {
      final text = recognized([
        block(['UTOPIA', 'PASSPORT / PASSEPORT']),
        block(['ERIKSSON', 'ANNA MARIA']),
        block([specimenLine1]),
        block([specimenLine2]),
        // ML Kit block order does not put the MRZ last on every frame.
        block(['12 AUG 1974']),
      ]);
      expect(extractMrzLines(text), [specimenLine1, specimenLine2]);
    });

    test('returns empty when only one MRZ-shaped line is found', () {
      final text = recognized([
        block([specimenLine1]),
      ]);
      expect(extractMrzLines(text), isEmpty);
    });

    test('returns empty when there are no blocks', () {
      expect(extractMrzLines(recognized([])), isEmpty);
    });

    test('strips spaces and uppercases before matching', () {
      final spaced =
          'P<UTO ERIKSSON<<ANNA<MARIA <<<<<<<<<<<<<<<<<<<'.toLowerCase();
      final text = recognized([
        block([spaced, specimenLine2]),
      ]);
      expect(extractMrzLines(text), [specimenLine1, specimenLine2]);
    });

    test('accepts lines with the « misread and OCR length slack', () {
      final withGuillemet =
          specimenLine2.replaceRange(37, 42, '«««««'); // fillers misread
      final shortLine = specimenLine1.substring(0, 42); // 42 chars, in slack
      final text = recognized([
        block([shortLine, withGuillemet]),
      ]);
      expect(extractMrzLines(text), [shortLine, withGuillemet]);
    });

    test('keeps the last two candidates when more than two match', () {
      final stale = 'X<UTOOLDLINE<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<';
      final text = recognized([
        block([stale]),
        block([specimenLine1, specimenLine2]),
      ]);
      expect(extractMrzLines(text), [specimenLine1, specimenLine2]);
    });
  });
}
