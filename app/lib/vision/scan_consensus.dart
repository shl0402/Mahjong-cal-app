import 'dart:math' as math;

import 'detector.dart';

enum ScanIssue {
  empty,
  count,
  confidence,
  arrangement,
  physical,
  collecting,
  stable,
  stale,
}

class ScanDecision {
  final ScanIssue issue;
  final int matchedFrames, expectedCount, observedCount;
  final List<Detection> detections;
  const ScanDecision(
    this.issue,
    this.matchedFrames,
    this.expectedCount,
    this.observedCount,
    this.detections,
  );
  bool get ready => issue == ScanIssue.stable;

  /// Human review can bypass confidence, motion and the multi-frame wait, but
  /// must not send missing/unknown or physically impossible tiles to the editor.
  /// Call ScanConsensus.at immediately before using this property for a tap.
  bool get canConfirmManually {
    if (issue == ScanIssue.stale ||
        detections.isEmpty ||
        detections.length != expectedCount) {
      return false;
    }
    final counts = <int, int>{};
    for (final d in detections) {
      if (d.tile < 0 ||
          d.tile >= 34 ||
          !d.confidence.isFinite ||
          d.confidence < 0 ||
          d.confidence > 1) {
        return false;
      }
      counts[d.tile] = (counts[d.tile] ?? 0) + 1;
      if (counts[d.tile]! > 4) return false;
    }
    return true;
  }

  List<int> get tiles => List.unmodifiable(detections.map((d) => d.tile));
}

/// Temporal agreement is an input-quality gate, not calibrated certainty.
/// A consistently misclassified tile can still pass. Final user review remains.
class ScanConsensus {
  /// Live UI guidance tolerates slower phones. The historical default policy
  /// remains available for reproducible benchmark replays.
  factory ScanConsensus.livePreview({required int expectedCount}) =>
      ScanConsensus(
        expectedCount: expectedCount,
        requiredFrames: 3,
        minimumSpanMs: 700,
        maximumGapMs: 3000,
        expiryMs: 4000,
      );
  final int expectedCount,
      requiredFrames,
      minimumSpanMs,
      maximumGapMs,
      expiryMs;
  final double minimumConfidence;
  List<Detection> _previous = [];
  List<Detection> _anchor = [];
  int _count = 0, _firstAt = 0, _lastAt = -1;
  ScanDecision? _decision;
  ScanConsensus({
    required this.expectedCount,
    this.requiredFrames = 5,
    this.minimumSpanMs = 1200,
    this.maximumGapMs = 1000,
    this.expiryMs = 1200,
    this.minimumConfidence = .80,
  }) {
    if (expectedCount < 2 ||
        expectedCount > 17 ||
        requiredFrames < 2 ||
        minimumSpanMs < 1 ||
        maximumGapMs < 1 ||
        expiryMs < 1 ||
        !minimumConfidence.isFinite ||
        minimumConfidence < 0 ||
        minimumConfidence > 1) {
      throw ArgumentError('Invalid stability policy');
    }
  }
  void reset() {
    _previous = [];
    _anchor = [];
    _count = 0;
    _firstAt = 0;
    _lastAt = -1;
    _decision = null;
  }

  ScanDecision get current =>
      _decision ?? ScanDecision(ScanIssue.empty, 0, expectedCount, 0, const []);
  ScanDecision at(int nowMs) {
    if (_lastAt >= 0 && (nowMs < _lastAt || nowMs - _lastAt > expiryMs)) {
      reset();
      _decision = ScanDecision(ScanIssue.stale, 0, expectedCount, 0, const []);
    }
    return current;
  }

  ScanDecision observe(List<Detection> input, int capturedAtMs) {
    if (capturedAtMs < 0 || (_lastAt >= 0 && capturedAtMs <= _lastAt)) {
      reset();
      return _set(ScanIssue.stale, const []);
    }
    final d = List<Detection>.of(input)..sort((a, b) => a.cx.compareTo(b.cx));
    final validation = _quality(d);
    if (validation != null) {
      reset();
      _lastAt = capturedAtMs;
      return _set(validation, d);
    }
    final same =
        _previous.length == d.length &&
        capturedAtMs - _lastAt <= maximumGapMs &&
        List.generate(
          d.length,
          (i) =>
              d[i].tile == _previous[i].tile &&
              d[i].redFive == _previous[i].redFive &&
              (d[i].cx - _previous[i].cx).abs() < .025 &&
              (d[i].cy - _previous[i].cy).abs() < .06 &&
              _relativeSize(d[i], _previous[i]) < .3 &&
              (d[i].cx - _anchor[i].cx).abs() < .025 &&
              (d[i].cy - _anchor[i].cy).abs() < .06 &&
              _relativeSize(d[i], _anchor[i]) < .3,
        ).every((x) => x);
    if (!same) {
      _count = 0;
      _firstAt = capturedAtMs;
      _anchor = List.unmodifiable(d);
    }
    _previous = List.unmodifiable(d);
    _lastAt = capturedAtMs;
    _count++;
    return _set(
      _count >= requiredFrames && capturedAtMs - _firstAt >= minimumSpanMs
          ? ScanIssue.stable
          : ScanIssue.collecting,
      d,
    );
  }

  double _relativeSize(Detection a, Detection b) {
    final aw = a.right - a.left,
        bw = b.right - b.left,
        ah = a.bottom - a.top,
        bh = b.bottom - b.top;
    return math.max((aw - bw).abs() / bw, (ah - bh).abs() / bh);
  }

  ScanIssue? _quality(List<Detection> d) {
    if (d.isEmpty) return ScanIssue.empty;
    if (d.length != expectedCount) return ScanIssue.count;
    if (d.any(
      (x) =>
          !x.confidence.isFinite ||
          x.confidence < minimumConfidence ||
          x.confidence > 1,
    )) {
      return ScanIssue.confidence;
    }
    final counts = <int, int>{};
    for (final x in d) {
      if (x.tile < 0 || x.tile >= 34) return ScanIssue.physical;
      counts[x.tile] = (counts[x.tile] ?? 0) + 1;
      if (counts[x.tile]! > 4) return ScanIssue.physical;
      if (![x.left, x.right, x.top, x.bottom].every((v) => v.isFinite) ||
          x.left < .005 ||
          x.right > .995 ||
          x.top < .005 ||
          x.bottom > .995 ||
          x.right - x.left < .008 ||
          x.bottom - x.top < .08) {
        return ScanIssue.arrangement;
      }
    }
    final heights = d.map((x) => x.bottom - x.top).toList()..sort();
    final median = heights[heights.length ~/ 2];
    final centers = d.map((x) => x.cy).toList()..sort();
    if (centers.last - centers.first > median * .5) {
      return ScanIssue.arrangement;
    }
    for (var i = 1; i < d.length; i++) {
      if (intersectionOverUnion(d[i - 1], d[i]) > .15) {
        return ScanIssue.arrangement;
      }
    }
    return null;
  }

  ScanDecision _set(ScanIssue issue, List<Detection> d) =>
      _decision = ScanDecision(
        issue,
        _count,
        expectedCount,
        d.length,
        List.unmodifiable(d),
      );
}
