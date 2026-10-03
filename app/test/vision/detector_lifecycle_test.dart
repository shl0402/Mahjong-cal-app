import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_vision/vision/camera_frame.dart';
import 'package:mahjong_vision/vision/detector.dart';

// Keep the real OrtSession/OrtValue wrappers and codec; substitute only native
// calls. No fake TileDetector can accidentally bypass the lifecycle under test.
class NativeRuntime {
  final events = <String>[];
  final released = <String>[];
  final closed = <String>[];
  final releaseFailures = <String>{};
  final runEntered = Completer<void>();
  final releaseEntered = Completer<void>();
  final closeEntered = Completer<void>();
  Completer<void>? runGate, releaseGate, closeGate;
  String? runError, readError, createError, closeError;
  String? heldRelease;
  bool shortOutput = false, failLoad = false;
  bool omitOutput = false;
  List<int> outputShape = [1, 46, 8400];
  String outputType = 'float32';
  int loads = 0, inputs = 0, runs = 0;

  Future<OrtSession> load() async {
    loads++;
    if (failLoad) throw StateError('Model load failed');
    return OrtSession.fromMap({
      'sessionId': 'session-$loads',
      'inputNames': ['images'],
      'outputNames': ['output0', 'auxiliary'],
    });
  }

  Future<Object?> handle(MethodCall call) async {
    final args = call.arguments as Map;
    switch (call.method) {
      case 'createOrtValue':
        expect(args['sourceType'], 'float32');
        expect(args['shape'], [1, 3, 640, 640]);
        expect(args['data'], isA<Float32List>());
        expect((args['data'] as Float32List).length, 3 * 640 * 640);
        if (createError != null) throw PlatformException(code: createError!);
        final id = 'input-${++inputs}';
        events.add('create:$id');
        return {
          'valueId': id,
          'dataType': 'float32',
          'shape': [1, 3, 640, 640],
        };
      case 'runInference':
        runs++;
        expect(args['inputs'], {
          'images': {'valueId': 'input-$inputs'},
        });
        events.add('run:${args['sessionId']}');
        if (!runEntered.isCompleted) runEntered.complete();
        await runGate?.future;
        if (runError != null) throw PlatformException(code: runError!);
        return {
          if (!omitOutput) 'output0': ['output-$runs', outputType, outputShape],
          'auxiliary': [
            'aux-$runs',
            'float32',
            [1],
          ],
        };
      case 'getOrtValueData':
        if (readError != null) throw PlatformException(code: readError!);
        return {'data': Float32List(shortOutput ? 1 : 46 * 8400)};
      case 'releaseOrtValue':
        final id = args['valueId'] as String;
        released.add(id);
        events.add('release:$id');
        if (id == heldRelease) {
          if (!releaseEntered.isCompleted) releaseEntered.complete();
          await releaseGate?.future;
        }
        if (releaseFailures.remove(id)) {
          throw PlatformException(code: 'release-$id');
        }
        return null;
      case 'closeSession':
        final id = args['sessionId'] as String;
        closed.add(id);
        events.add('close:$id');
        if (!closeEntered.isCompleted) closeEntered.complete();
        await closeGate?.future;
        if (closeError != null) throw PlatformException(code: closeError!);
        return null;
      default:
        throw StateError('Unexpected native call: ${call.method}');
    }
  }
}

CameraFrame frame() => CameraFrame(
  width: 8,
  height: 8,
  format: FrameFormat.bgra8888,
  planes: [FramePlane(Uint8List(8 * 8 * 4), 8 * 4, 4)],
);

