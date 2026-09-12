import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:mrz_parser/mrz_parser.dart';

/// The MRZ alphabet as ML Kit reads it: `A–Z 0–9 <`, plus `«`, ML Kit's
/// frequent misread of `<`, which the cleanup step maps back.
final _mrzAlphabet = RegExp(r'^[A-Z0-9<«]+$');
final _filler = RegExp('[<«]');
final _alphanumeric = RegExp('[A-Z0-9]');

/// OCR slack around [td3LineLength] for a line read in full.
const _minFullLength = 40;
const _maxFullLength = 46;

/// Shortest line accepted when ML Kit has collapsed its filler runs (see
/// [restoreFillers]). Line 2 needs its 28 fixed-position characters to be
/// repairable at all; a line 1 with short names collapses to something like
/// `P<UTOLI<<WU<`, so the floor sits below both.
const _minCollapsedLength = 10;

/// Fewest letters and digits a collapsed line must carry. Rejects a run of
/// fillers that ML Kit split off the end of a line into a line of its own.
const _minCollapsedAlphanumerics = 5;

/// Whether [line] — uppercased, whitespace stripped — looks like a MRZ line.
///
/// A line in the MRZ alphabet qualifies when it is [td3LineLength] characters
/// give or take OCR slack, or when it is shorter but carries the `<` filler,
/// a character no other text on a passport page contains. The short form is
/// how ML Kit returns a line whose long filler runs it has collapsed;
/// [restoreFillers] puts them back. Requiring some letters or digits as well
/// keeps a stray run of fillers ML Kit split off on its own from qualifying.
bool isMrzShaped(String line) {
  if (!_mrzAlphabet.hasMatch(line)) return false;
  final n = line.length;
  if (n >= _minFullLength && n <= _maxFullLength) return true;
  return n >= _minCollapsedLength &&
      n < _minFullLength &&
      _filler.hasMatch(line) &&
      _alphanumeric.allMatches(line).length >= _minCollapsedAlphanumerics;
}

