import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../vision/camera_frame.dart';
import '../vision/detector.dart';
import '../vision/scan_consensus.dart';
import 'tile_view.dart';

class ScanPage extends StatefulWidget {
  final Future<void> Function(List<int>) onAccepted;
  final VoidCallback onManual, onSample;
  final bool active;
  final int maximumTiles;

  /// Injectable boundaries keep camera lifecycle and confirmation testable.
  final TileDetector? detector;
  final int Function()? nowMilliseconds;
  const ScanPage({
    super.key,
    required this.onAccepted,
    required this.onManual,
    required this.onSample,
    this.active = true,
    this.maximumTiles = 14,
    this.detector,
    this.nowMilliseconds,
  });
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> with WidgetsBindingObserver {
  late final _detector = widget.detector ?? TileDetector();
  final _clock = Stopwatch()..start();
  CameraController? _camera;
  late ScanConsensus _consensus;
  late int _expected;
  bool _wanted = false, _resumed = true, _starting = false, _processing = false;
  bool _synchronizing = false,
      _resync = false,
      _disposed = false,
      _confirming = false;
  int _generation = 0, _lastFrameAt = -1000, _failures = 0;
  String? _error;
  DeviceOrientation? _lastOrientation;
  Timer? _expiry;
  bool get _desired => !_disposed && widget.active && _resumed && _wanted;
  int get _now => widget.nowMilliseconds?.call() ?? _clock.elapsedMilliseconds;
  ScanDecision get _decision => _consensus.current;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _expected = widget.maximumTiles;
    _consensus = ScanConsensus(expectedCount: _expected);
    _expiry = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_disposed || !_decision.ready) return;
      if (!_consensus.at(_now).ready) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant ScanPage old) {
    super.didUpdateWidget(old);
    if (old.maximumTiles != widget.maximumTiles) {
      _expected = widget.maximumTiles;
      _consensus = ScanConsensus(expectedCount: _expected);
      _generation++;
    }
    if (old.active != widget.active) {
      _generation++;
      _consensus.reset();
      unawaited(_synchronizeCamera());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _generation++;
    _consensus.reset();
    if (!_disposed) {
      setState(() {});
      unawaited(_synchronizeCamera());
    }
  }

  void _start() {
    if (kIsWeb) return;
    setState(() {
      _wanted = true;
      _error = null;
      _failures = 0;
      _consensus.reset();
    });
    _generation++;
    unawaited(_synchronizeCamera());
  }

  Future<void> _stop() async {
    _wanted = false;
    _generation++;
    _consensus.reset();
    if (!_disposed) setState(() {});
    await _synchronizeCamera();
  }

  /// Serialize permission/init/dispose and reconcile requests made while an
  /// earlier initialization was waiting. No camera survives an inactive tab.
  Future<void> _synchronizeCamera() async {
    if (_synchronizing) {
      _resync = true;
      return;
    }
    _synchronizing = true;
    try {
      do {
        _resync = false;
        if (!_desired && _camera != null) {
          final old = _camera!;
          _camera = null;
          if (!_disposed) setState(() {});
          await _releaseCamera(old);
        }
        if (_desired && _camera == null) {
          final generation = _generation;
          CameraController? pending;
          if (!_disposed) setState(() => _starting = true);
          try {
            final cameras = await availableCameras();
            final rear = cameras
                .where((c) => c.lensDirection == CameraLensDirection.back)
                .toList();
            if (rear.isEmpty) {
              throw CameraException('NoRearCamera', 'No rear camera');
            }
            if (generation != _generation || !_desired) {
              _resync = true;
              continue;
            }
            pending = CameraController(
              rear.first,
              ResolutionPreset.high,
              enableAudio: false,
              fps: 15,
              imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS
                  ? ImageFormatGroup.bgra8888
                  : ImageFormatGroup.yuv420,
            );
            await pending.initialize();
            if (generation != _generation || !_desired) {
              await _releaseCamera(pending);
              pending = null;
              _resync = true;
              continue;
            }
            _camera = pending;
            _lastOrientation = pending.value.deviceOrientation;
            pending.addListener(_onCameraValueChanged);
            await pending.startImageStream(_onFrame);
            pending = null;
            if (!_disposed) setState(() {});
          } catch (e) {
            if (pending != null) {
              await _releaseCamera(pending);
            }
            _camera = null;
            if (generation == _generation && !_disposed) {
              _wanted = false;
              setState(() => _error = _cameraError(e));
            }
          } finally {
            if (!_disposed) setState(() => _starting = false);
          }
        }
      } while (_resync);
    } finally {
      _synchronizing = false;
    }
  }

  Future<void> _releaseCamera(CameraController controller) async {
    controller.removeListener(_onCameraValueChanged);
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {
      // The OS may already have interrupted the stream.
    }
    try {
      await controller.dispose();
    } catch (_) {
      // Release remains safe after an OS camera interruption.
    }
  }

  void _onCameraValueChanged() {
    final value = _camera?.value;
    if (_disposed || value == null) return;
    if (value.hasError) {
      _wanted = false;
      _generation++;
      _consensus.reset();
      setState(() => _error = '相機已中斷。請重試，或使用手動輸入。');
      unawaited(_synchronizeCamera());
    } else if (_lastOrientation != value.deviceOrientation) {
      _lastOrientation = value.deviceOrientation;
      _generation++;
      setState(_consensus.reset);
    }
  }

  String _cameraError(Object e) {
    if (e is CameraException) {
      if (e.code.contains('Denied')) {
        return '未獲相機權限。請在手機設定 → 隱私權 → 相機允許「牌照」，再重試。';
      }
      if (e.code.contains('Restricted')) return '這部裝置限制了相機使用。你仍可手動輸入手牌。';
      if (e.code == 'NoRearCamera') {
        return '沒有可用的後置相機。模擬器可用示範手牌試算；即時掃描請在實體手機測試。';
      }
    }
    return '暫時無法啟動相機。請關閉其他相機程式後重試，或手動輸入。';
  }

  void _onFrame(CameraImage image) {
    final camera = _camera;
    final now = _now;
    if (!_desired ||
        camera == null ||
        _processing ||
        now - _lastFrameAt < 350) {
      return;
    }
    final orientation = camera.value.deviceOrientation;
    if (_lastOrientation != orientation) {
      _lastOrientation = orientation;
      _consensus.reset();
    }
    final generation = _generation;
    _lastFrameAt = now;
    try {
      final frame = _copyFrame(image, camera);
      _processing = true;
      unawaited(_process(frame, generation, orientation, now));
    } catch (e) {
      _frameFailure(e);
    }
  }

  CameraFrame _copyFrame(CameraImage image, CameraController camera) {
    final format = switch (image.format.group) {
      ImageFormatGroup.bgra8888 => FrameFormat.bgra8888,
      ImageFormatGroup.yuv420 => FrameFormat.yuv420,
      _ => throw const FormatException('Unsupported live camera format'),
    };
    final degrees = switch (camera.value.deviceOrientation) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
    };
    final frame = CameraFrame(
      width: image.width,
      height: image.height,
      format: format,
      rotation: defaultTargetPlatform == TargetPlatform.android
          ? androidFrameRotation(camera.description.sensorOrientation, degrees)
          : 0,
      planes: image.planes
          .map(
            (p) => FramePlane(
              Uint8List.fromList(p.bytes),
              p.bytesPerRow,
              p.bytesPerPixel ?? (format == FrameFormat.bgra8888 ? 4 : 1),
            ),
          )
          .toList(),
    );
    // Preview and analysis are separate CameraX use cases. A device may choose
    // incompatible aspect ratios; never confirm boxes against a wrong guide.
    final preview = camera.value.previewSize!;
    final landscape = degrees == 90 || degrees == 270;
    final previewAspect = landscape
        ? preview.width / preview.height
        : preview.height / preview.width;
    final frameAspect = frame.uprightWidth / frame.uprightHeight;
    if ((frameAspect / previewAspect - 1).abs() > .03) {
      throw const FormatException('Camera preview and frame aspect mismatch');
    }
    return frame;
  }

  Future<void> _process(
    CameraFrame frame,
    int generation,
    DeviceOrientation orientation,
    int capturedAt,
  ) async {
    try {
      final result = await _detector.scanFrame(frame);
      if (!_desired ||
          generation != _generation ||
          _camera?.value.deviceOrientation != orientation) {
        return;
      }
      _failures = 0;
      _consensus.observe(result.detections, capturedAt);
      _consensus.at(_now);
      setState(() {});
    } catch (e) {
      if (_desired && generation == _generation) _frameFailure(e);
    } finally {
      _processing = false;
    }
  }

  void _frameFailure(Object error) {
    _consensus.reset();
    _failures++;
    if (_disposed) return;
    if (_failures >= 3) {
      _wanted = false;
      _generation++;
      setState(() => _error = '這部裝置未能完成即時辨識。請重試，或用手動輸入；相機畫面沒有上傳。');
      unawaited(_synchronizeCamera());
    } else {
      setState(() {});
    }
    debugPrint('Live camera inference: $error');
  }

  Future<void> _confirm() async {
    final decision = _consensus.at(_now);
    if (!decision.ready ||
        _confirming ||
        !_desired ||
        _lastOrientation != _camera?.value.deviceOrientation) {
      return;
    }
    final tiles = List<int>.of(decision.tiles);
    setState(() => _confirming = true);
    await _stop();
    if (!_disposed) await widget.onAccepted(tiles);
    if (!_disposed) setState(() => _confirming = false);
  }

  Future<void> _manual() async {
    await _stop();
    if (!_disposed) widget.onManual();
  }

  Future<void> _sample() async {
    await _stop();
    if (!_disposed) widget.onSample();
  }

  @override
  void dispose() {
    _disposed = true;
    _wanted = false;
    _generation++;
    _expiry?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_synchronizeCamera());
    unawaited(
      _detector.close().catchError((Object error) {
        debugPrint('Detector shutdown: $error');
      }),
    );
    super.dispose();
  }

  String get _status => switch (_decision.issue) {
    ScanIssue.stable => '牌面已穩定，請核對後確認',
    ScanIssue.collecting => '保持不動，正在比對連續畫面…',
    ScanIssue.count => '請將整排 $_expected 張牌放入框中',
    ScanIssue.confidence => '部分牌面仍不清楚，請改善光線或距離',
    ScanIssue.arrangement => '請排成一行，讓每張牌完整入框',
    ScanIssue.physical => '辨識結果有重複或異常，請調整角度',
    ScanIssue.stale => '畫面已改變，正在重新確認',
    ScanIssue.empty => '對準牌面，避開反光與遮擋',
  };
  @override
  Widget build(BuildContext context) {
    final live = _camera != null && _camera!.value.isInitialized;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            children: [
              const Text(
                'LIVE · ON YOUR PHONE',
                style: TextStyle(
                  color: Color(0xff194D40),
                  fontSize: 11,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '對準手牌，\n穩定後確認。',
                style: Theme.of(context).textTheme.headlineLarge
                    ?.copyWith(height: 1.3),
              ),
              const SizedBox(height: 10),
              const Text(
                '相機連續辨識，畫面只在手機內處理。',
                style: TextStyle(color: Color(0xff606B64), height: 1.7),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '框內的暗手牌張數',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  DropdownButton<int>(
                    value: _expected,
                    items: [
                      for (var n = 2; n <= widget.maximumTiles; n += 3)
                        DropdownMenuItem(value: n, child: Text('$n 張')),
                    ],
                    onChanged: _confirming
                        ? null
                        : (v) {
                            if (v != null) {
                              setState(() {
                                _expected = v;
                                _consensus = ScanConsensus(expectedCount: v);
                                _generation++;
                              });
                            }
                          },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: live ? _livePreview() : _placeholder(),
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: Color(0xff9A5B20),
                      height: 1.6,
                    ),
                  ),
                ),
              if (live) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _status,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Text(
                      '${_decision.observedCount} / $_expected',
                      style: const TextStyle(
                        color: Color(0xff194D40),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: math.min(1, _decision.matchedFrames / 5),
                  color: _decision.ready
                      ? const Color(0xff194D40)
                      : const Color(0xffB68335),
                  backgroundColor: const Color(0xffE4E8DE),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 5,
                  runSpacing: 8,
                  children: [
                    for (final d in _decision.detections.take(17))
                      d.tile < 0
                          ? const Tooltip(
                              message: '未能辨識的牌',
                              child: Chip(label: Text('?')),
                            )
                          : TileView(tile: d.tile, compact: true),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  '穩定代表多次辨識一致，並不保證每張正確。請核對牌面；確認後仍可修改。',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xff66746C),
                    height: 1.6,
                  ),
                ),
              ] else ...[
                FilledButton.icon(
                  onPressed: kIsWeb || _starting ? null : _start,
                  icon: _starting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.videocam_outlined),
                  label: Text(_starting ? '正在啟動相機…' : '開啟相機掃描'),
                ),
                if (kIsWeb)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(
                      '瀏覽器版可試用手牌與計算。即時串流掃描請使用 iPhone／Android 測試 App。',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xff66746C),
                        height: 1.6,
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  if (live)
                    Expanded(
                      child: TextButton.icon(
                        onPressed: _stop,
                        icon: const Icon(Icons.pause_circle_outline),
                        label: const Text('暫停相機'),
                      ),
                    ),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: _confirming ? null : _manual,
                      icon: const Icon(Icons.touch_app_outlined),
                      label: const Text('手動輸入'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xffEEECE1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  '只掃描暗手牌，包括食糊牌。吃、碰、槓與花牌稍後分開加入。辨識模型仍在實體牌測試中，請勿省略人工核對。',
                  style: TextStyle(
                    color: Color(0xff786C48),
                    fontSize: 12,
                    height: 1.7,
                  ),
                ),
              ),
              TextButton(
                onPressed: _confirming ? null : _sample,
                child: const Text('先用示範手牌試算 →'),
              ),
            ],
          ),
        ),
        if (live || _confirming)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _decision.ready && !_confirming ? _confirm : null,
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(
                    _confirming
                        ? '正在開啟手牌…'
                        : _decision.ready
                        ? '確認這排牌，前往計算'
                        : '等待牌面穩定…',
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _placeholder() => Container(
    color: const Color(0xff194D40),
    padding: const EdgeInsets.fromLTRB(18, 24, 18, 24),
    child: Column(
      children: [
        const Icon(
          Icons.center_focus_strong,
          color: Color(0xffB7D5C7),
          size: 32,
        ),
        const SizedBox(height: 18),
        FittedBox(
          child: Row(
            children: [
              for (final t in [0, 1, 2, 13, 13, 20, 21, 22])
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: TileView(tile: t),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          '牌面朝上 · 單排 · 放入框內',
          style: TextStyle(color: Color(0xffD4E6DC), fontSize: 12),
        ),
      ],
    ),
  );
  Widget _livePreview() => ValueListenableBuilder<CameraValue>(
    valueListenable: _camera!,
    builder: (context, value, _) {
      final size = value.previewSize!;
      final landscape =
          value.deviceOrientation == DeviceOrientation.landscapeLeft ||
          value.deviceOrientation == DeviceOrientation.landscapeRight;
      final width = landscape ? size.width : size.height,
          height = landscape ? size.height : size.width;
      return AspectRatio(
        aspectRatio: landscape ? width / height : 1.25,
        child: ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: width,
              height: height,
              child: CameraPreview(
                _camera!,
                child: CustomPaint(
                  painter: _LiveOverlay(
                    ScanGuide.forFrame(width.round(), height.round()),
                    _decision.detections,
                    _decision.ready,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _LiveOverlay extends CustomPainter {
  final ScanGuide guide;
  final List<Detection> detections;
  final bool stable;
  _LiveOverlay(this.guide, this.detections, this.stable);
  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(
      guide.left * size.width,
      guide.top * size.height,
      guide.width * size.width,
      guide.height * size.height,
    );
    final shade = Path()
      ..addRect(Offset.zero & size)
      ..addRect(r)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(shade, Paint()..color = const Color(0x65000000));
    final color = stable ? const Color(0xff52E3A4) : const Color(0xffF1CE7A);
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(12)),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
    for (final d in detections) {
      canvas.drawRect(
        Rect.fromLTRB(
          r.left + d.left * r.width,
          r.top + d.top * r.height,
          r.left + d.right * r.width,
          r.top + d.bottom * r.height,
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = d.confidence >= .8
              ? const Color(0xff6BE4C6)
              : const Color(0xffF1BE55),
      );
    }
  }

  @override
  bool shouldRepaint(_LiveOverlay old) =>
      old.detections != detections ||
      old.stable != stable ||
      old.guide != guide;
}