Matcher platformError(String code) => isA<PlatformException>().having(
  (error) => error.code,
  'original native error code',
  code,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_onnxruntime');
  late NativeRuntime native;
  late TileDetector detector;
  setUp(() {
    native = NativeRuntime();
    detector = TileDetector(sessionLoader: native.load);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, native.handle);
  });
  tearDown(() async {
    for (final gate in [native.runGate, native.releaseGate, native.closeGate]) {
      if (gate != null && !gate.isCompleted) gate.complete();
    }
    native.closeError = null;
    await detector.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'successful scans reuse one session and release every native value',
    () async {
      for (var i = 0; i < 2; i++) {
        expect((await detector.scanFrame(frame())).detections, isEmpty);
      }
      expect(native.loads, 1);
      expect(native.released, [
        'output-1',
        'aux-1',
        'input-1',
        'output-2',
        'aux-2',
        'input-2',
      ]);
      await detector.close();
      expect(native.closed, ['session-1']);
    },
  );

  test(
    'wrong native output rank or channel order fails closed and permits retry',
    () async {
      for (final shape in [
        [1, 42, 8400],
        [1, 8400, 46],
        [46, 8400],
        [2, 46, 4200],
      ]) {
        native.outputShape = shape;
        await expectLater(detector.scanFrame(frame()), throwsFormatException);
      }
      expect(native.released, hasLength(12));
      native.outputShape = [1, 46, 8400];
      expect((await detector.scanFrame(frame())).detections, isEmpty);
    },
  );

  test('missing output and unexpected dtype fail closed while all available values are released', () async {
    native.omitOutput = true;
    await expectLater(detector.scanFrame(frame()), throwsFormatException);
    expect(native.released, ['aux-1', 'input-1']);
    native.omitOutput = false;
    native.outputType = 'int64';
    await expectLater(detector.scanFrame(frame()), throwsFormatException);
    expect(native.released.skip(2), ['output-2', 'aux-2', 'input-2']);
    native.outputType = 'float32';
    expect((await detector.scanFrame(frame())).detections, isEmpty);
  });

  test(
    'output release failure does not skip remaining values or disable retry',
    () async {
      native.releaseFailures.addAll(['output-1', 'aux-1', 'input-1']);
      await expectLater(
        detector.scanFrame(frame()),
        throwsA(platformError('release-output-1')),
      );
      expect(native.released, ['output-1', 'aux-1', 'input-1']);
      expect((await detector.scanFrame(frame())).detections, isEmpty);
      expect(native.runs, 2);
    },
  );

  test('input release failure also resets the busy state', () async {
    native.releaseFailures.add('input-1');
    await expectLater(
      detector.scanFrame(frame()),
      throwsA(platformError('release-input-1')),
    );
    expect((await detector.scanFrame(frame())).detections, isEmpty);
    expect(native.released, containsAll(['input-1', 'input-2']));
  });

  test(
    'inference failure keeps its error when input cleanup also fails',
    () async {
      native.runError = 'inference-failed';
      native.releaseFailures.add('input-1');
      await expectLater(
        detector.scanFrame(frame()),
        throwsA(platformError('inference-failed')),
      );
      expect(native.released, ['input-1']);
      native.runError = null;
      expect((await detector.scanFrame(frame())).detections, isEmpty);
    },
  );

  test('output read failure keeps its error and releases all values', () async {
    native.readError = 'read-failed';
    native.releaseFailures.addAll(['output-1', 'input-1']);
    await expectLater(
      detector.scanFrame(frame()),
      throwsA(platformError('read-failed')),
    );
    expect(native.released, ['output-1', 'aux-1', 'input-1']);
    native.readError = null;
    expect((await detector.scanFrame(frame())).detections, isEmpty);
  });

  test(
    'malformed output keeps its format error when cleanup also fails',
    () async {
      native.shortOutput = true;
      native.releaseFailures.add('output-1');
      await expectLater(detector.scanFrame(frame()), throwsFormatException);
      expect(native.released, ['output-1', 'aux-1', 'input-1']);
      native.shortOutput = false;
      expect((await detector.scanFrame(frame())).detections, isEmpty);
    },
  );

  test(
    'failed preprocessing leaves no native values and permits retry',
    () async {
      await expectLater(detector.scan(Uint8List(0)), throwsFormatException);
      expect(native.loads, 0);
      expect(native.events, isEmpty);
      expect((await detector.scanFrame(frame())).detections, isEmpty);
    },
  );

  test(
    'failed session loading and input allocation each permit retry',
    () async {
      native.failLoad = true;
      await expectLater(detector.scanFrame(frame()), throwsStateError);
      expect(native.events, isEmpty);
      native.failLoad = false;
      native.createError = 'allocate-failed';
      await expectLater(
        detector.scanFrame(frame()),
        throwsA(platformError('allocate-failed')),
      );
      expect(native.released, isEmpty);
      native.createError = null;
      expect((await detector.scanFrame(frame())).detections, isEmpty);
      expect(
        native.loads,
        2,
        reason: 'Allocation failure can reuse the session',
      );
    },
  );

  test('busy scans reject extra work and close waits for inference and every release', () async {
    native.runGate = Completer<void>();
    native.releaseGate = Completer<void>();
    native.heldRelease = 'output-1';
    final scanning = detector.scanFrame(frame());
    await native.runEntered.future;
    await expectLater(detector.scanFrame(frame()), throwsStateError);
    final closing = detector.close();
    expect(identical(closing, detector.close()), isTrue);
    await expectLater(detector.scanFrame(frame()), throwsStateError);
    expect(native.closed, isEmpty);
    native.runGate!.complete();
    await native.releaseEntered.future;
    expect(native.closed, isEmpty, reason: 'Output release is still blocked');
    native.releaseGate!.complete();
    await scanning;
    await closing;
    expect(native.inputs, 1);
    expect(native.events, [
      'create:input-1',
      'run:session-1',
      'release:output-1',
      'release:aux-1',
      'release:input-1',
      'close:session-1',
    ]);
  });

  test(
    'concurrent closes share native shutdown and prevent scans until it ends',
    () async {
      await detector.scanFrame(frame());
      native.closeGate = Completer<void>();
      var secondFinished = false;
      final first = detector.close();
      await native.closeEntered.future;
      final second = detector.close();
      expect(identical(first, second), isTrue);
      final observer = second.then((_) => secondFinished = true);
      await Future<void>.delayed(Duration.zero);
      expect(secondFinished, isFalse);
      await expectLater(detector.scanFrame(frame()), throwsStateError);
      expect(native.closed, ['session-1']);
      native.closeGate!.complete();
      await Future.wait([first, second, observer]);
      expect(secondFinished, isTrue);
      await detector.scanFrame(frame());
      expect(native.loads, 2);
      expect(
        native.events.lastWhere((e) => e.startsWith('run:')),
        'run:session-2',
      );
    },
  );

  test(
    'failed close is shared and a later scan never reuses the retired session',
    () async {
      await detector.scanFrame(frame());
      native.closeGate = Completer<void>();
      native.closeError = 'close-failed';
      final first = detector.close();
      final firstCheck = expectLater(
        first,
        throwsA(platformError('close-failed')),
      );
      await native.closeEntered.future;
      final second = detector.close();
      expect(identical(first, second), isTrue);
      final secondCheck = expectLater(
        second,
        throwsA(platformError('close-failed')),
      );
      native.closeGate!.complete();
      await Future.wait([firstCheck, secondCheck]);
      expect(native.closed, ['session-1']);
      native.closeError = null;
      await detector.scanFrame(frame());
      expect(native.loads, 2);
      expect(
        native.events.lastWhere((e) => e.startsWith('run:')),
        'run:session-2',
      );
      await detector.close();
      expect(native.closed, ['session-1', 'session-2']);
    },
  );

  test('close waits for failed inference cleanup and remains safe without a session', () async {
    await detector.close();
    await detector.close();
    expect(native.closed, isEmpty);
    native.runGate = Completer<void>();
    native.runError = 'inference-failed';
    native.releaseFailures.add('input-1');
    final scanning = expectLater(
      detector.scanFrame(frame()),
      throwsA(platformError('inference-failed')),
    );
    await native.runEntered.future;
    final closing = detector.close();
    native.runGate!.complete();
    await scanning;
    await closing;
    expect(native.events, [
      'create:input-1',
      'run:session-1',
      'release:input-1',
      'close:session-1',
    ]);
    await detector.close();
    expect(native.closed, ['session-1']);
  });
}
