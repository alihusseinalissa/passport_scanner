import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

extension MLKitUtils on AnalysisImage {
  InputImage toInputImage() {
    return when(
      nv21: (image) {
        return InputImage.fromBytes(
          bytes: image.bytes,
          metadata: InputImageMetadata(
            rotation: inputImageRotationForAndroid,
            format: InputImageFormat.nv21,
            size: image.size,
            bytesPerRow: image.planes.first.bytesPerRow,
          ),
        );
      },
      bgra8888: (image) {
        final inputImageData = InputImageMetadata(
          size: size,
          rotation: inputImageRotationForIOS,
          format: inputImageFormat,
          bytesPerRow: image.planes.first.bytesPerRow,
        );

        return InputImage.fromBytes(
          bytes: image.bytes,
          metadata: inputImageData,
        );
      },
    )!;
  }

  InputImageRotation get inputImageRotationForAndroid =>
      InputImageRotation.values.byName(rotation.name);

  InputImageRotation get inputImageRotationForIOS {
    switch (rotation) {
      case InputAnalysisImageRotation.rotation0deg:
        return InputImageRotation.rotation90deg;
      case InputAnalysisImageRotation.rotation90deg:
        return InputImageRotation.rotation180deg;
      case InputAnalysisImageRotation.rotation180deg:
        return InputImageRotation.rotation270deg;
      case InputAnalysisImageRotation.rotation270deg:
        return InputImageRotation.rotation0deg;
    }
  }

  InputImageFormat get inputImageFormat {
    switch (format) {
      case InputAnalysisImageFormat.bgra8888:
        return InputImageFormat.bgra8888;
      case InputAnalysisImageFormat.nv21:
        return InputImageFormat.nv21;
      default:
        return InputImageFormat.yuv420;
    }
  }
}