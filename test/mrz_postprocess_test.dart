import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:mrz_parser/mrz_parser.dart';
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

RecognizedText recognized(List<TextBlock> blocks) =>
    RecognizedText(text: blocks.map((b) => b.text).join('\n'), blocks: blocks);

/// ICAO 9303 check digit (weights 7, 3, 1; `<` counts as 0).
int checkDigit(String input) {
  const weights = [7, 3, 1];
  var sum = 0;
  for (var i = 0; i < input.length; i++) {
    final c = input.codeUnitAt(i);
    final v = c >= 65 && c <= 90
        ? c - 65 + 10
        : c >= 48 && c <= 57
        ? c - 48
        : 0;
    sum += v * weights[i % 3];
  }
  return sum % 10;
}

/// Builds a valid specimen line 2 around [documentNumber] (9 characters),
/// recomputing its check digit and the composite check digit.
String line2For(String documentNumber) {
  assert(documentNumber.length == 9);
  const birth = '7408122';
  const expiry = '1204159';
  const optional = 'ZE184226B<<<<<1';
  final head = '$documentNumber${checkDigit(documentNumber)}';
  final composite = checkDigit('$head$birth$expiry$optional');
  return '${head}UTO${birth}F$expiry$optional$composite';
}

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
      final spaced = 'P<UTO ERIKSSON<<ANNA<MARIA <<<<<<<<<<<<<<<<<<<'
          .toLowerCase();
      final text = recognized([
        block([spaced, specimenLine2]),
      ]);
      expect(extractMrzLines(text), [specimenLine1, specimenLine2]);
    });

    test('accepts lines with the « misread and OCR length slack', () {
      final withGuillemet = specimenLine2.replaceRange(
        37,
        42,
        '«««««',
      ); // fillers misread
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

  group('cleanup', () {
    test('maps « to <', () {
      final withGuillemet = specimenLine2.replaceRange(37, 42, '«««««');
      expect(cleanup(withGuillemet), specimenLine2);
    });

    test('strips whitespace and uppercases', () {
      expect(
        cleanup('p<uto eriksson<<anna<maria\t<<<<<<<<<<<<<<<<<<<'),
        specimenLine1,
      );
    });

    test('leaves a clean line untouched', () {
      expect(cleanup(specimenLine1), specimenLine1);
      expect(cleanup(specimenLine2), specimenLine2);
    });
  });

  group('normalize', () {
    test('fixes O→0 and other look-alikes in dates and check digits', () {
      // Birth date 7408122 → 74O8I22, expiry 1204159 → I2O4IS9, final 10 → IO.
      final corrupted = specimenLine2
          .replaceRange(13, 20, '74O8I22')
          .replaceRange(21, 28, 'I2O4IS9')
          .replaceRange(42, 44, 'IO');
      expect(normalize(corrupted, td3Line2), specimenLine2);
    });

    test('fixes 0→O and other look-alikes in names and country', () {
      // UTO → UT0, ERIKSSON → ER1K550N, MARIA → MAR1A.
      final corrupted = specimenLine1
          .replaceRange(2, 5, 'UT0')
          .replaceRange(5, 13, 'ER1K550N')
          .replaceRange(20, 25, 'MAR1A');
      expect(normalize(corrupted, td3Line1), specimenLine1);
    });

    test('fixes digits in nationality and sex on line 2', () {
      final corrupted = specimenLine2.replaceRange(10, 13, 'UT0');
      expect(normalize(corrupted, td3Line2), specimenLine2);
    });

    test('leaves mixed fields untouched', () {
      // Document number L898902C3 → L8989O2C3 and personal number
      // ZE184226B → ZEI84226B must survive for stage 4 to arbitrate.
      final corrupted = specimenLine2
          .replaceRange(0, 9, 'L8989O2C3')
          .replaceRange(28, 37, 'ZEI84226B');
      expect(normalize(corrupted, td3Line2), corrupted);
    });

    test('never touches the < filler', () {
      expect(normalize(specimenLine1, td3Line1), specimenLine1);
      expect(normalize(specimenLine2, td3Line2), specimenLine2);
    });

    test('tolerates lines shorter than the field map', () {
      final short = 'P<UT0ER1KSS0N';
      expect(normalize(short, td3Line1), 'P<UTOERIKSSON');
    });
  });

  group('normalizeTd3', () {
    test('applies both field tables to a 44-character pair', () {
      final l1 = specimenLine1.replaceRange(2, 5, 'UT0');
      final l2 = specimenLine2.replaceRange(13, 19, '74O812');
      expect(normalizeTd3([l1, l2]), [specimenLine1, specimenLine2]);
    });

    test('leaves lines that are not 44 characters unchanged', () {
      final short = specimenLine2.replaceRange(13, 19, '74O812').substring(1);
      final l1 = specimenLine1.replaceRange(2, 5, 'UT0');
      expect(normalizeTd3([l1, short]), [specimenLine1, short]);
    });

    test('passes through anything that is not a two-line MRZ', () {
      expect(normalizeTd3(const []), isEmpty);
      expect(normalizeTd3([specimenLine1]), [specimenLine1]);
    });
  });

  group('parseWithArbitration', () {
    test('the specimen fixture is self-consistent', () {
      expect(line2For('L898902C3'), specimenLine2);
      expect(checkDigit('L898902C3'), 6);
    });

    test('parses a clean MRZ directly', () {
      final result = parseWithArbitration([specimenLine1, specimenLine2]);
      expect(result, isNotNull);
      expect(result!.documentNumber, 'L898902C3');
      expect(result.surnames, 'ERIKSSON');
      expect(result.givenNames, 'ANNA MARIA');
    });

    test('recovers a document number with one swapped look-alike', () {
      final line2 = specimenLine2.replaceRange(0, 9, 'L8989O2C3'); // 0 → O
      expect(MRZParser.tryParse([specimenLine1, line2]), isNull);
      final result = parseWithArbitration([specimenLine1, line2]);
      expect(result?.documentNumber, 'L898902C3');
    });

    test('recovers a document number with two swapped look-alikes', () {
      final line2 = specimenLine2.replaceRange(0, 9, 'LB989O2C3'); // 8→B, 0→O
      expect(MRZParser.tryParse([specimenLine1, line2]), isNull);
      final result = parseWithArbitration([specimenLine1, line2]);
      expect(result?.documentNumber, 'L898902C3');
    });

    test('returns null when the confusion is outside the document number', () {
      // Birth date check digit corrupted to a different digit.
      final line2 = specimenLine2.replaceRange(19, 20, '3');
      expect(parseWithArbitration([specimenLine1, line2]), isNull);
    });

    test('returns null past the candidate cap', () {
      // Nine ambiguous characters → 2^9 candidates, far beyond the cap.
      final clean = line2For('000000000');
      expect(parseWithArbitration([specimenLine1, clean]), isNotNull);
      final line2 = clean.replaceRange(0, 9, 'OOOOOOOOO');
      expect(parseWithArbitration([specimenLine1, line2]), isNull);
    });

    test('recovers exactly at the candidate cap', () {
      // Five ambiguous characters (1 2 5 6 8) → 2^5 == the cap.
      expect(1 << 5, maxArbitrationCandidates);
      final clean = line2For('1234567C8');
      final line2 = clean.replaceRange(0, 9, 'I234567C8');
      expect(MRZParser.tryParse([specimenLine1, line2]), isNull);
      expect(
        parseWithArbitration([specimenLine1, line2])?.documentNumber,
        '1234567C8',
      );
    });

    test('prefers the candidate with the fewest substitutions', () {
      // Read JSB4B4EIF (1 → I). In plain bitmask order the 3-flip candidate
      // J58484EIF satisfies the check digit before the 1-flip truth does;
      // fewest-substitutions ordering must return the truth.
      final clean = line2For('JSB4B4E1F');
      final line2 = clean.replaceRange(0, 9, 'JSB4B4EIF');
      expect(
        parseWithArbitration([specimenLine1, line2])?.documentNumber,
        'JSB4B4E1F',
      );
    });

    test('returns null for input that is not a two-line TD3 MRZ', () {
      expect(parseWithArbitration(const []), isNull);
      expect(parseWithArbitration([specimenLine1]), isNull);
      expect(
        parseWithArbitration([specimenLine1, specimenLine2.substring(1)]),
        isNull,
      );
    });
  });
}
