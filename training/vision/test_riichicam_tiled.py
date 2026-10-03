import random
import unittest

import numpy as np
from PIL import Image

from evaluate_riichicam_tiled import (
    decode_window, inference_windows, merge_per_class, prepare_integer_pillow,
    round_positive,
)


def prediction(class_id, confidence, box):
    return {'model_class_id': class_id, 'confidence': confidence, 'box': box}


class SourceWrapperMathTest(unittest.TestCase):
    def test_window_boundaries_and_exact_final_window(self):
        self.assertEqual(inference_windows(200, 100), [(0, 0, 200, 100)])
        self.assertEqual(inference_windows(201, 100), [(0, 0, 200, 100), (1, 0, 200, 100)])
        self.assertEqual(inference_windows(999, 100), [
            (0, 0, 200, 100), (160, 0, 200, 100), (320, 0, 200, 100),
            (480, 0, 200, 100), (640, 0, 200, 100), (799, 0, 200, 100),
        ])
        self.assertEqual(inference_windows(100, 1000), [
            (0, y, 100, 200) for y in (0, 160, 320, 480, 640, 800)
        ])
        self.assertEqual(round_positive(2.5), 3)
        self.assertEqual(round_positive(3.5), 4)

    def test_200_random_windows_cover_full_axis_and_transpose(self):
        rng = random.Random(7042)
        for _ in range(200):
            width, height = rng.randint(1, 4000), rng.randint(1, 4000)
            windows = inference_windows(width, height)
            self.assertEqual(len(windows), len(set(windows)))
            self.assertEqual([(y, x, h, w) for x, y, w, h in windows],
                             inference_windows(height, width))
            previous_end = 0
            for x, y, w, h in windows:
                self.assertTrue(0 <= x < x + w <= width)
                self.assertTrue(0 <= y < y + h <= height)
                start, length = (x, w) if width > height else (y, h)
                self.assertLessEqual(start, previous_end)
                previous_end = start + length
            self.assertEqual(previous_end, max(width, height))

    def test_merge_keeps_different_classes_and_exact_threshold(self):
        # These length-3 boxes overlap by2, so IoU is exactly1/2.
        a = prediction(0, .9, [0, 0, 3, 1])
        b = prediction(0, .8, [1, 0, 4, 1])
        c = prediction(17, .7, [0, 0, 3, 1])
        self.assertEqual(merge_per_class([c, b, a], .5), [a, b, c])
        self.assertEqual(merge_per_class([c, b, a], .49), [a, c])
        # Ordinary5m and red5m have the same face but different source classes.
        ordinary = prediction(16, .95, [0, 0, 3, 1])
        self.assertEqual(merge_per_class([c, ordinary]), [ordinary, c])

    def test_integer_pillow_recipe_preserves_rgb_and_odd_padding(self):
        image = Image.new('RGB', (3, 2), (255, 0, 0))
        tensor, (scale, px, py) = prepare_integer_pillow(image)
        self.assertEqual(tensor.shape, (1, 3, 640, 640))
        self.assertEqual(tensor.dtype, np.float32)
        self.assertEqual((scale, px, py), (640 / 3, 0, 106))
        np.testing.assert_allclose(tensor[0, :, 0, 0], [114 / 255] * 3)
        np.testing.assert_array_equal(tensor[0, :, 106, 0], [1, 0, 0])
        np.testing.assert_array_equal(tensor[0, :, 532, 0], [1, 0, 0])
        np.testing.assert_allclose(tensor[0, :, 533, 0], [114 / 255] * 3)

    def test_decode_inverse_window_offset_red_identity_and_unclipped_boxes(self):
        raw = np.zeros((1, 41, 8400), dtype=np.float32)
        raw[0, :4, 0] = [100, 100, 80, 80]
        raw[0, 4 + 17, 0] = .25  # exact confidence boundary is retained
        result = decode_window(raw, (2, 20, 20), (200, 10, 320, 320), (1000, 100))
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]['tile'], '5m')
        self.assertTrue(result[0]['red_five'])
        np.testing.assert_allclose(result[0]['box'], [.22, .3, .26, .7])
        raw[0, :4, 0] = [0, 0, 80, 80]
        outside = decode_window(raw, (1, 0, 0), (0, 0, 640, 640), (640, 640))[0]
        self.assertLess(outside['box'][0], 0)

    def test_source_has_no_40_detection_cap_and_rejects_malformed_output(self):
        raw = np.zeros((1, 41, 8400), dtype=np.float32)
        for i in range(41):
            raw[0, :4, i] = [i * 12 + 6, 100, 5, 10]
            raw[0, 4, i] = .8
        result = decode_window(raw, (1, 0, 0), (0, 0, 640, 640), (640, 640))
        self.assertEqual(len(result), 41)
        with self.assertRaises(ValueError):
            decode_window(raw[:, :-1], (1, 0, 0), (0, 0, 640, 640), (640, 640))
        raw[0, 0, 0] = np.nan
        with self.assertRaises(ValueError):
            decode_window(raw, (1, 0, 0), (0, 0, 640, 640), (640, 640))


if __name__ == '__main__':
    unittest.main()
