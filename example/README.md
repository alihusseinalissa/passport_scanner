# passport_scanner example

A demo app for the `passport_scanner` package: scan a passport's machine-readable
zone — live from the camera or from a photo in the gallery — and read back every
parsed field.

## What it shows

- **Home page** — an empty state with capture tips until a scan lands, then the
  full result: the captured frame, the holder's name, validity and document
  number chips, and every MRZ field grouped into *Holder* and *Document*. Both
  entry points are offered side by side, and the footer says which one the
  result came from.
- **Gallery scan** — `scanPassportFromGallery()` opens the system photo picker
  and reads the chosen image; the app shows a reading overlay while OCR runs and
  turns each `PassportScanFailure` into a message.
- **Field details** — country codes resolved to names and flags, the date of
  birth annotated with the holder's age, the expiry date with how far away it
  is, and the ICAO document type spelled out. Tap any field to copy it; the
  toolbar copies all of them at once.
- **Scanner page** — a full-screen capture surface with a live hint that reacts
  to `onNoMrzFound` and `onParsingFailed`, plus the package's flash toggle.

## Layout

| File | Contents |
| --- | --- |
| `lib/main.dart` | App theme, home page, empty state |
| `lib/scanner_page.dart` | Full-screen `PassportScannerWidget` host |
| `lib/result_view.dart` | Result presentation — hero, sections, field tiles |
| `lib/mrz_format.dart` | Date, age, expiry, country and document-type formatting |
| `lib/countries.dart` | ICAO/ISO 3166-1 country codes → name and flag |

## Running

```sh
flutter run
```

A camera is required for the live scan, so use a physical device — the scanner
surface has nothing to read on a simulator. The gallery scan works anywhere you
can put a passport photo in the photo library.
