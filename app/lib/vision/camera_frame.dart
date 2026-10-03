import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'detector.dart';

enum FrameFormat { bgra8888, yuv420 }

class FramePlane {
  final Uint8List bytes;
  final int rowStride, pixelStride;
  const FramePlane(this.bytes, this.rowStride, this.pixelStride);
}

/// An owned snapshot of one selected camera buffer, never a saved photograph.
class CameraFrame {
  final int width, height, rotation;
  final FrameFormat format;
  final List<FramePlane> planes;
  const CameraFrame({
    required this.width,
    required this.height,
    required this.format,
    required this.planes,
    this.rotation = 0,
  });
  int get uprightWidth => rotation % 180 == 0 ? width : height;
  int get uprightHeight => rotation % 180 == 0 ? height : width;
}

/// The same normalized rectangle is used for display and camera preprocessing.
class ScanGuide {
  final double left, top, width, height;
  const ScanGuide(this.left, this.top, this.width, this.height);
  factory ScanGuide.forFrame(int width, int height) {
    final h = math.min(.82, width * .92 / 3.2 / height);
    return ScanGuide(.04, (1 - h) / 2, .92, h);
  }
}

/// Android CameraX delivers unrotated sensor buffers. AVFoundation has already
/// oriented its sample buffers through AVCaptureConnection; use zero on iOS.
int androidFrameRotation(int sensorDegrees, int deviceDegrees) {
  if (![0, 90, 180, 270].contains(sensorDegrees) ||
      ![0, 90, 180, 270].contains(deviceDegrees)) {
    throw const FormatException('Unsupported camera orientation');
  }
  return (sensorDegrees - deviceDegrees + 360) % 360;
}

void validateCameraFrame(CameraFrame f) {
  if (f.width < 2 ||
      f.height < 2 ||
      f.width > 4096 ||
      f.height > 4096 ||
      ![0, 90, 180, 270].contains(f.rotation)) {
    throw const FormatException('Invalid camera frame dimensions');
  }
  if (f.planes.length != (f.format == FrameFormat.bgra8888 ? 1 : 3)) {
    throw const FormatException('Unsupported camera pixel planes');
  }
  for (var i = 0; i < f.planes.length; i++) {
    final p = f.planes[i];
    final w = i == 0 ? f.width : (f.width + 1) ~/ 2;
    final h = i == 0 ? f.height : (f.height + 1) ~/ 2;
    final channels = f.format == FrameFormat.bgra8888 ? 4 : 1;
    final last = (h - 1) * p.rowStride + (w - 1) * p.pixelStride + channels;
    if (p.pixelStride < channels ||
        p.rowStride < (w - 1) * p.pixelStride + channels ||
        p.bytes.length < last) {
      throw const FormatException('Truncated or invalid camera plane');
    }
  }
}

/// Decode only the guided row. Handles padded BGRA and independently strided
/// Y/U/V planes; nothing is written to disk or sent over a network.
img.Image cameraFrameImage(CameraFrame f, {bool guided = true}) {
  validateCameraFrame(f);
  final uw = f.uprightWidth, uh = f.uprightHeight;
  final guide = guided
      ? ScanGuide.forFrame(uw, uh)
      : const ScanGuide(0, 0, 1, 1);
  final left = (guide.left * uw).round(), top = (guide.top * uh).round();
  final w = math.max(1, math.min(uw - left, (guide.width * uw).round()));
  final h = math.max(1, math.min(uh - top, (guide.height * uh).round()));
  final crop = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final ox = x + left, oy = y + top;
      final (rx, ry) = switch (f.rotation) {
        90 => (oy, f.height - 1 - ox),
        180 => (f.width - 1 - ox, f.height - 1 - oy),
        270 => (f.width - 1 - oy, ox),
        _ => (ox, oy),
      };
      if (f.format == FrameFormat.bgra8888) {
        final p = f.planes.first,
            i = ry * f.planes.first.rowStride + rx * p.pixelStride;
        crop.setPixelRgb(x, y, p.bytes[i + 2], p.bytes[i + 1], p.bytes[i]);
      } else {
        final yp = f.planes[0], up = f.planes[1], vp = f.planes[2];
        final luma = yp.bytes[ry * yp.rowStride + rx * yp.pixelStride]
            .toDouble();
        final u =
            up.bytes[(ry ~/ 2) * up.rowStride + (rx ~/ 2) * up.pixelStride] -
            128;
        final v =
            vp.bytes[(ry ~/ 2) * vp.rowStride + (rx ~/ 2) * vp.pixelStride] -
            128;
        // BT.601 full-range assumption: the camera plugin exposes plane layout
        // but not Android DataSpace/range. Validate colour on physical devices.
        crop.setPixelRgb(
          x,
          y,
          (luma + 1.402 * v).round().clamp(0, 255),
          (luma - .344136 * u - .714136 * v).round().clamp(0, 255),
          (luma + 1.772 * u).round().clamp(0, 255),
        );
      }
    }
  }
  return crop;
}

PreparedImage prepareCameraFrame(CameraFrame f) =>
    prepareUprightImage(cameraFrameImage(f), includePreview: false);
