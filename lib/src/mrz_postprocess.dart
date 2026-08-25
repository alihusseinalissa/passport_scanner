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
