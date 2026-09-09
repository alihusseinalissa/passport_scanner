import 'package:mrz_parser/mrz_parser.dart';

import 'countries.dart';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `14 Mar 1991` — unambiguous for a document field, where `03/14/91` is not.
String formatDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')} '
    '${_months[date.month - 1]} '
    '${date.year}';

/// Whole years between [birthDate] and [now], clamped at 0.
int ageInYears(DateTime birthDate, {DateTime? now}) {
  final today = now ?? DateTime.now();
  var age = today.year - birthDate.year;
  final hadBirthday =
      today.month > birthDate.month ||
      (today.month == birthDate.month && today.day >= birthDate.day);
  if (!hadBirthday) age--;
  return age < 0 ? 0 : age;
}

/// Calendar days from [now] to [expiryDate]; negative once expired.
int daysUntil(DateTime expiryDate, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final from = DateTime(today.year, today.month, today.day);
  final to = DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
  return to.difference(from).inDays;
}

/// Human phrasing of the expiry distance: `Expires in 3 months`,
/// `Expired 12 days ago`, `Expires today`.
String expiryLabel(DateTime expiryDate, {DateTime? now}) {
  final days = daysUntil(expiryDate, now: now);
  if (days == 0) return 'Expires today';
  final magnitude = days.abs();
  final String amount;
  if (magnitude < 31) {
    amount = '$magnitude ${magnitude == 1 ? 'day' : 'days'}';
  } else if (magnitude < 365) {
    final months = (magnitude / 30.44).round().clamp(1, 12);
    amount = '$months ${months == 1 ? 'month' : 'months'}';
  } else {
    final years = (magnitude / 365.25).floor();
    amount = '$years ${years == 1 ? 'year' : 'years'}';
  }
  return days > 0 ? 'Expires in $amount' : 'Expired $amount ago';
}

/// ICAO document type: `P` is a passport, `P<`/`PM`/… are national variants,
/// `I`/`A`/`C` are ID cards, `V` is a visa.
String documentTypeLabel(String code) {
  final normalized = code.replaceAll('<', '').trim().toUpperCase();
  if (normalized.isEmpty) return 'Unknown';
  final label = switch (normalized[0]) {
    'P' => 'Passport',
    'V' => 'Visa',
    'I' || 'A' || 'C' => 'Identity card',
    _ => 'Travel document',
  };
  // A second letter is an issuer-defined subtype (e.g. `PD` diplomatic).
  return normalized.length > 1 ? '$label · $normalized' : label;
}

String sexLabel(Sex sex) => switch (sex) {
  Sex.male => 'Male',
  Sex.female => 'Female',
  Sex.none => 'Unspecified',
};

/// Country name for an MRZ code, falling back to the raw code when unknown.
String countryLabel(String code) => lookupCountry(code)?.name ?? code;

/// Flag emoji for an MRZ country code, or `null` when the code has no flag.
String? countryFlag(String code) => lookupCountry(code)?.flag;

/// `SURNAME, Given Names` — the way the holder line reads on the document.
String fullName(MRZResult result) {
  final given = result.givenNames.trim();
  final surname = result.surnames.trim();
  if (given.isEmpty) return surname;
  if (surname.isEmpty) return given;
  return '$surname, $given';
}

/// Up to two initials for the avatar fallback when no capture is available.
String initials(MRZResult result) {
  final letters = [
    if (result.givenNames.trim().isNotEmpty) result.givenNames.trim()[0],
    if (result.surnames.trim().isNotEmpty) result.surnames.trim()[0],
  ];
  return letters.isEmpty ? '?' : letters.join().toUpperCase();
}

/// Plain-text dump of every parsed field, for the "copy all" action.
String resultAsText(MRZResult result) {
  final lines = <String>[
    'Document type: ${documentTypeLabel(result.documentType)}',
    'Document number: ${result.documentNumber}',
    'Issuing country: ${countryLabel(result.countryCode)} '
        '(${result.countryCode})',
    'Surnames: ${result.surnames}',
    'Given names: ${result.givenNames}',
    'Nationality: ${countryLabel(result.nationalityCountryCode)} '
        '(${result.nationalityCountryCode})',
    'Sex: ${sexLabel(result.sex)}',
    'Date of birth: ${formatDate(result.birthDate)}',
    'Date of expiry: ${formatDate(result.expiryDate)}',
    if (result.personalNumber.isNotEmpty)
      'Personal number: ${result.personalNumber}',
    if (result.optionalData.isNotEmpty)
      'Optional data: ${result.optionalData}',
  ];
  return lines.join('\n');
}

extension on MRZResult {
  /// `personalNumber2` is null on TD3 and often blank elsewhere.
  String get optionalData => (personalNumber2 ?? '').trim();
}
