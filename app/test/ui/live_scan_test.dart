import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_vision/ui/scan_page.dart';
import 'package:mahjong_vision/vision/camera_frame.dart';
import 'package:mahjong_vision/vision/detector.dart';

class FakeCamera extends CameraPlatform {
  final initialized = StreamController<CameraInitializedEvent>.broadcast();
  final errors = StreamController<CameraErrorEvent>.broadcast();
  final orientations =
      StreamController<DeviceOrientationChangedEvent>.broadcast();
  final streams = <int, StreamController<CameraImageData>>{};
  final disposed = <int>[];
  int created = 0;
  bool deny = false;
  bool squareFrames = false;
  Completer<void>? holdInitialize;
  MediaSettings? settings;
  @override
  Future<List<CameraDescription>> availableCameras() async => const [
    CameraDescription(
      name: 'rear',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
    ),
  ];
  @override
  Future<int> createCameraWithSettings(
    CameraDescription description,
    MediaSettings mediaSettings,
  ) async {
    if (deny) throw PlatformException(code: 'CameraAccessDenied');
    settings = mediaSettings;
    final id = ++created;
    streams[id] = StreamController<CameraImageData>.broadcast();
    return id;
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    await holdInitialize?.future;
    initialized.add(
      CameraInitializedEvent(
        cameraId,
        640,
        480,
        ExposureMode.auto,
        true,
        FocusMode.auto,
        true,
      ),
    );
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      initialized.stream.where((e) => e.cameraId == cameraId);
  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      errors.stream.where((e) => e.cameraId == cameraId);
  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      orientations.stream;
  @override
  bool supportsImageStreaming() => true;
  @override
  Stream<CameraImageData> onStreamedFrameAvailable(
    int cameraId, {
    CameraImageStreamOptions? options,
  }) => streams[cameraId]!.stream;
  @override
  Widget buildPreview(int cameraId) => const ColoredBox(color: Colors.black);
  @override
  Future<void> dispose(int cameraId) async => disposed.add(cameraId);
  void frame() {
    streams[created]!.add(
      CameraImageData(
        format: const CameraImageFormat(ImageFormatGroup.bgra8888, raw: 0),
        planes: [
          CameraImagePlane(
            bytes: Uint8List(4 * 640 * (squareFrames ? 640 : 480)),
            bytesPerRow: 2560,
            bytesPerPixel: 4,
          ),
        ],
        height: squareFrames ? 640 : 480,
        width: 640,
      ),
    );
  }

  Future<void> shutdown() async {
    for (final stream in streams.values) {
      await stream.close();
    }
    await initialized.close();
    for (var id = 1; id <= created; id++) {
      errors.add(CameraErrorEvent(id, 'closed'));
    }
    await errors.close();
    await orientations.close();
  }
}

List<Detection> row({double confidence = .95}) => List.generate(
  14,
  (i) => Detection(i, confidence, .035 + i * .067, .2, .087 + i * .067, .8),
);

class FakeDetector extends TileDetector {
  List<Detection> detections = row();
  Completer<ScanResult>? pending;
  int calls = 0, closed = 0;
  bool fail = false;
  ScanResult get result => ScanResult(detections, Uint8List(0), 640, 200, 20);
  @override
  Future<ScanResult> scanFrame(CameraFrame frame) async {
    calls++;
    if (fail) throw StateError('Test inference failure');
    return pending == null ? result : pending!.future;
  }

