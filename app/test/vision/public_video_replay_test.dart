import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_vision/vision/detector.dart';
import 'package:mahjong_vision/vision/scan_consensus.dart';

void main() {
  test(
    'historical YOLO11n V2: replay 550 licensed observations through the gate',
    () {
      // Recorded predictions from distinct timestamps, not synthetic repetition of
      // one still. These predictions belong only to the explicitly pinned V2
      // model, not the current AR42 model. No AR42 video behavior is inferred.
      // This documentary is rejection diagnostics, not hand accuracy.
      final report = jsonDecode(
        File('../training/vision/reports/online/video-v2-results.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(
        report['model_sha256'],
        '2b1adbdb6f395eba7ce755f87672c8a4275d6eeae68d26c5206ae6a89f4e628a',
      );
      final frames = report['frames'] as List;
      expect(frames, hasLength(550));
      for (final count in [2, 5, 8, 11, 14, 17]) {
        final consensus = ScanConsensus(expectedCount: count);
        var previousTimestamp = -1;
        for (final frame in frames) {
          final timestamp = frame['timestamp_ms'] as int;
          expect(timestamp, greaterThan(previousTimestamp));
          previousTimestamp = timestamp;
          final detections = (frame['predictions'] as List).map((p) {
            final box = (p['box'] as List).cast<num>();
            return Detection(
              p['tile_index'] as int,
              (p['confidence'] as num).toDouble(),
              box[0].toDouble(),
              box[1].toDouble(),
              box[2].toDouble(),
              box[3].toDouble(),
              redFive: p['red_five'] as bool,
            );
          }).toList();
          expect(
            consensus.observe(detections, timestamp).ready,
            isFalse,
            reason: 'Unexpected confirmation at $timestamp ms for $count tiles',
          );
        }
      }
    },
  );
}
