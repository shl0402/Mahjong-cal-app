import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:mahjong_vision/vision/detector.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'AR42 native inference preserves all 14 identities in the licensed real-photo row',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Native real-photo regression')),
        ),
      );
      // A fixed crop of a previously inspected development photograph. The
      // expected order comes from manual annotations, not model predictions.
      // This runs actual Dart JPEG decoding/letterboxing -> native ONNX ->
      // class mapping/NMS. It is neither a live-camera nor accuracy benchmark.
      // Attribution and source hashes: assets/licenses/COMMONS-TEST-FIXTURE.txt.
      final data = await rootBundle.load(
        'assets/test_fixtures/commons-ting-row-2.jpg',
      );
      final detector = TileDetector();
      try {
        final result = await detector.scan(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
        expect(detectorModelId, 'mahjong-ar42-63b683c7');
        expect(result.width, 700);
        expect(result.height, 81);
        expect(result.detections.map((d) => d.tile), [
          30,
          27,
          28,
          12,
          13,
          14,
          0,
          1,
          2,
          23,
          25,
          12,
          12,
          24,
        ]);
        expect(result.detections.every((d) => !d.redFive), isTrue);
        expect(
          result.detections.map((d) => d.cx),
          orderedEquals(result.detections.map((d) => d.cx).toList()..sort()),
        );
        debugPrint(
          'AR42 real-photo native inference: ${result.milliseconds} ms; '
          '${result.detections.length} tiles; minimum confidence '
          '${result.detections.map((d) => d.confidence).reduce((a, b) => a < b ? a : b)}',
        );
      } finally {
        await detector.close();
      }
    },
  );

  testWidgets(
    'bundled model runs repeatedly through the native image pipeline',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Native inference smoke test')),
        ),
      );
      final blank = img.Image(width: 960, height: 480);
      img.fill(blank, color: img.ColorRgb8(114, 114, 114));
      final bytes = Uint8List.fromList(img.encodeJpg(blank));
      final detector = TileDetector();
      try {
        // This exercises real platform registration, asset loading, ONNX session
        // creation, tensor transfer, execution, output decoding, and disposal.
        // It is not an accuracy benchmark or a camera permission test.
        for (var run = 0; run < 2; run++) {
          final result = await detector.scan(bytes);
          expect(result.width, 960);
          expect(result.height, 480);
          expect(result.preview, isNotEmpty);
          expect(
            result.detections,
            isEmpty,
            reason: 'A plain gray image has no tiles.',
          );
          debugPrint('Native scan $run: ${result.milliseconds} ms');
        }
        await detector.close();
        final reopened = await detector.scan(bytes);
        expect(reopened.detections, isEmpty);
      } finally {
        await detector.close();
      }
    },
  );
}