  @override
  Future<void> close() async {
    closed++;
  }
}

void main() {
  late CameraPlatform original;
  late FakeCamera camera;
  late FakeDetector detector;
  late int now;
  List<int>? accepted;
  int acceptanceCount = 0;
  setUp(() {
    original = CameraPlatform.instance;
    camera = FakeCamera();
    detector = FakeDetector();
    CameraPlatform.instance = camera;
    now = 0;
    accepted = null;
    acceptanceCount = 0;
  });
  tearDown(() async {
    await camera.shutdown();
    CameraPlatform.instance = original;
  });
  Future<void> mount(WidgetTester tester, {bool active = true}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScanPage(
            active: active,
            detector: detector,
            nowMilliseconds: () => now,
            onAccepted: (tiles) async {
              accepted = tiles;
              acceptanceCount++;
            },
            onManual: () {},
            onSample: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
  }

  Future<void> start(WidgetTester tester) async {
    await tester.ensureVisible(find.text('開啟相機掃描'));
    await tester.tap(find.text('開啟相機掃描'));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
  }

  Future<void> frame(WidgetTester tester) async {
    now += 400;
    camera.frame();
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
  }

  bool canConfirm(WidgetTester tester) =>
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('confirm-scan-preview')),
          )
          .onPressed !=
      null;

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
  }

  testWidgets(
    'camera starts only on request, no audio, and stops its stream on disposal',
    (tester) async {
      await mount(tester);
      expect(camera.created, 0);
      await start(tester);
      expect(camera.created, 1);
      expect(camera.settings!.enableAudio, isFalse);
      expect(camera.settings!.fps, 15);
      expect(camera.streams[1]!.hasListener, isTrue);
      await unmount(tester);
      expect(camera.disposed, [1]);
      expect(camera.streams[1]!.hasListener, isFalse);
      expect(detector.closed, 1);
    },
  );
  testWidgets('permission denial stays recoverable and never accepts a hand', (
    tester,
  ) async {
    camera.deny = true;
    await mount(tester);
    await start(tester);
    expect(find.textContaining('未獲相機權限'), findsOneWidget);
    expect(accepted, isNull);
    camera.deny = false;
    await start(tester);
    expect(camera.created, 1);
    await unmount(tester);
  });
  testWidgets(
    'human can confirm the first preview without waiting for stable frames',
    (tester) async {
      await mount(tester);
      await start(tester);
      expect(canConfirm(tester), isFalse);
      await frame(tester);
      expect(canConfirm(tester), isTrue);
      expect(accepted, isNull);
      await tester.tap(find.byKey(const ValueKey('confirm-scan-preview')));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      expect(accepted, List.generate(14, (i) => i));
      expect(camera.disposed, [1]);
      expect(camera.streams[1]!.hasListener, isFalse);
      await unmount(tester);
    },
  );
  testWidgets(
    'low confidence permits human review but UNKNOWN never enters the hand',
    (tester) async {
      await mount(tester);
      await start(tester);
      detector.detections = row(confidence: .79);
      for (var i = 0; i < 6; i++) {
        await frame(tester);
      }
      expect(canConfirm(tester), isTrue);
      detector.detections = [
        const Detection(-1, .99, .035, .2, .087, .8),
        ...row().skip(1),
      ];
      for (var i = 0; i < 6; i++) {
        await frame(tester);
      }
      expect(canConfirm(tester), isFalse);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );
  testWidgets(
    'stale stable result is disabled without waiting for another frame',
    (tester) async {
      await mount(tester);
      await start(tester);
      for (var i = 0; i < 5; i++) {
        await frame(tester);
      }
      now += 4001;
      await tester.pump(const Duration(milliseconds: 200));
      expect(canConfirm(tester), isFalse);
      await unmount(tester);
    },
  );
  testWidgets(
    'low-confidence preview expires and tap rechecks age immediately',
    (tester) async {
      await mount(tester);
      await start(tester);
      detector.detections = row(confidence: .4);
      await frame(tester);
      expect(canConfirm(tester), isTrue);
      // No timer tick or new render: the callback itself must reject old results.
      now += 4001;
      await tester.tap(find.byKey(const ValueKey('confirm-scan-preview')));
      await tester.pump();
      expect(accepted, isNull);
      await tester.pump(const Duration(milliseconds: 200));
      expect(canConfirm(tester), isFalse);
      await unmount(tester);
    },
  );
  testWidgets('double tap confirms once and ignores an in-flight next frame', (
    tester,
  ) async {
    await mount(tester);
    await start(tester);
    await frame(tester);
    detector.pending = Completer<ScanResult>();
    await frame(tester);
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('confirm-scan-preview')),
    );
    button.onPressed!();
    button.onPressed!();
    detector.pending!.complete(
      ScanResult(row().reversed.toList(), Uint8List(0), 640, 200, 20),
    );
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    expect(acceptanceCount, 1);
    expect(accepted, List.generate(14, (i) => i));
    expect(camera.disposed, [1]);
    await unmount(tester);
  });
  testWidgets(
    'slow inference yields a usable first preview instead of instant expiry',
    (tester) async {
      await mount(tester);
      await start(tester);
      detector.pending = Completer<ScanResult>();
      await frame(tester);
      now += 1500;
      detector.pending!.complete(detector.result);
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      expect(canConfirm(tester), isTrue);
      expect(accepted, isNull);
      await unmount(tester);
    },
  );
  testWidgets(
    'tap cannot accept identities that changed after the preview was painted',
    (tester) async {
      await mount(tester);
      await start(tester);
      await frame(tester);
      final oldTap = tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('confirm-scan-preview')),
          )
          .onPressed!;
      detector.pending = Completer<ScanResult>();
      await frame(tester);
      final changed = row()..[0] = const Detection(33, .95, .035, .2, .087, .8);
      // Complete inference but deliberately do not paint the changed preview.
      await tester.runAsync(() async {
        detector.pending!.complete(
          ScanResult(changed, Uint8List(0), 640, 200, 20),
        );
        await Future<void>.delayed(Duration.zero);
      });
      oldTap();
      await tester.pump();
      expect(accepted, isNull);
      expect(find.text('預覽剛有更新，請核對後再確認。'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('confirm-scan-preview')));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      expect(accepted!.first, 33);
      expect(acceptanceCount, 1);
      await unmount(tester);
    },
  );
  testWidgets(
    'tab exit closes camera, resume opens a fresh stream, and drops pending result',
    (tester) async {
      await mount(tester);
      await start(tester);
      detector.pending = Completer<ScanResult>();
      await frame(tester);
      for (var i = 0; i < 3; i++) {
        await frame(tester);
      }
      expect(detector.calls, 1, reason: 'Only one inference may be in flight');
      await mount(tester, active: false);
      expect(camera.disposed, [1]);
      detector.pending!.complete(detector.result);
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      detector.pending = null;
      await mount(tester);
      expect(camera.created, 2);
      expect(canConfirm(tester), isFalse);
      await unmount(tester);
    },
  );
  testWidgets(
    'leaving while permission initializes releases late camera and does not stream',
    (tester) async {
      camera.holdInitialize = Completer<void>();
      await mount(tester);
      await start(tester);
      await mount(tester, active: false);
      camera.holdInitialize!.complete();
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      expect(camera.disposed, [1]);
      expect(camera.streams[1]!.hasListener, isFalse);
      await unmount(tester);
    },
  );
  testWidgets(
    'three inference failures stop the camera with a manual fallback',
    (tester) async {
      await mount(tester);
      await start(tester);
      detector.fail = true;
      for (var i = 0; i < 3; i++) {
        await frame(tester);
      }
      expect(camera.disposed, [1]);
      expect(find.textContaining('未能完成即時辨識'), findsOneWidget);
      expect(accepted, isNull);
      await unmount(tester);
    },
  );
  testWidgets('background and foreground release and reopen the camera', (
    tester,
  ) async {
    await mount(tester);
    await start(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    expect(camera.disposed, [1]);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    expect(camera.created, 2);
    await unmount(tester);
  });
  testWidgets(
    'orientation changes revoke confirmation before another image arrives',
    (tester) async {
      await mount(tester);
      await start(tester);
      for (var i = 0; i < 5; i++) {
        await frame(tester);
      }
      expect(canConfirm(tester), isTrue);
      camera.orientations.add(
        const DeviceOrientationChangedEvent(DeviceOrientation.landscapeLeft),
      );
      await tester.pump();
      expect(canConfirm(tester), isFalse);
      expect(accepted, isNull);
      await frame(tester);
      expect(canConfirm(tester), isTrue);
      await unmount(tester);
    },
  );
  testWidgets('native camera errors release the stream and offer retry', (
    tester,
  ) async {
    await mount(tester);
    await start(tester);
    camera.errors.add(const CameraErrorEvent(1, 'Camera disconnected'));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    expect(camera.disposed, [1]);
    expect(find.textContaining('相機已中斷'), findsOneWidget);
    expect(accepted, isNull);
    await unmount(tester);
  });
  testWidgets(
    'mismatched preview and analysis aspect ratios never reach inference',
    (tester) async {
      camera.squareFrames = true;
      await mount(tester);
      await start(tester);
      for (var i = 0; i < 3; i++) {
        await frame(tester);
      }
      expect(detector.calls, 0);
      expect(camera.disposed, [1]);
      expect(accepted, isNull);
      await unmount(tester);
    },
  );
}