/// Stage 1 — line extraction.
///
/// Selects MRZ candidate lines by shape ([isMrzShaped]) across **all**
/// recognized lines, instead of assuming the MRZ is the last block ML Kit
/// returns. Returns the last two matching lines (the MRZ sits at the bottom
/// of the page), or an empty list when fewer than two candidates are found.
List<String> extractMrzLines(RecognizedText text) {
  final candidates = text.blocks
      .expand((b) => b.lines)
      .map((l) => l.text.toUpperCase().replaceAll(' ', ''))
      .where(isMrzShaped)
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

/// TD3 line 2 layout: the fixed-position fields (document number through the
/// expiry date check digit) end at 28; the personal number runs to 42 and is
/// followed by its check digit and, at 43, the composite check digit.
const _line2FixedEnd = 28;
const _personalNumberEnd = 42;
const _compositeIndex = 43;
const _emptyPersonalNumber = '<<<<<<<<<<<<<<';

/// Stage 2b — filler restoration.
///
/// ML Kit's recognizer is trained on natural text and treats a long run of
/// one character as noise: `<<<<<<<<<<<<<<<<` routinely comes back as
/// `<<<<<<<`, and characters *after* such a run are sometimes dropped with
/// it. Everything else in the read is correct, but the line is short and the
/// field positions stage 3 relies on no longer line up.
///
/// Puts the missing fillers back so each line is [td3LineLength] characters:
///
/// * **Line 1** is padded at the end — the names field is the last thing on
///   the line and always ends in fillers. Line 1 has no check digit, so a
///   filler lost from *inside* the names cannot be detected here.
/// * **Line 2** keeps its 28 fixed-position characters and grows the longest
///   filler run after them (or inserts one at position 28 when none was
///   read), which is where the personal number's fillers sit. When the
///   restored personal number is empty and both trailing check digits are
///   missing, the personal number's check digit is set to `0` — the value of
///   an empty field — but the composite stays `<` for stage 4 to fill once
///   every other correction has been applied ([completeCompositeCheckDigit]).
///
/// Lines already [td3LineLength] or longer, a line 2 shorter than its fixed
/// fields, and anything that is not a two-line MRZ are returned unchanged.
List<String> restoreFillers(List<String> mrz) {
  if (mrz.length != 2) return mrz;
  return [_restoreLine1(mrz[0]), _restoreLine2(mrz[1])];
}

String _restoreLine1(String line) =>
    line.length >= td3LineLength ? line : line.padRight(td3LineLength, '<');

String _restoreLine2(String line) {
  if (line.length >= td3LineLength || line.length < _line2FixedEnd) {
    return line;
  }
  final missing = td3LineLength - line.length;
  final tail = line.substring(_line2FixedEnd);

  // Longest filler run in the tail; a tie goes to the later run. With no run
  // at all the fillers go in front of whatever was read.
  var at = 0;
  var longest = 0;
  for (var i = 0; i < tail.length;) {
    if (tail[i] != '<') {
      i++;
      continue;
    }
    var j = i;
    while (j < tail.length && tail[j] == '<') {
      j++;
    }
    if (j - i >= longest) {
      longest = j - i;
      at = i;
    }
    i = j;
  }

  var restored =
      line.substring(0, _line2FixedEnd) +
      tail.substring(0, at) +
      '<' * missing +
      tail.substring(at);
  if (restored.substring(_line2FixedEnd, _personalNumberEnd) ==
          _emptyPersonalNumber &&
      restored[_personalNumberEnd] == '<' &&
      restored[_compositeIndex] == '<') {
    restored = restored.replaceRange(
      _personalNumberEnd,
      _personalNumberEnd + 1,
      '0',
    );
  }
  return restored;
}

/// ICAO 9303 check digit of [input]: weights 7, 3, 1 repeating over `0–9` at
/// face value, `A–Z` as 10–35 and `<` as 0, modulo 10.
int checkDigit(String input) {
  const weights = [7, 3, 1];
  var sum = 0;
  for (var i = 0; i < input.length; i++) {
    final c = input.codeUnitAt(i);
    final value = c >= 0x41 && c <= 0x5A
        ? c - 0x41 + 10
        : c >= 0x30 && c <= 0x39
        ? c - 0x30
        : 0;
    sum += value * weights[i % 3];
  }
  return sum % 10;
}

/// Fills in a composite check digit that OCR dropped, when that is safe.
///
/// Applies only when line 2 ends in `<` — [restoreFillers] leaves the
/// composite position that way when it was not read — *and* the personal
/// number is empty. Every character the composite covers is then either
/// verified by its own field check digit (document number, birth date,
/// expiry date) or a filler, so the composite adds no verification the parser
/// does not already perform, and computing it lets an otherwise fully
/// validated read succeed. A line whose personal number holds data is never
/// completed: its check digits must be read, not computed.
///
/// Meant to run on the final candidate, after stage 3 and any arbitration
/// flips, since both change the characters the composite covers.
List<String> completeCompositeCheckDigit(List<String> mrz) {
  if (mrz.length != 2) return mrz;
  final line2 = mrz[1];
  if (line2.length != td3LineLength ||
      line2[_compositeIndex] != '<' ||
      line2.substring(_line2FixedEnd, _personalNumberEnd) !=
          _emptyPersonalNumber) {
    return mrz;
  }
  final composite = checkDigit(
    line2.substring(0, 10) +
        line2.substring(13, 20) +
        line2.substring(21, _compositeIndex),
  );
  return [
    mrz[0],
    line2.replaceRange(_compositeIndex, _compositeIndex + 1, '$composite'),
  ];
}

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
const td3Line1 = [FieldSpec(0, 44, CharClass.alpha)];

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
  'O': '0',
  'Q': '0',
  'D': '0',
  'I': '1',
  'L': '1',
  'Z': '2',
  'S': '5',
  'G': '6',
  'B': '8',
};
const _toAlpha = {'0': 'O', '1': 'I', '2': 'Z', '5': 'S', '6': 'G', '8': 'B'};

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

