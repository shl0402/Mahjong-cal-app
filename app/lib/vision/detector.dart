import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

import 'camera_frame.dart';

// Experimental local-test model; publisher redistribution grant is unresolved.
// Exact ONNX/class metadata: vision/candidates/ar-model-manifest.json.
const detectorModelId = 'mahjong-ar42-63b683c7';
const detectorModelAsset = 'assets/models/mahjong-ar42-63b683c7.onnx';
const detectorModelSha256 =
    '63b683c7f50e4e9c65492d53530e6722c58d2b34350480ee979fb8ba92b7fe5a';
const modelClassNames = [
  '1B',
  '1C',
  '1D',
  '1F',
  '1S',
  '2B',
  '2C',
  '2D',
  '2F',
  '2S',
  '3B',
  '3C',
  '3D',
  '3F',
  '3S',
  '4B',
  '4C',
  '4D',
  '4F',
  '4S',
  '5B',
  '5C',
  '5D',
  '6B',
  '6C',
  '6D',
  '7B',
  '7C',
  '7D',
  '8B',
  '8C',
  '8D',
  '9B',
  '9C',
  '9D',
  'EW',
  'GD',
  'NW',
  'RD',
  'SW',
  'WD',
  'WW',
];

// B=bamboo (s), C=characters (m), D=circles (p). Flower/season classes
// remain unknown (-1); retaining them prevents an unsupported row being locked.
// This model has no red-five class, so no index is interpreted as a red five.
const modelClasses = [
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

class Detection {
  final int tile;
  final double confidence, left, top, right, bottom;
  final bool redFive;
  const Detection(
    this.tile,
    this.confidence,
    this.left,
    this.top,
    this.right,
    this.bottom, {
    this.redFive = false,
  });
  double get cx => (left + right) / 2;
  double get cy => (top + bottom) / 2;
}

class ScanResult {
  final List<Detection> detections;
  final Uint8List preview;
  final int width, height, milliseconds;
  const ScanResult(
    this.detections,
    this.preview,
    this.width,
    this.height,
    this.milliseconds,
  );
}

class PreparedImage {
  final Float32List tensor;
  final Uint8List preview;
  final int width, height, padX, padY, resizedWidth, resizedHeight;
  const PreparedImage(
    this.tensor,
    this.preview,
    this.width,
    this.height,
    this.padX,
    this.padY,
    this.resizedWidth,
    this.resizedHeight,
  );
}

PreparedImage prepareImage(Uint8List bytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    throw const FormatException('無法讀取照片，請選擇 JPEG 或 PNG。');
  }
  if (decoded == null) throw const FormatException('無法讀取照片，請選擇 JPEG 或 PNG。');
  final upright = img.bakeOrientation(decoded);
  return prepareUprightImage(upright);
}

PreparedImage prepareUprightImage(
  img.Image upright, {
  bool includePreview = true,
}) {
  final scale = 640 / math.max(upright.width, upright.height);
  final w = math.max(1, (upright.width * scale).round());
  final h = math.max(1, (upright.height * scale).round());
  final small = img.copyResize(
    upright,
    width: w,
    height: h,
    interpolation: img.Interpolation.linear,
  );
  final px = (640 - w) ~/ 2, py = (640 - h) ~/ 2;
  final data = Float32List(3 * 640 * 640)
    ..fillRange(0, 3 * 640 * 640, 114 / 255);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = small.getPixel(x, y), index = (y + py) * 640 + x + px;
      data[index] = p.r / 255;
      data[640 * 640 + index] = p.g / 255;
      data[2 * 640 * 640 + index] = p.b / 255;
    }
  }
  // Preview orientation is identical to inference, independent of EXIF support.
  final preview = includePreview
      ? Uint8List.fromList(
          img.encodeJpg(
            img.copyResize(upright, width: math.min(1400, upright.width)),
            quality: 85,
          ),
        )
      : Uint8List(0);
  return PreparedImage(
    data,
    preview,
    upright.width,
    upright.height,
    px,
    py,
    w,
    h,
  );
}

double intersectionOverUnion(Detection a, Detection b) {
  final intersection =
      math.max(0, math.min(a.right, b.right) - math.max(a.left, b.left)) *
      math.max(0, math.min(a.bottom, b.bottom) - math.max(a.top, b.top));
  final area =
      (a.right - a.left) * (a.bottom - a.top) +
      (b.right - b.left) * (b.bottom - b.top) -
      intersection;
  return area > 0 ? intersection / area : 0;
}

