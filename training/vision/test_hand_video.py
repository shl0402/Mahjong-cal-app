import unittest
from evaluate_hand_video import canonical_order

class VideoOrderTests(unittest.TestCase):
    def test_row_comparison_uses_position_not_confidence_order(self):
        pred=[{'tile':'3m','box':[.7,.1,.8,.9],'confidence':.99},
              {'tile':'1m','box':[.1,.1,.2,.9],'confidence':.8},
              {'tile':'2m','box':[.4,.1,.5,.9],'confidence':.9}]
        self.assertEqual(canonical_order(pred),['1m','2m','3m'])
        self.assertEqual(pred[0]['tile'],'3m')
    def test_red_normalization_keeps_repeated_physical_tiles(self):
        pred=[{'tile':'0p','box':[.4,.1,.5,.9]},
              {'tile':'5p','box':[.1,.1,.2,.9]},
              {'tile':'UNKNOWN','box':[.7,.1,.8,.9]}]
        self.assertEqual(canonical_order(pred),['5p','5p','UNKNOWN'])

if __name__=='__main__':unittest.main()
