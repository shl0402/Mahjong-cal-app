import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_vision/vision/detector.dart';
import 'package:mahjong_vision/vision/scan_consensus.dart';

void main() {
  test('replay actual tournament row timestamps with both evaluated models', () {
    final summaries = <Map<String, Object?>>[];
    for (final candidate in ['ar42', 'baseline']) {
      final report = jsonDecode(
        File('../training/vision/video_candidates/$candidate-row-results.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(
        report['reference_sha256'],
        '8b49ac8b4aa4ae5491f721c06ebe47e7e53f903a7e4e2f1588e016e4c8f4f940',
      );
      final frames = report['frames'] as List;
      expect(frames, hasLength(20));
      expect(frames.map((f) => f['rgb_sha256']).toSet(), hasLength(20));
      for (final count in [2, 5, 8, 11, 14, 17, 13]) {
        //13 is diagnostic only: the actual app's completed-hand count menu
        //offers2/5/8/11/14/17. This source row contains13, including a red5m.
        final gate = ScanConsensus(expectedCount: count);
        final issues = <String, int>{};
        int? firstAccepted;
        var lastTimestamp = -1;
        for (final frame in frames) {
          final timestamp = frame['timestamp_ms'] as int;
          expect(timestamp, greaterThan(lastTimestamp));
          lastTimestamp = timestamp;
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
          final decision = gate.observe(detections, timestamp);
          issues.update(decision.issue.name, (v) => v + 1, ifAbsent: () => 1);
          if (decision.ready) firstAccepted ??= timestamp;
        }
        expect(firstAccepted, isNull,
            reason: '$candidate must not accept this inaccurate13-tile row');
        summaries.add({
          'candidate': candidate,
          'model_sha256': report['model_sha256'],
          'expected_count': count,
          'app_count_option': count != 13,
          'first_accepted_timestamp_ms': firstAccepted,
          'issues': issues,
        });
      }
    }
    // Machine-readable evidence from the real Dart policy, not a Python copy.
    // ignore: avoid_print
    print('VIDEO_GATE_REPORT ${jsonEncode(summaries)}');
  });
}
