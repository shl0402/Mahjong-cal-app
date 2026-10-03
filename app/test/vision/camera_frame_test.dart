import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mahjong_vision/vision/camera_frame.dart';

List<int> rgb(img.Image image, int x, int y) {
  final p = image.getPixel(x, y);
  return [p.r.toInt(), p.g.toInt(), p.b.toInt()];
}

CameraFrame bgra(
  int width,
  int height, {
  int rotation = 0,
  int pixelStride = 4,
  int padding = 0,
  List<int> Function(int, int)? color,
}) {
  final stride = width * pixelStride + padding;
  final bytes = Uint8List(stride * height)..fillRange(0, stride * height, 239);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final c =
          color?.call(x, y) ?? [x % 256, y % 256, (x ~/ 256) * 16 + y ~/ 256];
      final i = y * stride + x * pixelStride;
      bytes.setRange(i, i + 4, [c[2], c[1], c[0], 17]);
    }
  }
  return CameraFrame(
    width: width,
    height: height,
    rotation: rotation,
    format: FrameFormat.bgra8888,
    planes: [FramePlane(bytes, stride, pixelStride)],
  );
}

FramePlane plane(List<List<int>> values, int rowStride, int pixelStride) {
  final bytes = Uint8List(rowStride * values.length)
    ..fillRange(0, rowStride * values.length, 253);
  for (var y = 0; y < values.length; y++) {
    for (var x = 0; x < values[y].length; x++) {
      bytes[y * rowStride + x * pixelStride] = values[y][x];
    }
  }
  return FramePlane(bytes, rowStride, pixelStride);
}

