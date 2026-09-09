# Passport Scanner

Easily scan passports to extract their information from the MRZ code.
This package reads the MRZ (Machine Readable Zone) and parses it to extract the information, either **live from the device camera** or from a **still image picked from the gallery**.
## Setup
Since this package is using [ML Kit](https://pub.dev/packages/google_mlkit_text_recognition) for text recognition, you must satisfy its requirements:
### iOS
-   Minimum iOS Deployment Target: 15.5
-   Xcode 15.3.0 or newer
-   Swift 5
-   ML Kit does not support 32-bit architectures (i386 and armv7). ML Kit does support 64-bit architectures (x86_64 and arm64). Check this  [list](https://developer.apple.com/support/required-device-capabilities/)  to see if your device has the required device capabilities. More info  [here](https://developers.google.com/ml-kit/migration/ios).

Your Podfile should look like this:

```ruby
platform :ios, '15.5'  # or newer version

...

# add this line:
$iOSVersion = '15.5'  # or newer version

post_install do |installer|
  # add these lines:
  installer.pods_project.build_configurations.each do |config|
    config.build_settings["EXCLUDED_ARCHS[sdk=*]"] = "armv7"
    config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = $iOSVersion
  end

  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)

    # add these lines:
    target.build_configurations.each do |config|
      if Gem::Version.new($iOSVersion) > Gem::Version.new(config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'])
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = $iOSVersion
      end
    end

  end
end

```

Notice that the minimum  `IPHONEOS_DEPLOYMENT_TARGET`  is 15.5, you can set it to something newer but not older.

### Android

-   minSdkVersion: 21
-   targetSdkVersion: 35
-   compileSdkVersion: 35

### Camera and photo permissions
There is **no need** to request permissions yourself; the camera and the photo picker each ask for what they need.

On iOS, add the usage descriptions to your `Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>The camera is used to scan the machine-readable zone of a passport.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Photos are read so a passport you already photographed can be scanned.</string>
```

The photo entry is only needed if you use the gallery scan.

## Usage

### Scanning with the camera
You can add the `PassportScannerWidget` to your scaffold and pass a listener to get the result data:

```dart
Scaffold(  
  appBar: AppBar(title: Text('Passport Scanner')),  
  body: PassportScannerWidget(  
    onScanned: (result) {  
      print('Scanned: ${result.documentNumber}, ${result.givenNames} ${result.surnames}');
    },  
  ),  
)
```
The data will be an `MRZResult` object, and it includes these information:
```dart
documentType
countryCode
surnames
givenNames
documentNumber
nationalityCountryCode
birthDate
sex
expiryDate
personalNumber
personalNumber2
```

### Scanning an image from the gallery
`scanPassportFromGallery()` opens the system photo picker and reads the MRZ from
whatever the user chooses — no widget, no camera:

```dart
final scan = await scanPassportFromGallery();

if (scan.isSuccess) {
  final MRZResult result = scan.result!;
  print('Scanned: ${result.documentNumber}, ${result.givenNames} ${result.surnames}');
  print('From image: ${scan.imagePath}');
} else {
  switch (scan.failure!) {
    case PassportScanFailure.cancelled:      // the picker was dismissed
    case PassportScanFailure.unreadableImage: // missing or undecodable file
    case PassportScanFailure.noMrzFound:      // no MRZ-shaped lines in the image
    case PassportScanFailure.invalidMrz:      // lines found, check digits failed
  }
}
```

Every returned result is check-digit validated, exactly like a camera scan. The
image is read as stored first, then retried at 90°, 270° and 180°, so a photo
that was taken sideways or upside down still scans; pass `tryRotations: false`
to skip those retries. On failure, `scan.mrzLines` holds the lines as they were
fed to the parser, which is useful for diagnostics.

To scan an image you already have on disk, use `scanPassportImage(path)`. When
scanning several images in a row, create one `PassportImageScanner`, call
`scanFile` / `scanFromGallery` on it and `dispose()` it when done — that reuses
a single ML Kit recognizer instead of creating one per image:

```dart
final scanner = PassportImageScanner();
for (final path in paths) {
  final scan = await scanner.scanFile(path);
  ...
}
await scanner.dispose();
```


## Support Us

This package was created inside [OpenCode](https://opencode.iq/). You can support us by liking it on Pub, starring it on GitHub, sharing ideas on how we could enhance a certain functionality, or reporting issues and creating pull requests.