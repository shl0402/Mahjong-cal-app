import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_vision/vision/detector.dart';
import 'package:mahjong_vision/vision/scan_consensus.dart';

List<Detection> row({
  int count = 14,
  double confidence = .95,
  double dx = 0,
  double dy = 0,
  double width = .035,
  double height = .4,
  List<int>? tiles,
}) => [
  for (var i = 0; i < count; i++)
    Detection(
      tiles?[i] ?? i,
      confidence,
      .07 + .06 * i - width / 2 + dx,
      .5 - height / 2 + dy,
      .07 + .06 * i + width / 2 + dx,
      .5 + height / 2 + dy,
    ),
];

Detection change(
  Detection d, {
  int? tile,
  double? confidence,
  double? left,
  double? top,
  double? right,
  double? bottom,
  bool? redFive,
}) => Detection(
  tile ?? d.tile,
  confidence ?? d.confidence,
  left ?? d.left,
  top ?? d.top,
  right ?? d.right,
  bottom ?? d.bottom,
  redFive: redFive ?? d.redFive,
);

ScanDecision stable(
  ScanConsensus c, {
  int start = 0,
  List<Detection>? detections,
}) {
  var result = c.current;
  for (var i = 0; i < 5; i++) {
    result = c.observe(detections ?? row(), start + 300 * i);
  }
  return result;
}