List<Detection> decodeDetections(
  List<num> raw,
  PreparedImage input, {
  double threshold = .25,
  double nmsThreshold = .45,
}) {
  const anchors = 8400;
  if (raw.length != (modelClasses.length + 4) * anchors) {
    throw const FormatException('模型輸出格式不符，請改用手動輸入。');
  }
  final candidates = <Detection>[];
  for (var i = 0; i < anchors; i++) {
    var best = 0, confidence = 0.0;
    for (var c = 0; c < modelClasses.length; c++) {
      final value = raw[(c + 4) * anchors + i].toDouble();
      if (value.isFinite && value > confidence) {
        confidence = value;
        best = c;
      }
    }
    if (confidence < threshold) continue;
    final cx = raw[i].toDouble(), cy = raw[anchors + i].toDouble();
    final w = raw[2 * anchors + i].toDouble(),
        h = raw[3 * anchors + i].toDouble();
    if (![cx, cy, w, h].every((n) => n.isFinite) || w <= 0 || h <= 0) continue;
    final left = ((cx - w / 2 - input.padX) / input.resizedWidth).clamp(
      0.0,
      1.0,
    );
    final right = ((cx + w / 2 - input.padX) / input.resizedWidth).clamp(
      0.0,
      1.0,
    );
    final top = ((cy - h / 2 - input.padY) / input.resizedHeight).clamp(
      0.0,
      1.0,
    );
    final bottom = ((cy + h / 2 - input.padY) / input.resizedHeight).clamp(
      0.0,
      1.0,
    );
    if (right <= left || bottom <= top) continue;
    candidates.add(
      Detection(modelClasses[best], confidence, left, top, right, bottom),
    );
  }
  candidates.sort((a, b) => b.confidence.compareTo(a.confidence));
  final kept = <Detection>[];
  for (final candidate in candidates) {
    if (kept.every((k) => intersectionOverUnion(candidate, k) < nmsThreshold)) {
      kept.add(candidate);
    }
    if (kept.length >= 40) break;
  }
  // Guided capture expects one row. Keep physical order, never deduplicate IDs.
  kept.sort((a, b) => a.cx.compareTo(b.cx));
  return kept;
}

class TileDetector {
  final Future<OrtSession> Function() _loadSession;
  OrtSession? _session;
  bool _running = false;
  Future<void>? _pending;
  Future<void>? _closeFuture;

  /// Allows lifecycle tests to exercise real OrtSession/OrtValue calls without
  /// loading a model file. Production uses the bundled model unchanged.
  TileDetector({Future<OrtSession> Function()? sessionLoader})
    : _loadSession = sessionLoader ?? _loadBundledSession;

  static Future<OrtSession> _loadBundledSession() {
    final options = OrtSessionOptions(
      intraOpNumThreads: 2,
      interOpNumThreads: 1,
    );
    // Flutter Web places bundle keys beneath an additional assets/ directory.
    // The plugin's web createSessionFromAsset forwards the key as a raw URL.
    return kIsWeb
        ? OnnxRuntime().createSession(
            'assets/$detectorModelAsset',
            options: options,
          )
        : OnnxRuntime().createSessionFromAsset(
            detectorModelAsset,
            options: options,
          );
  }

  Future<ScanResult> scan(Uint8List bytes) =>
      _scan(() => compute(prepareImage, bytes));
  Future<ScanResult> scanFrame(CameraFrame frame) =>
      _scan(() => compute(prepareCameraFrame, frame));
  Future<ScanResult> _scan(Future<PreparedImage> Function() prepare) {
    if (_running || _closeFuture != null) {
      return Future.error(StateError('辨識器正在處理或釋放資源。'));
    }
    final result = _run(prepare);
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<ScanResult> _run(Future<PreparedImage> Function() prepare) async {
    if (_running) throw StateError('已有照片正在辨識。');
    _running = true;
    OrtValue? tensor;
    Map<String, OrtValue> outputs = {};
    var inferenceCompleted = false;
    final timer = Stopwatch()..start();
    try {
      final input = await prepare();
      _session ??= await _loadSession();
      tensor = await OrtValue.fromList(input.tensor, [1, 3, 640, 640]);
      outputs = await _session!.run({'images': tensor});
      final output = outputs['output0'];
      if (output == null ||
          !listEquals(output.shape, [1, 46, 8400]) ||
          output.dataType != OrtDataType.float32) {
        throw const FormatException('模型輸出格式不符，請改用手動輸入。');
      }
      final raw = await output.asFlattenedList();
      final detections = decodeDetections(raw.cast<num>(), input);
      inferenceCompleted = true;
      return ScanResult(
        detections,
        input.preview,
        input.width,
        input.height,
        timer.elapsedMilliseconds,
      );
    } finally {
      Object? releaseError;
      StackTrace? releaseStack;
      try {
        // A failed release must not skip other values or leave Retry disabled.
        for (final value in [...outputs.values, ?tensor]) {
          try {
            await value.dispose();
          } catch (error, stack) {
            releaseError ??= error;
            releaseStack ??= stack;
          }
        }
      } finally {
        _running = false;
      }
      // Preserve a preparation/inference error if cleanup also failed.
      if (inferenceCompleted && releaseError != null) {
        Error.throwWithStackTrace(releaseError, releaseStack!);
      }
    }
  }

  Future<void> close() => _closeFuture ??= _closeSession();

  Future<void> _closeSession() async {
    try {
      await _pending;
      final session = _session;
      // Even a failed close must not allow reuse of a possibly closed session.
      _session = null;
      await session?.close();
    } finally {
      _closeFuture = null;
    }
  }
}
