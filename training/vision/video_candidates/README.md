# Real-camera video candidate

`niconico_reference.json` is the frozen, pre-inference reference for an actual eight-second camera excerpt, requested from original source seconds 188–196. Its companion `.sha256` pins the reference. The full decoded clip is `niconico-188-196-lossless.mkv` (1920×1080, 29.97 fps, 239 frames, FFV1 lossless, audio removed). An auxiliary lossless row crop is also available; use the full video's explicit reference ROI for evaluation.

The reference contains 13 visible tiles, left to right:

`1s 2s 5s 6s 6s 6s 2m 4m 0m 7m 5p 7p 8p`

`0m` is a red five characters. A detector with only ordinary `5m` must report normalized-face accuracy separately from red identity. Two reviewers independently agreed on the sequence. Twenty frames spaced by 12 frames (about 400 ms) were inspected before inference: the row stays visible and unchanged. This supports a sampled sequence diagnostic; it is not a dense per-frame annotation of all 239 frames.

The row is tilted and has only 13 tiles, so it cannot demonstrate a successful complete-hand lock in the current app. It is a real broadcast camera scene, not a phone scan. Neither public availability nor publication date establishes independence from pretrained training data. This source is development material after manual inspection, not an untouched holdout.

Source: [Nicopro Mahjong footage on Wikimedia Commons](https://commons.wikimedia.org/w/index.php?curid=74794134), creator **ニコプロ -ニコニコプロレスチャンネル-**, original [YouTube publication](https://www.youtube.com/watch?v=s9g9TGOxxq8). License: [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/). Commons revision `1032109094` retains the YouTube CC-BY declaration and a license-review record dated 2020-02-13. Credit the creator, source and license, and disclose trimming, cropping, and audio removal if sharing a derivative. `provenance.json` and the saved Commons API responses preserve this evidence.

The original 249 MB video was not downloaded in full. An initial stream-copy inspection clip has a keyframe-aligned start and must not be used as an exact source-time reference. The final lossless excerpt uses accurate input seeking; its decoded frame PTS values are in `niconico-188-196-frame-times.csv`. Local clip PTS is authoritative; the source-time offset is approximate to one frame.

Other candidates: the saved 6.35 MB [Miyalinsky robotics clip](https://huggingface.co/datasets/Miyalinsky/mahjong) declares Apache-2.0 but is severely defocused and grayscale, so it is unsuitable for a confident positive row-label reference. The [Anren camera clip](https://commons.wikimedia.org/wiki/File:Mahjong1.theora.ogv) declares CC BY-SA 3.0; only its metadata and thumbnail were inspected because a clearer source was found.

`niconico-manual-reference.json` is the earlier single-reviewer draft and is retained for provenance. The authoritative final evaluator input is `niconico_reference.json`.