void main() {
  group('BGRA buffers and independent quarter-turn fixtures', () {
    test('padding and BGRA channels do not leak into RGB', () {
      final f = bgra(
        3,
        2,
        padding: 11,
        pixelStride: 5,
        color: (x, y) => [10 + x * 30, 20 + y * 60, 250 - x * 20 - y * 10],
      );
      final image = cameraFrameImage(f, guided: false);
      for (var y = 0; y < 2; y++) {
        for (var x = 0; x < 3; x++) {
          expect(rgb(image, x, y), [
            10 + x * 30,
            20 + y * 60,
            250 - x * 20 - y * 10,
          ]);
        }
      }
    });
    const matrices = {
      0: [
        [1, 2, 3],
        [4, 5, 6],
      ],
      90: [
        [4, 1],
        [5, 2],
        [6, 3],
      ],
      180: [
        [6, 5, 4],
        [3, 2, 1],
      ],
      270: [
        [3, 6],
        [2, 5],
        [1, 4],
      ],
    };
    for (final entry in matrices.entries) {
      test('${entry.key} degrees has exact orientation and dimensions', () {
        final f = bgra(
          3,
          2,
          rotation: entry.key,
          padding: 7,
          color: (x, y) => [1 + y * 3 + x, 0, 0],
        );
        final image = cameraFrameImage(f, guided: false);
        expect(image.width, entry.value.first.length);
        expect(image.height, entry.value.length);
        expect(f.uprightWidth, image.width);
        expect(f.uprightHeight, image.height);
        for (var y = 0; y < image.height; y++) {
          for (var x = 0; x < image.width; x++) {
            expect(rgb(image, x, y), [entry.value[y][x], 0, 0]);
          }
        }
      });
    }
    test(
      'last row may omit unused trailing padding, but not channel bytes',
      () {
        final original = bgra(3, 2, padding: 8);
        final p = original.planes.single;
        final bytes = Uint8List.sublistView(p.bytes, 0, p.rowStride + 3 * 4);
        final f = CameraFrame(
          width: 3,
          height: 2,
          format: FrameFormat.bgra8888,
          planes: [FramePlane(bytes, p.rowStride, 4)],
        );
        expect(() => validateCameraFrame(f), returnsNormally);
        expect(rgb(cameraFrameImage(f, guided: false), 2, 1), [2, 1, 0]);
        final short = CameraFrame(
          width: 3,
          height: 2,
          format: FrameFormat.bgra8888,
          planes: [
            FramePlane(
              Uint8List.sublistView(bytes, 0, bytes.length - 1),
              p.rowStride,
              4,
            ),
          ],
        );
        expect(() => cameraFrameImage(short), throwsFormatException);
      },
    );
  });

  group('YUV full-range conversion contract', () {
    // Literal BT.601 full-range color fixtures, independent of production
    // conversion arithmetic. Actual Android camera range needs device checks.
    const samples = [
      ([0, 128, 128], [0, 0, 0]),
      ([255, 128, 128], [255, 255, 255]),
      ([128, 128, 128], [128, 128, 128]),
      ([76, 85, 255], [254, 0, 0]),
      ([150, 44, 21], [0, 255, 1]),
      ([29, 255, 107], [0, 0, 254]),
    ];
    for (var i = 0; i < samples.length; i++) {
      test('known YUV color $i converts and clamps correctly', () {
        final s = samples[i];
        final f = CameraFrame(
          width: 2,
          height: 2,
          format: FrameFormat.yuv420,
          planes: [
            plane(
              [
                [s.$1[0], s.$1[0]],
                [s.$1[0], s.$1[0]],
              ],
              7,
              2,
            ),
            plane(
              [
                [s.$1[1]],
              ],
              5,
              3,
            ),
            plane(
              [
                [s.$1[2]],
              ],
              4,
              2,
            ),
          ],
        );
        final image = cameraFrameImage(f, guided: false);
        for (var y = 0; y < 2; y++) {
          for (var x = 0; x < 2; x++) {
            expect(rgb(image, x, y), s.$2);
          }
        }
      });
    }
    test(
      'independent chroma row/pixel strides select all four color blocks',
      () {
        final f = CameraFrame(
          width: 4,
          height: 4,
          format: FrameFormat.yuv420,
          planes: [
            plane(
              [
                [76, 76, 255, 255],
                [76, 76, 255, 255],
                [29, 29, 150, 150],
                [29, 29, 150, 150],
              ],
              11,
              2,
            ),
            plane(
              [
                [85, 128],
                [255, 44],
              ],
              9,
              3,
            ),
            plane(
              [
                [255, 128],
                [107, 21],
              ],
              7,
              2,
            ),
          ],
        );
        final image = cameraFrameImage(f, guided: false);
        const expected = [
          [
            [254, 0, 0],
            [255, 255, 255],
          ],
          [
            [0, 0, 254],
            [0, 255, 1],
          ],
        ];
        for (var y = 0; y < 4; y++) {
          for (var x = 0; x < 4; x++) {
            expect(rgb(image, x, y), expected[y ~/ 2][x ~/ 2]);
          }
        }
      },
    );
    test('odd dimensions use ceiling chroma size and strided luma', () {
      final f = CameraFrame(
        width: 3,
        height: 3,
        rotation: 90,
        format: FrameFormat.yuv420,
        planes: [
          plane(
            [
              [10, 20, 30],
              [40, 50, 60],
              [70, 80, 90],
            ],
            8,
            2,
          ),
          plane(
            [
              [128, 128],
              [128, 128],
            ],
            7,
            3,
          ),
          plane(
            [
              [128, 128],
              [128, 128],
            ],
            5,
            2,
          ),
        ],
      );
      final image = cameraFrameImage(f, guided: false);
      const values = [
        [70, 40, 10],
        [80, 50, 20],
        [90, 60, 30],
      ];
      for (var y = 0; y < 3; y++) {
        for (var x = 0; x < 3; x++) {
          expect(rgb(image, x, y), List.filled(3, values[y][x]));
        }
      }
    });
  });

  group('guide and preprocessing alignment', () {
    test(
      'landscape crop exactly matches normalized guide and source pixels',
      () {
        final f = bgra(640, 480, padding: 12);
        final g = ScanGuide.forFrame(640, 480);
        expect(g.left, .04);
        expect(g.width, .92);
        expect(g.height * 480, closeTo(184, 1e-9));
        final image = cameraFrameImage(f);
        expect([image.width, image.height], [589, 184]);
        expect(rgb(image, 0, 0), [26, 148, 0]);
        expect(rgb(image, 588, 183), [614 % 256, 331 % 256, 33]);
        expect(
          (image.width / 640 - g.width).abs(),
          lessThanOrEqualTo(.5 / 640),
        );
      },
    );
    test(
      'portrait guide after rotation crops the displayed upright region',
      () {
        final image = cameraFrameImage(
          bgra(640, 480, rotation: 90, padding: 4),
        );
        expect([image.width, image.height], [442, 138]);
        expect(rgb(image, 0, 0), [251, 460 % 256, 1]);
        expect(rgb(image, 441, 137), [388 % 256, 19, 16]);
        final other = cameraFrameImage(bgra(640, 480, rotation: 270));
        expect([other.width, other.height], [442, 138]);
        expect(rgb(other, 0, 0), [388 % 256, 19, 16]);
        expect(rgb(other, 441, 137), [251, 460 % 256, 1]);
      },
    );
    test('height cap keeps shallow-frame guide inside the image', () {
      final g = ScanGuide.forFrame(640, 100);
      expect(g.height, .82);
      expect(g.top, closeTo(.09, 1e-12));
      final image = cameraFrameImage(bgra(640, 100));
      expect([image.width, image.height], [589, 82]);
      expect(rgb(image, 0, 0), [26, 9, 0]);
    });
    test(
      'live-frame tensor uses guided image without creating JPEG preview',
      () {
        final prepared = prepareCameraFrame(
          bgra(320, 240, color: (x, y) => [255, 128, 0]),
        );
        expect([prepared.width, prepared.height], [294, 92]);
        expect(prepared.preview, isEmpty);
        expect(prepared.tensor.length, 3 * 640 * 640);
        final first = prepared.padY * 640 + prepared.padX;
        expect(prepared.tensor[first], 1);
        expect(prepared.tensor[640 * 640 + first], closeTo(128 / 255, 1e-7));
        expect(prepared.tensor[2 * 640 * 640 + first], 0);
        expect(prepared.tensor[0], closeTo(114 / 255, 1e-7));
      },
    );
  });

  test('Android rear-camera sensor/device orientation table is complete', () {
    const expected = [
      [0, 270, 180, 90],
      [90, 0, 270, 180],
      [180, 90, 0, 270],
      [270, 180, 90, 0],
    ];
    for (var s = 0; s < 4; s++) {
      for (var d = 0; d < 4; d++) {
        expect(androidFrameRotation(s * 90, d * 90), expected[s][d]);
      }
    }
    for (final bad in [-90, 1, 45, 360]) {
      expect(() => androidFrameRotation(bad, 0), throwsFormatException);
      expect(() => androidFrameRotation(0, bad), throwsFormatException);
    }
  });
  test(
    'malformed dimensions, rotations, plane counts, strides and buffers fail',
    () {
      final good = bgra(2, 2).planes;
      for (final size in [(0, 2), (1, 2), (2, -1), (4097, 2), (2, 4097)]) {
        expect(
          () => cameraFrameImage(
            CameraFrame(
              width: size.$1,
              height: size.$2,
              format: FrameFormat.bgra8888,
              planes: good,
            ),
          ),
          throwsFormatException,
        );
      }
      for (final rotation in [-90, 1, 45, 360]) {
        expect(
          () => cameraFrameImage(
            CameraFrame(
              width: 2,
              height: 2,
              rotation: rotation,
              format: FrameFormat.bgra8888,
              planes: good,
            ),
          ),
          throwsFormatException,
        );
      }
      for (final format in FrameFormat.values) {
        for (final planes in [
          <FramePlane>[],
          [...good, ...good],
        ]) {
          expect(
            () => cameraFrameImage(
              CameraFrame(width: 2, height: 2, format: format, planes: planes),
            ),
            throwsFormatException,
          );
        }
      }
      for (final p in [
        FramePlane(Uint8List(16), 7, 4),
        FramePlane(Uint8List(16), 8, 3),
        FramePlane(Uint8List(15), 8, 4),
        FramePlane(Uint8List(16), -1, 4),
      ]) {
        expect(
          () => cameraFrameImage(
            CameraFrame(
              width: 2,
              height: 2,
              format: FrameFormat.bgra8888,
              planes: [p],
            ),
          ),
          throwsFormatException,
        );
      }
      for (var badPlane = 0; badPlane < 3; badPlane++) {
        final planes = [
          plane(
            [
              [1, 2],
              [3, 4],
            ],
            2,
            1,
          ),
          plane(
            [
              [128],
            ],
            1,
            1,
          ),
          plane(
            [
              [128],
            ],
            1,
            1,
          ),
        ];
        final p = planes[badPlane];
        planes[badPlane] = FramePlane(Uint8List(0), p.rowStride, p.pixelStride);
        expect(
          () => cameraFrameImage(
            CameraFrame(
              width: 2,
              height: 2,
              format: FrameFormat.yuv420,
              planes: planes,
            ),
          ),
          throwsFormatException,
        );
      }
    },
  );
}
