## 1.0.0 (unreleased)

* Added still-image scanning: `scanPassportFromGallery()` opens the system photo
  picker, `scanPassportImage(path)` reads an image already on disk, and
  `PassportImageScanner` scans several images with one ML Kit recognizer. Both
  return a `PassportScan` carrying either a check-digit validated `MRZResult` or
  a `PassportScanFailure`. An image that yields nothing as stored is retried at
  90°, 270° and 180°, so sideways and upside-down photos still scan.
* **Breaking:** `precision: N` now means exactly N identical reads (it previously
  required N + 1, and `precision: 1` could never succeed). The default drops from
  3 to 2 — every read is now check-digit validated, so two identical reads is a
  strong signal and scans complete faster. `precision` must be at least 1.
* MRZ lines are selected by shape across all recognized text instead of assuming
  the last ML Kit block is the MRZ.
* Look-alike characters (`O/0`, `I/1`, `S/5`, `B/8`, `Z/2`, `G/6`) are corrected
  by field position, and the document number is arbitrated with its check digit,
  so near-miss frames are recovered instead of discarded.
* `onNoMrzFound` and `onParsingFailed` are throttled to at most once every 2
  seconds; `onParsingFailed` fires only after arbitration also fails.

## 0.3.3

* Fixed image rotation for iOS

## 0.3.2

* Bug fix

## 0.3.1

* Added onNoMrzFound

## 0.3.0

* Save the scanned image file in the cache, and return the path of the saved image
* Added a button to toggle flash

## 0.2.0 (RETRACTED)

* Enhance the UI.
* Return the path of the scanned image.

## 0.1.0

* First stable release.
* Added precision (the max number of duplicated scans before assuming that the result is correct).
* Added onParsingFailed listener.

## 0.0.3

* Updated README.md instructions for iOS and Android setup.
* Added an example app.

## 0.0.2

* Correction for pubspec.yaml.

## 0.0.1

* Initial release.
