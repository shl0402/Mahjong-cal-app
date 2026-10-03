import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mahjong_vision/vision/camera_frame.dart';
import 'package:mahjong_vision/vision/detector.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native camera streams buffers and can stop, dispose and reopen', (
    tester,
  ) async {
    if (kIsWeb) {
      markTestSkipped(
        'The official browser camera plugin has no frame stream.',
      );
      return;
    }
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      markTestSkipped('No camera exists on this simulator/device.');
      return;
    }
    final camera = cameras.firstWhere(
      (item) => item.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    final format = defaultTargetPlatform == TargetPlatform.iOS
        ? ImageFormatGroup.bgra8888
        : ImageFormatGroup.yuv420;
    final detector = TileDetector();
    addTearDown(detector.close);

    for (var cycle = 0; cycle < 2; cycle++) {
      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        fps: 15,
        enableAudio: false,
        imageFormatGroup: format,
      );
      try {
        await controller.initialize();
        await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
        await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: CameraPreview(controller))),
        );
        final firstFrame = Completer<CameraImage>();
        await controller.startImageStream((frame) {
          if (!firstFrame.isCompleted) firstFrame.complete(frame);
        });
        final frame = await firstFrame.future.timeout(
          const Duration(seconds: 20),
        );
        expect(frame.width, greaterThan(0));
        expect(frame.height, greaterThan(0));
        expect(frame.format.group, format);
        expect(
          frame.planes,
          hasLength(format == ImageFormatGroup.bgra8888 ? 1 : 3),
        );
        for (final plane in frame.planes) {
          expect(plane.bytes, isNotEmpty);
          expect(plane.bytesPerRow, greaterThan(0));
        }
        debugPrint(
          'Camera cycle $cycle: ${frame.width}x${frame.height}, '
          '${frame.format.group}, '
          'row strides ${frame.planes.map((plane) => plane.bytesPerRow).toList()}, '
          'pixel strides ${frame.planes.map((plane) => plane.bytesPerPixel).toList()}',
        );
        await controller.stopImageStream();
        expect(controller.value.isStreamingImages, isFalse);
        final snapshot = CameraFrame(
          width: frame.width,
          height: frame.height,
          format: format == ImageFormatGroup.bgra8888
              ? FrameFormat.bgra8888
              : FrameFormat.yuv420,
          planes: [
            for (final plane in frame.planes)
              FramePlane(
                Uint8List.fromList(plane.bytes),
                plane.bytesPerRow,
                plane.bytesPerPixel ??
                    (format == ImageFormatGroup.bgra8888 ? 4 : 1),
              ),
          ],
          rotation: defaultTargetPlatform == TargetPlatform.iOS
              ? 0
              : androidFrameRotation(camera.sensorOrientation, 0),
        );
        validateCameraFrame(snapshot);
        final result = await detector.scanFrame(snapshot);
        expect(result.width, greaterThan(0));
        expect(result.height, greaterThan(0));
        expect(
          result.preview,
          isEmpty,
          reason: 'Live analysis must not encode a photograph.',
        );
        for (final detection in result.detections) {
          expect(detection.left, inInclusiveRange(0, 1));
          expect(detection.right, inInclusiveRange(0, 1));
          expect(detection.top, inInclusiveRange(0, 1));
          expect(detection.bottom, inInclusiveRange(0, 1));
        }
        debugPrint('Camera pipeline cycle $cycle: ${result.milliseconds} ms');
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await controller.dispose();
      }
    }
  });
}
