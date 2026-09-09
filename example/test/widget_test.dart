import 'package:example/main.dart';
import 'package:example/mrz_format.dart';
import 'package:example/result_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrz_parser/mrz_parser.dart';

final _sample = MRZResult(
  documentType: 'P',
  countryCode: 'NLD',
  surnames: 'DE BRUIJN',
  givenNames: 'WILLEKE LISELOTTE',
  documentNumber: 'SPECI2014',
  nationalityCountryCode: 'NLD',
  birthDate: DateTime(1965, 3, 10),
  sex: Sex.female,
  expiryDate: DateTime(2030, 3, 9),
  personalNumber: '999999990',
);

void main() {
  testWidgets('home page starts on the empty state', (tester) async {
    await tester.pumpWidget(const PassportScannerDemoApp());

    expect(find.text('No document scanned yet'), findsOneWidget);
    expect(find.text('Scan a document'), findsOneWidget);
  });

  testWidgets('result view shows every parsed field', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ScanResultView(
              result: _sample,
              imagePath: null,
              scannedAt: DateTime(2026, 1, 1, 9, 30),
            ),
          ),
        ),
      ),
    );

    // Hero heading plus the "Given names" field row.
    expect(find.text('WILLEKE LISELOTTE'), findsNWidgets(2));
    expect(find.text('DE BRUIJN'), findsWidgets);
    expect(find.text('SPECI2014'), findsWidgets);
    expect(find.text('Netherlands'), findsNWidgets(2)); // issuer + nationality
    expect(find.text('Female'), findsOneWidget);
    expect(find.text('10 Mar 1965'), findsOneWidget);
    expect(find.text('09 Mar 2030'), findsOneWidget);
    expect(find.text('999999990'), findsOneWidget);
    expect(find.text('Passport'), findsOneWidget);
  });

  group('formatting', () {
    test('dates read unambiguously', () {
      expect(formatDate(DateTime(1991, 3, 14)), '14 Mar 1991');
    });

    test('age accounts for a birthday not yet reached', () {
      final now = DateTime(2026, 3, 13);
      expect(ageInYears(DateTime(1991, 3, 14), now: now), 34);
      expect(ageInYears(DateTime(1991, 3, 13), now: now), 35);
    });

    test('expiry label switches sides at today', () {
      final now = DateTime(2026, 1, 10);
      expect(expiryLabel(DateTime(2026, 1, 10), now: now), 'Expires today');
      expect(expiryLabel(DateTime(2026, 1, 15), now: now), 'Expires in 5 days');
      expect(expiryLabel(DateTime(2026, 1, 9), now: now), 'Expired 1 day ago');
      expect(expiryLabel(DateTime(2020, 1, 10), now: now), 'Expired 6 years ago');
    });

    test('document type resolves ICAO codes, keeping subtypes visible', () {
      expect(documentTypeLabel('P'), 'Passport');
      expect(documentTypeLabel('P<'), 'Passport');
      expect(documentTypeLabel('PD'), 'Passport · PD');
      expect(documentTypeLabel('I'), 'Identity card');
      expect(documentTypeLabel('<'), 'Unknown');
    });

    test('country codes resolve, unknown codes pass through', () {
      expect(countryLabel('NLD'), 'Netherlands');
      expect(countryLabel('D'), 'Germany');
      expect(countryFlag('NLD'), '🇳🇱');
      expect(countryLabel('ZZZ'), 'ZZZ');
      expect(countryFlag('ZZZ'), isNull);
      expect(countryFlag('XXA'), isNull); // stateless: no flag
    });

    test('copy-all text carries every populated field', () {
      final text = resultAsText(_sample);
      expect(text, contains('Document number: SPECI2014'));
      expect(text, contains('Issuing country: Netherlands (NLD)'));
      expect(text, contains('Personal number: 999999990'));
      expect(text, isNot(contains('Optional data')));
    });
  });
}
