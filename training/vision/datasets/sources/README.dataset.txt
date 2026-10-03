# mahjong-vtacs-mexax-m4vyu-sjtd > 2025-03-14 12:29am
https://universe.roboflow.com/rf-100-vl/mahjong-vtacs-mexax-m4vyu-sjtd

Provided by a Roboflow user
License: MIT

# Overview
- [Introduction](#introduction)
- [Object Classes](#object-classes)
  - [Bamboo Tiles](#bamboo-tiles)
    - [Bamboo 1](#bamboo_1)
    - [Bamboo 2](#bamboo_2)
    - [Bamboo 3](#bamboo_3)
    - [Bamboo 4](#bamboo_4)
    - [Bamboo 5](#bamboo_5)
    - [Bamboo 6](#bamboo_6)
    - [Bamboo 7](#bamboo_7)
    - [Bamboo 8](#bamboo_8)
    - [Bamboo 9](#bamboo_9)
- [Character Classes](#character-classes)
  - [Character 1](#character_1)
  - [Character 2](#character_2)
  - [Character 3](#character_3)
  - [Character 4](#character_4)
  - [Character 5](#character_5)
  - [Character 6](#character_6)
  - [Character 7](#character_7)
  - [Character 8](#character_8)
  - [Character 9](#character_9)
- [Circle Classes](#circle-classes)
  - [Circle 1](#circle_1)
  - [Circle 2](#circle_2)
  - [Circle 3](#circle_3)
  - [Circle 4](#circle_4)
  - [Circle 5](#circle_5)
  - [Circle 6](#circle_6)
  - [Circle 7](#circle_7)
  - [Circle 8](#circle_8)
  - [Circle 9](#circle_9)
- [Wind Directions](#wind-directions)
  - [East](#east)
  - [North](#north)
  - [South](#south)
  - [West](#west)
- [Dragons](#wind-directions)
  - [Red](#red)
  - [Green](#green)
  - [White](#white)

# Introduction
The Mahjong dataset aims to facilitate the development of object detection models that can accurately identify and distinguish different mahjong tiles. This dataset encompasses 34 unique classes corresponding to different tiles used in the traditional Chinese game of mahjong. The classes include three different suits each with numerical classifications (bamboo, character, and circle), as well as four wind indicators (east, south, west, north) and three dragons (green, red, and white).

# Object Classes

## Bamboo 1
### Description
Bamboo 1 tiles are characterized by a single green bamboo rod with a single circle at the center. They are predominantly light in color with intricate bamboo designs.

### Instructions
- Annotate the entire tile, ensuring to include the patterns and designs that indicate it is a bamboo tile, specifically with one bamboo symbol.
- Ensure that the rectangular boundaries fully encase the tile, even if it is partially occluded by another tile or edge of the image.
- Do not label any reflection of tiles seen on the surface.
- Differentiate this class from other bamboo tiles by verifying that the tile only contains one bamboo symbol.

## Bamboo 2
### Description
A bamboo tile featuring two vertically stacked bamboo sticks.

### Instructions
- Zone the entire visible area of the tile using a rectangular boundary, which includes both the bamboo symbol and the numeric character.
- For occlusions, estimate the bounds of the hidden part and include that within the annotation.
- Do not annotate reflections or unseen areas that are speculative.

## Bamboo 3
### Description
Mahjong tile featuring three bamboo symbols.

### Instructions
- Bound the full extent of the tile image without excluding partial occlusions.
- The focus should be on capturing three bamboo designs on the tile.
- Avoid labeling reflections or unclear images where the tile cannot be clearly identified as a three-bamboo tile.

## Bamboo 4
### Description
A tile displaying four bamboo sticks arranged vertically.

### Instructions
- Include all visible parts of the tile in the annotation, ensuring the bamboo symbols are present.
- If occluded, estimate and label appropriately without assuming unseen details.
- Exclude reflections and unclear images where the number of bamboo sticks cannot be determined.

## Bamboo 5
### Description
A tile featuring five bamboo sticks in a vertical arrangement.

### Instructions
- Draw bounding boxes around the entire tile, ensuring clear identification of the bamboo count.
- Partial occlusions should be annotated with estimated boundaries.
- Avoid marking reflections and misidentified tiles.

## Bamboo 6
### Description
A bamboo tile showing six distinct bamboo sticks.

### Instructions
- Clearly identify and annotate all six bamboo symbols.
- Maintain accurate bounding boxes even in cases of partial occlusion.
- Exclude any reflective or unclear images.

## Bamboo 7
### Description
A tile with seven bamboo symbols, typically arranged in a symmetrical or organized manner.

### Instructions
- Label the tile ensuring all symbols are captured within the bounding box.
- Annotate occlusions while maintaining accuracy in shape estimation.
- Ignore reflections or indistinct representations.

## Bamboo 8
### Description
A tile containing eight bamboo sticks, usually stacked in two groups.

### Instructions
- Annotate the tile ensuring the clear visibility of all bamboo symbols.
- Account for occlusions but avoid speculative markings.
- Disregard reflections or indistinct tiles.

## Bamboo 9
### Description
A tile featuring nine bamboo symbols, forming the highest numbered bamboo tile.

### Instructions
- Annotate the tile ensuring the clear visibility of all bamboo symbols.
- Account for occlusions but avoid speculative markings.
- Disregard reflections or indistinct tiles.

## Character 1
### Description
A tile featuring the chinese character for one.

### Instructions
- Draw bounding boxes around the entire tile, ensuring clear identification of the chinese character
- Partial occlusions should be annotated with estimated boundaries.
- Avoid marking reflections and misidentified tiles.

## Character 2
### Description
A tile featuring the chinese character for two.

### Instructions
- Draw bounding boxes around the entire tile, ensuring clear identification of the chinese character
- Partial occlusions should be annotated with estimated boundaries.
- Avoid marking reflections and misidentified tiles.

## Character 3
### Description
A tile featuring the chinese character for three.

### Instructions
- Draw bounding boxes around the entire tile, ensuring clear identification of the chinese character
- Partial occlusions should be annotated with estimated boundaries.
- Avoid marking reflections and misidentified tiles.

## Character 4
### Description
A tile featuring the chinese character for four.

### Instructions
- Draw bounding boxes around the entire tile, ensuring clear identification of the chinese character
- Partial occlusions should be annotated with estimated boundaries.
- Avoid marking reflections and misidentified tiles.

## Character 5
### Description
A tile featuring the chinese character for five.

### Instructions
- Draw bounding boxes around the entire tile, ensuring clear identification of the chinese character
- Partial occlusions should be annotated with estimated boundaries.
- Avoid marking reflections and misidentified tiles.

## Character 6
### Description
A tile featuring the chinese character for six.

### Instructions
- Draw bounding boxes around the entire tile, ensuring clear identification of the chinese character
- Partial occlusions should be annotated with estimated boundaries.
- Avoid marking reflections and misidentified tiles.

## Character 7
### Description
A tile featuring the chinese character for seven.

### Instructions
- Draw bounding boxes around the entire tile, ensuring clear identification of the chinese character
- Partial occlusions should be annotated with estimated boundaries.
- Avoid marking reflections and misidentified tiles.

## Character 8
### Description
A tile featuring the chinese character for eight.

### Instructions
- Draw bounding boxes around the entire tile, ensuring clear identification of the chinese character
- Partial occlusions should be annotated with estimated boundaries.
- Avoid marking reflections and misidentified tiles.

## Character 9
### Description
A tile featuring the chinese character for nine.

### Instructions
- Draw bounding boxes around the entire tile, ensuring clear identification of the chinese character
- Partial occlusions should be annotated with estimated boundaries.
- Avoid marking reflections and misidentified tiles.

## Circle 1
### Description
A tile featuring one circle.

### Instructions
- Draw bounding boxes around the entire tile, ensuring the the tile has one circle
- Partial occlusions should be annotated with estimated boundaries.
- Avoid marking reflections and misidentified tiles.

## Circle 2
### Description
A tile featuring two circles.

### Instructions
- Draw bounding boxes around the entire tile, ensuring the the tile has two circles.
- Partial occlusions should be annotated with estimated boundaries.
- Avoid marking reflections and misidentified tiles.

## Circle 3
### Description
A tile featuring three circles.

### Instructions
- Draw bounding boxes around the entire tile, ensuring the the tile has three circles.
- Partial occlusions should be annotated with estimated boundaries.
- Avoid marking reflections and misidentified tiles.

## Circle 4
### Description
A tile featuring four circles.

### Instructions
- Draw bounding boxes around the entire tile, ensuring the the tile has four circles.
- Partial occlusions should be annotated with estimated boundaries.
- Avoid marking reflections and misidentified tiles.

## Circle 5
### Description
A tile featuring five circles.

### Instructions
- Draw bounding boxes around the entire tile, ensuring the the tile has five circles.
- Partial occlusions should be annotated with estimated boundaries.
- Avoid marking reflections and misidentified tiles.

## Circle 6
### Description
A tile featuring six circles.

### Instructions
- Draw bounding boxes around the entire tile, ensuring the the tile has six circles.
- Partial occlusions should be annotated with estimated boundaries.
- Avoid marking reflections and misidentified tiles.

## Circle 7
### Description
A tile featuring seven circles.

### Instructions
- Draw bounding boxes around the entire tile, ensuring the the tile has seven circles.
- Partial occlusions should be annotated with estimated boundaries.
- Avoid marking reflections and misidentified tiles.

## Circle 8
### Description
A tile featuring eight circles.

### Instructions
- Draw bounding boxes around the entire tile, ensuring the the tile has eight circles.
- Partial occlusions should be annotated with estimated boundaries.
- Avoid marking reflections and misidentified tiles.

## Circle 9
### Description
A tile featuring nine circles.

### Instructions
- Draw bounding boxes around the entire tile, ensuring the the tile has nine circles.
- Partial occlusions should be annotated with estimated boundaries.
- Avoid marking reflections and misidentified tiles.

## East
### Description
A tile featuring the chinese character for east.

### Instructions
- Draw bounding boxes around the entire tile.
- Partial occlusions should be annotated with estimated boundaries.
- Avoid marking reflections and misidentified tiles.

## South
### Description
A tile featuring the chinese character for south.

### Instructions
- Draw bounding boxes around the entire tile.
- Partial occlusions should be annotated with estimated boundaries.
- Avoid marking reflections and misidentified tiles.

## North
### Description
A tile featuring the chinese character for north.

### Instructions
- Draw bounding boxes around the entire tile.
- Partial occlusions should be annotated with estimated boundaries.
- Avoid marking reflections and misidentified tiles.

## West
### Description
A tile featuring the chinese character for west.

### Instructions
- Draw bounding boxes around the entire tile.
- Partial occlusions should be annotated with estimated boundaries.
- Avoid marking reflections and misidentified tiles.

## Red
### Description
A tile featuring a red chinese character.

### Instructions
- Draw bounding boxes around the entire tile.
- Partial occlusions should be annotated with estimated boundaries.
- Avoid marking reflections and misidentified tiles.


## Green
### Description
A tile featuring a green chinese character.

### Instructions
- Draw bounding boxes around the entire tile.
- Partial occlusions should be annotated with estimated boundaries.
- Avoid marking reflections and misidentified tiles.

## White
### Description
A tile featuring a white chinese character.

### Instructions
- Draw bounding boxes around the entire tile.
- Partial occlusions should be annotated with estimated boundaries.
- Avoid marking reflections and misidentified tiles.