void main() {
  group('default five-frame / 1200ms stability contract', () {
    test('empty observations and fresh instance cannot be confirmed', () {
      final c = ScanConsensus(expectedCount: 14);
      expect(c.current.issue, ScanIssue.empty);
      expect(c.current.ready, isFalse);
      for (var time = 0; time <= 3000; time += 300) {
        final d = c.observe([], time);
        expect(d.issue, ScanIssue.empty);
        expect(d.ready, isFalse);
        expect(d.matchedFrames, 0);
      }
    });
    test('four frames fail; fifth frame at exact minimum span succeeds', () {
      final c = ScanConsensus(expectedCount: 14);
      for (var i = 0; i < 4; i++) {
        final d = c.observe(row(), 300 * i);
        expect(d.issue, ScanIssue.collecting);
        expect(d.matchedFrames, i + 1);
        expect(d.ready, isFalse);
      }
      final d = c.observe(row(), 1200);
      expect(d.ready, isTrue);
      expect(d.matchedFrames, 5);
      expect(d.expectedCount, 14);
      expect(d.observedCount, 14);
      expect(d.tiles, List.generate(14, (i) => i));
    });
    test('short burst cannot satisfy dwell time merely by adding frames', () {
      final c = ScanConsensus(expectedCount: 14);
      for (var i = 0; i < 10; i++) {
        expect(c.observe(row(), i).ready, isFalse);
      }
      expect(c.observe(row(), 900).ready, isFalse);
      expect(c.observe(row(), 1199).ready, isFalse);
      expect(c.observe(row(), 1200).ready, isTrue);
    });
    test('gap at exactly 1000ms is valid; 1001ms starts a new run', () {
      for (final gap in [1000, 1001]) {
        final c = ScanConsensus(expectedCount: 14);
        for (final time in [0, 300, 600, 900]) {
          c.observe(row(), time);
        }
        final d = c.observe(row(), 900 + gap);
        expect(d.ready, gap == 1000);
        expect(d.matchedFrames, gap == 1000 ? 5 : 1);
      }
    });
    test('stable decision expires after 1200ms and after backwards clock', () {
      final c = ScanConsensus(expectedCount: 14);
      expect(stable(c).ready, isTrue);
      expect(c.at(2400).ready, isTrue);
      expect(c.at(2401).issue, ScanIssue.stale);
      expect(c.current.ready, isFalse);
      expect(c.current.tiles, isEmpty);
      expect(c.observe(row(), 2700).matchedFrames, 1);
      expect(c.at(2699).issue, ScanIssue.stale);
    });
    test(
      'repeated, negative and non-increasing timestamps break agreement',
      () {
        for (final invalid in [-1, 900, 1199, 1200]) {
          final c = ScanConsensus(expectedCount: 14);
          stable(c);
          final d = c.observe(row(), invalid);
          expect(d.issue, ScanIssue.stale);
          expect(d.ready, isFalse);
          expect(d.matchedFrames, 0);
          expect(c.observe(row(), 1500).matchedFrames, 1);
        }
      },
    );
    test('reset drops confidence history and does not retain prior tiles', () {
      final c = ScanConsensus(expectedCount: 14);
      stable(c);
      c.reset();
      expect(c.current.issue, ScanIssue.empty);
      expect(c.current.tiles, isEmpty);
      expect(c.observe(row(), 1500).matchedFrames, 1);
    });
  });
  group('physical and confidence quality gates', () {
    test('missing or extra tile breaks stable state immediately', () {
      for (final count in [0, 1, 13, 15, 17]) {
        final c = ScanConsensus(expectedCount: 14);
        stable(c);
        final d = c.observe(row(count: count), 1500);
        expect(d.issue, count == 0 ? ScanIssue.empty : ScanIssue.count);
        expect(d.ready, isFalse);
        expect(d.observedCount, count);
        expect(d.matchedFrames, 0);
        expect(c.observe(row(), 1800).matchedFrames, 1);
      }
    });
    test(
      'minimum confidence is inclusive, but invalid confidence never passes',
      () {
        expect(
          stable(
            ScanConsensus(expectedCount: 14),
            detections: row(confidence: .80),
          ).ready,
          isTrue,
        );
        for (final score in [
          .799999,
          -1,
          double.nan,
          double.infinity,
          double.negativeInfinity,
          1.00001,
        ]) {
          final c = ScanConsensus(expectedCount: 14);
          final bad = row()..[7] = change(row()[7], confidence: score.toDouble());
          expect(stable(c, detections: bad).issue, ScanIssue.confidence);
          expect(c.current.ready, isFalse);
        }
        expect(
          stable(
            ScanConsensus(expectedCount: 14),
            detections: row(confidence: 1),
          ).ready,
          isTrue,
        );
      },
    );
    test(
      'four copies remain separate; five copies and unsupported tiles fail',
      () {
        final four = [0, 0, 0, 0, ...List.generate(10, (i) => i + 1)];
        final d = stable(
          ScanConsensus(expectedCount: 14),
          detections: row(tiles: four),
        );
        expect(d.ready, isTrue);
        expect(d.tiles.where((t) => t == 0).length, 4);
        for (final tiles in [
          [0, 0, 0, 0, 0, ...List.generate(9, (i) => i + 1)],
          [-1, ...List.generate(13, (i) => i + 1)],
          [34, ...List.generate(13, (i) => i + 1)],
        ]) {
          final c = ScanConsensus(expectedCount: 14);
          expect(
            stable(c, detections: row(tiles: tiles)).issue,
            ScanIssue.physical,
          );
          expect(c.current.ready, isFalse);
        }
      },
    );
    test('tile label or red-five identity changes restart the run', () {
      for (final red in [false, true]) {
        final c = ScanConsensus(expectedCount: 14);
        stable(c);
        final changed = row();
        changed[4] = change(changed[4], tile: red ? 4 : 33, redFive: red);
        expect(c.observe(changed, 1500).matchedFrames, 1);
        expect(c.current.ready, isFalse);
        for (final time in [1800, 2100, 2400]) {
          expect(c.observe(changed, time).ready, isFalse);
        }
        expect(c.observe(changed, 2700).ready, isTrue);
        expect(c.observe(row(), 3000).matchedFrames, 1);
      }
    });
    test('input order is irrelevant, physical order and immutable result are retained', () {
      final c = ScanConsensus(expectedCount: 14);
      final input = row().reversed.toList();
      final d = stable(c, detections: input);
      expect(d.ready, isTrue);
      expect(d.tiles, List.generate(14, (i) => i));
      expect(input.first.tile, 13);
      input.clear();
      expect(d.tiles, hasLength(14));
      expect(() => d.detections.clear(), throwsUnsupportedError);
      expect(() => d.tiles.add(0), throwsUnsupportedError);
    });
  });
  group('box shape, row arrangement and motion', () {
    test('clipped, nonfinite and degenerate boxes fail', () {
      final original = row()[0];
      for (final bad in [
        change(original, left: 0),
        change(original, right: 1),
        change(original, top: 0),
        change(original, bottom: 1),
        change(original, left: double.nan),
        change(original, bottom: double.infinity),
        change(original, right: original.left),
        change(original, left: original.right + .01),
        change(original, right: original.left + .0079),
        change(original, bottom: original.top + .0799),
      ]) {
        final input = row()..[0] = bad;
        expect(
          stable(ScanConsensus(expectedCount: 14), detections: input).issue,
          ScanIssue.arrangement,
        );
      }
    });
    test('a second row or substantial overlap is rejected', () {
      final twoRows = row();
      twoRows[4] = change(twoRows[4], top: .56, bottom: .96);
      expect(
        stable(ScanConsensus(expectedCount: 14), detections: twoRows).issue,
        ScanIssue.arrangement,
      );
      final overlap = row();
      overlap[1] = change(
        overlap[1],
        left: overlap[0].left + .005,
        right: overlap[0].right + .005,
      );
      expect(
        stable(ScanConsensus(expectedCount: 14), detections: overlap).issue,
        ScanIssue.arrangement,
      );
    });
    test('large position or size changes reset an otherwise stable row', () {
      for (final moved in [
        row(dx: .04),
        row(dy: .07),
        row(width: .05),
        row(height: .55),
      ]) {
        final c = ScanConsensus(expectedCount: 14);
        stable(c);
        final d = c.observe(moved, 1500);
        expect(d.issue, ScanIssue.collecting);
        expect(d.matchedFrames, 1);
        expect(d.ready, isFalse);
      }
    });
    test('small cumulative drift cannot masquerade as a steady row', () {
      final c = ScanConsensus(expectedCount: 14);
      for (var i = 0; i < 5; i++) {
        final d = c.observe(row(dx: .02 * i), 300 * i);
        expect(
          d.ready,
          isFalse,
          reason: 'row has drifted ${.02 * i} since first frame',
        );
      }
    });
    test('200 seeded jitter, changed-label and poisoned-frame sequences', () {
      final random = Random(202610021);
      for (var run = 0; run < 200; run++) {
        final tiles = List.generate(14, (i) => (i + run) % 34);
        final c = ScanConsensus(expectedCount: 14);
        List<Detection> jittered() => row(
          tiles: tiles,
          dx: (random.nextDouble() - .5) * .003,
          dy: (random.nextDouble() - .5) * .01,
          width: .034 + random.nextDouble() * .002,
          height: .39 + random.nextDouble() * .02,
          confidence: .81 + random.nextDouble() * .18,
        )..shuffle(random);
        for (var i = 0; i < 5; i++) {
          final d = c.observe(jittered(), 300 * i);
          expect(d.ready, i == 4, reason: 'initial jitter run $run, frame $i');
        }
        final poison = jittered();
        if (run.isEven) {
          poison[0] = change(poison[0], confidence: .79);
        } else {
          poison.removeLast();
        }
        expect(c.observe(poison, 1500).ready, isFalse);
        for (var i = 0; i < 5; i++) {
          final d = c.observe(jittered(), 1800 + 300 * i);
          expect(d.ready, i == 4, reason: 'recovery run $run, frame $i');
        }
        final changed = row(tiles: [33, ...tiles.skip(1)]);
        // If the first original identity was already 33 choose another one.
        changed[0] = change(changed[0], tile: (tiles.first + 17) % 34);
        final reset = c.observe(changed, 3300);
        expect(reset.ready, isFalse);
        expect(reset.matchedFrames, 1);
        expect(c.at(4501).issue, ScanIssue.stale);
      }
    });
  });
  test('invalid policies, including NaN confidence, are rejected', () {
    for (final count in [-1, 0, 1, 18]) {
      expect(() => ScanConsensus(expectedCount: count), throwsArgumentError);
    }
    for (final c in [
      -.1,
      1.1,
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      expect(
        () => ScanConsensus(expectedCount: 14, minimumConfidence: c),
        throwsArgumentError,
      );
    }
    expect(
      () => ScanConsensus(expectedCount: 14, requiredFrames: 1),
      throwsArgumentError,
    );
    expect(
      () => ScanConsensus(expectedCount: 14, minimumSpanMs: 0),
      throwsArgumentError,
    );
    expect(
      () => ScanConsensus(expectedCount: 14, maximumGapMs: 0),
      throwsArgumentError,
    );
    expect(
      () => ScanConsensus(expectedCount: 14, expiryMs: 0),
      throwsArgumentError,
    );
  });
}
