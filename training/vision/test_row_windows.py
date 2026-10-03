import unittest
from probe_row_windows import merge_windows, windows


class WindowGeometryTests(unittest.TestCase):
    def test_midpoint_tile_has_one_owner_and_global_coordinates(self):
        # Same physical tile crosses the ownership boundary in both crops.
        prediction = {'tile': '5m', 'confidence': .9}
        left = dict(prediction, box=[.45 / .6, .1, .55 / .6, .9])
        right = dict(prediction, box=[(.45 - .4) / .6, .1, (.55 - .4) / .6, .9])
        result = merge_windows(list(zip(windows(1000, 200), [[left], [right]])), 1000)
        self.assertEqual(len(result), 1)
        for actual, expected in zip(result[0]['box'], [.45, .1, .55, .9]):
            self.assertAlmostEqual(actual, expected)

    def test_duplicate_boxes_across_boundary_are_suppressed(self):
        left = {'tile': '5m', 'confidence': .8, 'box': [.43 / .6, 0, .55 / .6, 1]}
        right = {'tile': '6m', 'confidence': .9, 'box': [(.45 - .4) / .6, 0, (.57 - .4) / .6, 1]}
        result = merge_windows(list(zip(windows(1000, 200), [[left], [right]])), 1000)
        self.assertEqual([p['tile'] for p in result], ['6m'])

    def test_narrow_source_and_rounding_remap(self):
        self.assertEqual(windows(101, 100), [(0, 101, 0., 1.)])
        result = merge_windows([((40, 101, .5, 1.),
                                [{'box': [0, 0, 1, 1], 'confidence': 1.}])], 101)
        self.assertEqual(result[0]['box'], [40 / 101, 0, 1, 1])


if __name__ == '__main__':
    unittest.main()
