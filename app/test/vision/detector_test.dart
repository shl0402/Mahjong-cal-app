import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mahjong_vision/vision/detector.dart';
import 'package:mahjong_vision/vision/scan_consensus.dart';

const anchors = 8400;

PreparedImage geometry({int width = 640, int height = 640}) {
  final ratio = 640 / max(width, height);
  final w = (width * ratio).round(), h = (height * ratio).round();
  return PreparedImage(
    Float32List(0),
    Uint8List(0),
    width,
    height,
    (640 - w) ~/ 2,
    (640 - h) ~/ 2,
    w,
    h,
  );
}

Float32List output() => Float32List(46 * anchors);

void prediction(
  Float32List raw,
  int index,
  int kind, {
  double x = 320,
  double y = 320,
  double w = 100,
  double h = 160,
  double confidence = .9,
}) {
  raw[index] = x;
  raw[anchors + index] = y;
  raw[2 * anchors + index] = w;
  raw[3 * anchors + index] = h;
  raw[(kind + 4) * anchors + index] = confidence;
}

void main() {
  group('image preprocessing', () {
    test('invalid image produces a recoverable format error', () {
      expect(
        () => prepareImage(Uint8List.fromList([0, 1, 2])),
        throwsFormatException,
      );
    });

    test('RGB order, normalization, and channel-first layout are exact', () {
      final source = img.Image(width: 2, height: 2);
      img.fill(source, color: img.ColorRgb8(255, 128, 0));
      final prepared = prepareImage(Uint8List.fromList(img.encodePng(source)));
      expect(prepared.tensor.length, 3 * 640 * 640);
      expect(prepared.tensor[0], 1);
      expect(prepared.tensor[640 * 640], closeTo(128 / 255, 1e-7));
      expect(prepared.tensor[2 * 640 * 640], 0);
      expect(prepared.padX, 0);
      expect(prepared.padY, 0);
      expect(prepared.width, 2);
      expect(prepared.height, 2);
      expect(img.decodeJpg(prepared.preview), isNotNull);
    });

    test('landscape images preserve aspect ratio and gray padding', () {
      final source = img.Image(width: 4, height: 2);
      img.fill(source, color: img.ColorRgb8(255, 0, 0));
      final prepared = prepareImage(Uint8List.fromList(img.encodePng(source)));
      expect(prepared.resizedWidth, 640);
      expect(prepared.resizedHeight, 320);
      expect(prepared.padX, 0);
      expect(prepared.padY, 160);
      expect(prepared.tensor[0], closeTo(114 / 255, 1e-7));
      expect(prepared.tensor[160 * 640], 1);
      expect(prepared.tensor[480 * 640], closeTo(114 / 255, 1e-7));
    });

    test('portrait images preserve aspect ratio and horizontal padding', () {
      final source = img.Image(width: 2, height: 4);
      final prepared = prepareImage(Uint8List.fromList(img.encodePng(source)));
      expect(prepared.resizedWidth, 320);
      expect(prepared.resizedHeight, 640);
      expect(prepared.padX, 160);
      expect(prepared.padY, 0);
    });
  });

  group('ONNX output contract', () {
    test('all 42 AR metadata classes map to canonical IDs or unsupported', () {
      const expected = [
        18,
        0,
        9,
        -1,
        -1,
        19,
        1,
        10,
        -1,
        -1,
        20,
        2,
        11,
        -1,
        -1,
        21,
        3,
        12,
        -1,
        -1,
        22,
        4,
        13,
        23,
        5,
        14,
        24,
        6,
        15,
        25,
        7,
        16,
        26,
        8,
        17,
        27,
        32,
        30,
        33,
        28,
        31,
        29,
      ];
      for (var kind = 0; kind < expected.length; kind++) {
        final raw = output();
        prediction(raw, 8399, kind);
        final result = decodeDetections(raw, geometry());
        expect(result, hasLength(1), reason: 'model class $kind');
        expect(result.single.tile, expected[kind]);
        expect(result.single.redFive, isFalse);
      }
    });

    test(
      'asset contract matches pinned AR metadata and the complete class file',
      () {
        final metadata = jsonDecode(
          File('../training/vision/candidates/ar-model-manifest.json')
              .readAsStringSync(),
        );
        final names = File('../training/vision/candidates/ar-class-names.txt')
            .readAsLinesSync();
        expect(modelClassNames, names);
        expect(modelClassNames, metadata['classes']);
        expect(modelClasses, hasLength(42));
        expect(
          modelClasses.where((tile) => tile >= 0).toSet(),
          Set.from(List.generate(34, (i) => i)),
        );
        expect(modelClasses.where((tile) => tile < 0), hasLength(8));
        expect(detectorModelSha256, metadata['sha256']);
        expect(metadata['input']['shape'], [1, 3, 640, 640]);
        expect(metadata['output']['shape'], [1, 46, 8400]);
        expect(File(detectorModelAsset).lengthSync(), metadata['bytes']);
      },
    );

    test('wrong output shape fails closed', () {
      expect(() => decodeDetections([1, 2], geometry()), throwsFormatException);
      for (final length in [
        41 * anchors,
        42 * anchors,
        46 * anchors - 1,
        46 * anchors + 1,
      ]) {
        expect(
          () => decodeDetections(Float32List(length), geometry()),
          throwsFormatException,
        );
      }
    });

    test('all flower and season classes survive decoding and block stable confirmation', () {
      for (final unsupported in [3, 4, 8, 9, 13, 14, 18, 19]) {
        final raw = output();
        final kinds = [0, 1, 2, 5, unsupported];
        for (var i = 0; i < kinds.length; i++) {
          prediction(
            raw,
            i,
            kinds[i],
            x: 80.0 + i * 120,
            w: 80,
            confidence: .99,
          );
        }
        final detections = decodeDetections(raw, geometry());
        expect(detections, hasLength(5));
        expect(detections.last.tile, -1, reason: modelClassNames[unsupported]);
        final gate = ScanConsensus(expectedCount: 5);
        for (var at = 0; at <= 2000; at += 400) {
          final decision = gate.observe(detections, at);
          expect(decision.ready, isFalse);
          expect(decision.issue, ScanIssue.physical);
        }
      }
    });

    test('zero-confidence output produces no tiles', () {
      expect(decodeDetections(output(), geometry()), isEmpty);
    });

    test(
      'confidence threshold is inclusive and immediately lower is rejected',
      () {
        final raw = output();
        prediction(raw, 0, 0, x: 100, confidence: .25);
        prediction(raw, 1, 1, x: 400, confidence: .249);
        expect(decodeDetections(raw, geometry()).single.tile, 18);
      },
    );

    test('best class is chosen using class confidence without objectness', () {
      final raw = output();
      prediction(raw, 0, 0, confidence: .5);
      raw[(33 + 4) * anchors] = .95; // 9C -> 9m
      expect(decodeDetections(raw, geometry()).single.tile, 8);
    });

    test('NaN class score does not poison another finite class', () {
      final raw = output();
      prediction(raw, 0, 1);
      raw[4 * anchors] = double.nan;
      expect(decodeDetections(raw, geometry()).single.tile, 0);
    });

    test('nonfinite geometry, zero width and negative height are rejected', () {
      final raw = output();
      prediction(raw, 0, 0, x: double.nan);
      prediction(raw, 1, 0, y: double.infinity);
      prediction(raw, 2, 0, w: 0);
      prediction(raw, 3, 0, h: -2);
      expect(decodeDetections(raw, geometry()), isEmpty);
    });

    test('letterbox coordinates recover original image proportions', () {
      final raw = output();
      prediction(raw, 0, 0, x: 320, y: 320, w: 320, h: 160);
      final result = decodeDetections(
        raw,
        geometry(width: 1200, height: 600),
      ).single;
      expect(result.left, .25);
      expect(result.right, .75);
      expect(result.top, .25);
      expect(result.bottom, .75);
    });

    test(
      'outside-image boxes are clipped and entirely padded boxes discarded',
      () {
        final raw = output();
        prediction(raw, 0, 0, x: 0, y: 320, w: 100, h: 160);
        prediction(raw, 1, 1, x: 300, y: 50, w: 100, h: 100);
        final result = decodeDetections(
          raw,
          geometry(width: 1000, height: 500),
        );
        expect(result, hasLength(1));
        expect(result.single.left, 0);
        expect(result.single.right, 50 / 640);
      },
    );
  });

  group('suppression and physical tile order', () {
    test('conflicting classes on the same tile retain highest confidence', () {
      final raw = output();
      prediction(raw, 0, 0, confidence: .8);
      prediction(raw, 1, 2, confidence: .9);
      final result = decodeDetections(raw, geometry());
      expect(result, hasLength(1));
      expect(result.single.tile, 9);
    });

    test('adjacent duplicate tile faces stay as separate physical tiles', () {
      final raw = output();
      for (var i = 0; i < 4; i++) {
        prediction(raw, i, 0, x: 80 + i * 120, w: 100);
      }
      final result = decodeDetections(raw, geometry());
      expect(result.map((d) => d.tile), [18, 18, 18, 18]);
      expect(result.map((d) => d.cx), orderedEquals([.125, .3125, .5, .6875]));
    });

    test('result order is physical left-to-right, not confidence order', () {
      final raw = output();
      prediction(raw, 0, 0, x: 500, confidence: .99);
      prediction(raw, 1, 1, x: 100, confidence: .6);
      prediction(raw, 2, 2, x: 300, confidence: .8);
      expect(decodeDetections(raw, geometry()).map((d) => d.tile), [0, 9, 18]);
    });

    test('IoU handles no overlap, identity, and degenerate boxes', () {
      const a = Detection(0, .9, 0, 0, .5, .5);
      const b = Detection(0, .9, .5, .5, 1, 1);
      const empty = Detection(0, .9, 0, 0, 0, 0);
      expect(intersectionOverUnion(a, a), 1);
      expect(intersectionOverUnion(a, b), 0);
      expect(intersectionOverUnion(empty, empty), 0);
    });

    test('100 seeded random rows preserve counts, identity, and order', () {
      final rng = Random(20261002);
      for (var run = 0; run < 100; run++) {
        final raw = output();
        final kinds = List.generate(14, (_) => rng.nextInt(42));
        final anchorIds = List.generate(14, (i) => i)..shuffle(rng);
        for (var i = 0; i < kinds.length; i++) {
          prediction(
            raw,
            anchorIds[i],
            kinds[i],
            x: 20.0 + 44 * i,
            y: 320 + rng.nextDouble() * 10,
            w: 30,
            h: 50,
            confidence: .5 + rng.nextDouble() * .49,
          );
        }
        final result = decodeDetections(raw, geometry());
        expect(
          result.map((d) => d.tile),
          kinds.map((k) => modelClasses[k]),
          reason: 'seeded row $run',
        );
        expect(
          result.every(
            (d) => d.left >= 0 && d.right <= 1 && d.top >= 0 && d.bottom <= 1,
          ),
          isTrue,
        );
      }
    });
  });
}