/// Ambiguous characters in mixed fields, keyed by what they might also be.
const _mixedAlternates = {
  'O': '0',
  '0': 'O',
  'I': '1',
  '1': 'I',
  'S': '5',
  '5': 'S',
  'B': '8',
  '8': 'B',
  'Z': '2',
  '2': 'Z',
  'G': '6',
  '6': 'G',
};

/// Upper bound on the candidate search in [parseWithArbitration]: 2^5.
/// Beyond ~5 ambiguous characters it is cheaper to wait for the next frame.
const maxArbitrationCandidates = 32;

/// TD3 document number occupies positions `[0, 9)` of line 2.
const _documentNumberEnd = 9;

MRZResult? _tryParse(List<String> mrz) {
  try {
    return MRZParser.parse(completeCompositeCheckDigit(mrz));
  } on MRZException {
    return null;
  } on FormatException {
    // A date that passed its check digit but is still not a calendar date.
    return null;
  }
}

/// Stage 4 — parse, validate, and arbitrate mixed fields.
///
/// [MRZParser.parse] validates every TD3 check digit plus the composite, so a
/// successful parse is a *verified* read. When it fails, the likely culprit
/// is a look-alike confusion inside the document number — the one field
/// stage 3 cannot touch, because only its check digit can tell `O` from `0`.
///
/// Runs a bounded candidate search: every ambiguous character in the document
/// number is flipped to its alternate in all combinations, and the first
/// candidate that passes *all* check digits wins. Candidates are tried in
/// order of fewest substitutions first — OCR is more likely right than wrong
/// for any single character, so when several candidates satisfy the check
/// digit (the ICAO scheme cannot tell `O` from `0` at every position, and
/// never `G` from `6`) the one closest to what was read is the best estimate.
///
/// Returns `null` when the direct parse and every candidate fail, or when
/// there are too many ambiguous characters ([maxArbitrationCandidates]) — in
/// which case the caller should simply wait for a cleaner frame.
MRZResult? parseWithArbitration(List<String> mrz) {
  final direct = _tryParse(mrz);
  if (direct != null) return direct;

  if (mrz.length != 2 || mrz[1].length != td3LineLength) return null;

  final line2 = mrz[1];
  final ambiguous = <int>[
    for (var i = 0; i < _documentNumberEnd; i++)
      if (_mixedAlternates.containsKey(line2[i])) i,
  ];
  if (ambiguous.isEmpty || (1 << ambiguous.length) > maxArbitrationCandidates) {
    return null;
  }

  final masks = [for (var m = 1; m < (1 << ambiguous.length); m++) m]
    ..sort((a, b) {
      final byFlips = _bitCount(a).compareTo(_bitCount(b));
      return byFlips != 0 ? byFlips : a.compareTo(b);
    });

  for (final mask in masks) {
    final chars = line2.split('');
    for (var b = 0; b < ambiguous.length; b++) {
      if (mask & (1 << b) != 0) {
        final i = ambiguous[b];
        chars[i] = _mixedAlternates[chars[i]]!;
      }
    }
    final result = _tryParse([mrz[0], chars.join()]);
    if (result != null) return result;
  }
  return null;
}

int _bitCount(int v) {
  var n = 0;
  while (v != 0) {
    v &= v - 1;
    n++;
  }
  return n;
}

/// Stage 5 — confirmation.
///
/// Counts identical validated reads and reports success when one result has
/// been seen [required] times. `required: 1` accepts the first validated read;
/// `required: N` needs exactly N identical reads.
class ConfirmationCounter {
  ConfirmationCounter(this.required) : assert(required >= 1);

  final int required;
  final Map<MRZResult, int> _counts = {};

  /// Number of times [result] has been recorded so far.
  int countOf(MRZResult result) => _counts[result] ?? 0;

  /// Records one sighting of [result] and returns `true` once it has been
  /// seen [required] times.
  bool record(MRZResult result) {
    final count = countOf(result) + 1;
    _counts[result] = count;
    return count >= required;
  }

  /// Forgets every sighting.
  void reset() => _counts.clear();
}
