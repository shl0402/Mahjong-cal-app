"""Independent boundary checks for evaluation matching, not model accuracy."""
import unittest
from evaluate_online import match,iou

def item(tile,box):return {'tile':tile,'box':box}

class MatchingTest(unittest.TestCase):
    def test_duplicate_prediction_is_not_a_second_true_positive(self):
        truth=[item('1m',[0,0,1,1])]
        predicted=[item('1m',[0,0,1,1]),item('1m',[0,0,1,1])]
        self.assertEqual(len(match(truth,predicted)),1)
    def test_wrong_class_counts_as_miss_and_false_positive(self):
        truth=[item('1m',[0,0,1,1])];predicted=[item('2m',[0,0,1,1])]
        self.assertEqual(match(truth,predicted),[])
        self.assertEqual(len(match(truth,predicted,False)),1)
    def test_iou_boundary_is_inclusive(self):
        truth=[item('1m',[0,0,1,1])]
        self.assertEqual(len(match(truth,[item('1m',[0,0,.5,1])])),1)
        self.assertEqual(match(truth,[item('1m',[0,0,.499,1])]),[])
    def test_global_matching_avoids_greedy_loss(self):
        truth=[item('1m',[0,0,.6,1]),item('1m',[.3,0,.9,1])]
        predicted=[item('1m',[.15,0,.75,1]),item('1m',[0,0,.6,1])]
        self.assertEqual({(a,b) for a,b,_ in match(truth,predicted)},{(0,1),(1,0)})
    def test_empty_and_zero_area(self):
        self.assertEqual(match([],[]),[])
        self.assertEqual(match([item('1m',[0,0,1,1])],[]),[])
        self.assertEqual(iou([0,0,0,0],[0,0,0,0]),0)

if __name__=='__main__':unittest.main()
