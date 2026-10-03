#!/usr/bin/env python3
"""Human-reviewed annotations, fixed before evaluating the detector.
Coordinates refer to original upright images; boxes enclose visible tile faces.
"""
import json,datetime
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
regions=[]
def add(id,source,roi,tiles,kind='hand',note=''):
    regions.append(dict(id=id,source_id=source,roi=roi,kind=kind,note=note,
                        annotations=[{'tile':t,'box':b} for t,b in tiles]))
def row(labels,edges,top,bottom):
    return [(t,[edges[i],top,edges[i+1],bottom]) for i,t in enumerate(labels.split())]
# Two photographed rows; not supported by the live single-row guide, retained as stress case.
a=row('1p 9p 1m 9m 1s 9s 5z',[40,264,465,679,890,1104,1314,1535],276,552)
a+=row('1z 2z 3z 4z 7z 6z 5z',[29,249,470,676,894,1111,1311,1552],552,861)
add('orphans-close-two-rows','commons-1316485',[0,180,1600,980],a,note='Two-row layout with large tiles and flash; stress case, not live single-row framing.')
# Four separate physical rows in one published photograph. These are correlated examples.
x=[18,61,103,144,185,225,266,308,349,391,433,474,516,558]
labels=['1p 2p 3p 3m 4m 5m 5s 6s 7s 3s 3s 3s 8m',
        '4z 1z 2z 4p 5p 6p 1m 2m 3m 6s',
        '2s 3s 4s 6m 7m 8m 2p 3p 4p',
        '4s 4s 4s 5s 6s 7s 6s 7s 8s 9s 9s 9s 4z']
boxes=row(labels[0],x,64,117)+[('8m',[621,63,667,117])]
add('ting-row-1','commons-31193194',[0,48,700,134],boxes,note='Tight row crop selected before inference; neighboring rows excluded. Four rows share one source photo.')
boxes=row(labels[1],[14,55,97,140,183,224,266,309,351,393,433],148,204)
boxes+=[('8s',[471,146,513,201]),('4p',[515,145,555,201]),('4p',[556,144,599,199]),('7s',[625,143,674,199])]
add('ting-row-2','commons-31193194',[0,134,700,215],boxes,note='Tight row crop, not a simulated 3.2:1 camera guide.')
boxes=row(labels[2],[10,52,94,135,179,221,264,306,348,389],219,274)
boxes+=[('7z',[432,218,474,273]),('5z',[473,217,516,273]),('1m',[515,216,560,272]),('1m',[559,216,602,273]),('6z',[627,217,676,274])]
add('ting-row-3','commons-31193194',[0,215,700,288],boxes,note='Tight row crop, same source photograph as other ting rows.')
boxes=row(labels[3],[8,50,91,134,176,218,261,304,346,389,431,475,520,563],298,351)+[('4z',[635,294,683,348])]
add('ting-row-4','commons-31193194',[0,288,705,365],boxes,note='Tight row crop, same source photograph as other ting rows.')
# Group scenes are diagnostic localization/classification cases, not complete hands.
boxes=row('2p 3p 4p',[39,95,153,213],128,208)+row('6m 7m 8m',[263,321,378,437],128,208)+row('1m 2m 3m',[515,573,630,691],134,216)
boxes+=row('2s 3s 4s',[34,93,151,209],286,364)+row('6s 7s 8s',[263,321,379,438],286,364)+row('7z 6z 5z',[516,574,632,693],289,366)
add('six-groups','commons-31195555',[0,75,720,405],boxes,'groups','18 photographed tiles, not a legal complete hand.')
boxes=row('1z 1z 1z',[274,360,448,535],76,189)+row('7z 7z 7z',[89,177,264,351],263,377)+row('8s 8s 8s',[430,518,608,696],265,379)
add('three-pungs','commons-31198498',[45,40,720,420],boxes,'groups','Nine photographed tiles in three pungs.')
# Complete thirteen-orphans hand. The second West is upside down, visually checked after rotation.
boxes=row('1s 9s 1m 9m 9p 1z 2z 3z 3z 4z 6z 5z 7z',[50,121,184,248,310,373,432,491,551,611,670,730,790,873],481,558)
boxes+=[('1p',[345,410,414,483])]
add('orphans-table-hand','commons-86379076',[20,350,916,630],boxes,note='14-tile hand including separated 1p; near 3.2:1 guide. Second West rotated180 degrees.')
# 13 concealed circles plus separated winning 8p. Other table tiles excluded before inference.
boxes=row('2p 3p 4p 3p 4p 5p 5p 6p 7p 7p 9p 9p 9p',[51,145,239,332,423,517,608,697,785,874,961,1047,1139,1223],744,866)
boxes+=[('8p',[1481,565,1608,677])]
add('chinitsu-table-hand','commons-179482826',[0,450,1632,960],boxes,note='14-tile hand including separated 8p; 3.2:1 guide; other table tiles excluded.')
# Front concealed row only; winning discard is elsewhere and intentionally not invented.
labels='1m 2m 3m 4m 5m 5m 5m 6m 6m 7m 7m 8m 9m'.split()
bounds=[[86,400,129,447],[125,393,165,440],[163,397,199,446],[198,386,237,431],[236,379,274,427],[272,375,309,423],[308,376,346,424],[344,374,384,423],[381,386,421,436],[418,382,458,431],[456,382,495,429],[486,369,530,419],[524,376,570,425]]
add('ron-concealed-row','commons-179482828',[48,308,608,480],list(zip(labels,bounds)),note='13-tile concealed row, winning discard outside region; sixth tile is rotated180 degrees.')
manifest={'annotation_method':'Manual visual face identification and axis-aligned boxes; fixed before model inference; no model-assisted labels',
          'created_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'coordinate_system':'upright original image pixel xyxy',
          'not_independent_samples':'Four ting rows are from one photo; all French gray-table photos likely share one tile set.',
          'regions':regions}
p=ROOT/'vision/reports/online_annotations.json';p.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
print(len(regions),'regions;',sum(len(r['annotations']) for r in regions),'annotated tiles')
