import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// TD3 lines are exactly 44 characters from `A–Z 0–9 <`; allow OCR slack of a
/// few characters. `«` is ML Kit's frequent misread of `<` and is mapped back
/// in the cleanup step.
final _mrzShape = RegExp(r'^[A-Z0-9<«]{40,46}$');

/// Stage 1 — line extraction.
///
/// Selects MRZ candidate lines by shape across **all** recognized lines,
/// instead of assuming the MRZ is the last block ML Kit returns. Returns the
/// last two matching lines (the MRZ sits at the bottom of the page), or an
/// empty list when fewer than two candidates are found.
List<String> extractMrzLines(RecognizedText text) {
  final candidates = text.blocks
      .expand((b) => b.lines)
      .map((l) => l.text.toUpperCase().replaceAll(' ', ''))
      .where(_mrzShape.hasMatch)
      .toList();
  return candidates.length < 2
      ? const []
      : candidates.sublist(candidates.length - 2);
}

/// Stage 2 — cleanup.
///
/// Normalizes an extracted line to the MRZ alphabet: maps ML Kit's frequent
/// `«` misread of the `<` filler back, strips any remaining whitespace and
/// uppercases. Idempotent, so it is safe to apply to already-clean lines.
String cleanup(String line) =>
    line.replaceAll('«', '<').replaceAll(RegExp(r'\s+'), '').toUpperCase();

/// Character class a TD3 field position must belong to.
enum CharClass {
  /// `A–Z` (and the `<` filler).
  alpha,

  /// `0–9`.
  digit,

  /// Either; only a check digit can arbitrate (see stage 4).
  mixed,
}

/// A contiguous run of MRZ positions `[start, end)` sharing one [CharClass].
class FieldSpec {
  final int start;
  final int end;
  final CharClass type;
  const FieldSpec(this.start, this.end, this.type);
}

/// Length of every line in a TD3 (passport) MRZ.
const td3LineLength = 44;

/// TD3 line 1: document type, issuing country and names are all alphabetic;
/// `<` passes through untouched.
const td3Line1 = [
  FieldSpec(0, 44, CharClass.alpha),
];

/// TD3 line 2 field map (ICAO 9303 part 4).
const td3Line2 = [
  FieldSpec(0, 9, CharClass.mixed), // document number
  FieldSpec(9, 10, CharClass.digit), // check digit
  FieldSpec(10, 13, CharClass.alpha), // nationality
  FieldSpec(13, 19, CharClass.digit), // birth date YYMMDD
  FieldSpec(19, 20, CharClass.digit), // check digit
  FieldSpec(20, 21, CharClass.alpha), // sex
  FieldSpec(21, 27, CharClass.digit), // expiry date YYMMDD
  FieldSpec(27, 28, CharClass.digit), // check digit
  FieldSpec(28, 42, CharClass.mixed), // personal number
  FieldSpec(42, 43, CharClass.digit), // check digit
  FieldSpec(43, 44, CharClass.digit), // composite check digit
];

// Conservative look-alike maps — extend only with pairs observed in the field;
// each added pair slightly increases the false-fix surface.
const _toDigit = {
  'O': '0', 'Q': '0', 'D': '0',
  'I': '1', 'L': '1',
  'Z': '2', 'S': '5', 'G': '6', 'B': '8',
};
const _toAlpha = {
  '0': 'O', '1': 'I', '2': 'Z', '5': 'S', '6': 'G', '8': 'B',
};

/// Stage 3 — position-aware character substitution.
///
/// Walks [line] with the given field map and fixes ML Kit's look-alike
/// confusions according to the class each position must hold: letters become
/// digits in [CharClass.digit] fields, digits become letters in
/// [CharClass.alpha] fields, and [CharClass.mixed] fields are left alone for
/// stage 4 to arbitrate with the check digit. The `<` filler is never touched.
///
/// Positions beyond [line]'s length are ignored, and characters without a
/// mapping pass through unchanged.
String normalize(String line, List<FieldSpec> fields) {
  final chars = line.split('');
  for (final f in fields) {
    for (var i = f.start; i < f.end && i < chars.length; i++) {
      final c = chars[i];
      if (c == '<') continue;
      chars[i] = switch (f.type) {
        CharClass.digit => _toDigit[c] ?? c,
        CharClass.alpha => _toAlpha[c] ?? c,
        CharClass.mixed => c,
      };
    }
  }
  return chars.join();
}

/// Applies [normalize] with the TD3 field tables to a two-line MRZ.
///
/// The maps are only meaningful for the TD3 layout, so lines that are not
/// exactly [td3LineLength] characters are returned unchanged — a length
/// mismatch means the field boundaries cannot be trusted.
List<String> normalizeTd3(List<String> mrz) {
  if (mrz.length != 2) return mrz;
  return [
    mrz[0].length == td3LineLength ? normalize(mrz[0], td3Line1) : mrz[0],
    mrz[1].length == td3LineLength ? normalize(mrz[1], td3Line2) : mrz[1],
  ];
}
