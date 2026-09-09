# Passport Scanner

Easily scan passports to extract their information from the MRZ code.
This app uses the device camera to scan the MRZ (Machine Readable Zone) and parse it to extract the information.
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

### Camera permission
There is **no need** to ask for the camera permission; this will be done automatically.

## Usage
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


## Support Us

This package was created inside [OpenCode](https://opencode.iq/). You can support us by liking it on Pub, starring it on GitHub, sharing ideas on how we could enhance a certain functionality, or reporting issues and creating pull requests.