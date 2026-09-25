# Segment 9 (Action 1) — Multi-Region ROI on Android, Feasibility Prototype

Exploratory pilot from the Spandan Field Guide's "still open" list. **Feasibility/
direction-finding only — deliberately scoped down, not a full port or a live-pipeline
change.** Answers one question: *does adding a second (cheek) ROI crop-and-average pass
per frame cost anything real on-device?* — before deciding whether a bigger port
(actually wiring a second region into `RealHeartRateEstimator`/region-switching) is worth
building.

## What was built

- `RoiCalculator.cheekRoisFrom(faceBox)` — new function, additive, does not change
  `foreheadRoiFrom`. Cheek fractions ported directly from
  `matlab/src/roi/extractROISignals.m`'s `computeRegionBBoxes` `'cheek'` mode: x:[0.10,
  0.35] (left) / [0.65,0.90] (right), y:[0.55,0.75] of the face box. Cheek (not glabella
  or malar) was picked because Segment6_Task_N/Task_Q found forehead and cheek are the
  two regions that are "not bad everywhere" — glabella/malar lost to both across every
  Task N scenario.
- `RoiPixelAverager.averageRgbMultiRect(imageProxy, rects)` — new function, additive,
  does not change the existing single-rect `averageRgb` the live pipeline uses. Pools
  pixels from multiple rects into ONE spatial mean, matching
  `extractROISignals.m`'s own bilateral-region convention ("concatenate the left/right
  pixel arrays before averaging, not the mean of two per-patch means").
- `MultiRegionProfilingFaceAnalyzer` — new, debug-only `ImageAnalysis.Analyzer`, gated
  behind a `secondRegionEnabled` constructor flag, **never constructed by
  `MainActivity.kt`'s normal path and not wired into the live HR pipeline** (no
  `onResult` callback into `SignalBuffer`/`RealHeartRateEstimator` at all — this class
  only measures throughput). Reuses `Segment7_Task_G`'s `ProfilingFaceAnalyzer` style
  (same detector config, same largest-face rule, same per-frame `Log.d` timing
  convention) but deliberately WITHOUT `FaceAnalyzer.kt`'s frame-skip logic, so the
  1-region-vs-2-region comparison isn't entangled with the separately-measured
  frame-skip question (Segment7_Task_G Section 3).

## Method

Same "temporarily wire into `MainActivity.kt`, capture, revert" discipline as
Segment7_Task_G's own capture method — but SHORT captures (~25-35s each, not a full
stability run) per this pilot's own scope. Ran on the same Samsung Galaxy A35
(SM-A356E, Android 16) used for Segment7_Task_G's captures, with a face continuously in
frame:

1. `MultiRegionProfilingFaceAnalyzer(secondRegionEnabled = false)` — forehead-only
   baseline.
2. `MultiRegionProfilingFaceAnalyzer(secondRegionEnabled = true)` — forehead + cheek.
3. Reverted back to `FaceAnalyzer` immediately after, confirmed by a post-revert
   `gradlew assembleDebug` + reinstall (`git status` shows zero diff on `MainActivity.kt`
   afterward).

## Real result

| | frames | duration | steady-state (last 20s) fps | mean roi1Ms | mean roi2Ms |
|---|---|---|---|---|---|
| 1-region (forehead only) | 457 | 33.56s | **13.43** | 0.367 | 0.000 |
| 2-region (forehead + cheek) | 452 | 33.40s | **13.35** | 0.431 | 0.468 |

**The added cheek pass costs ~0.47ms/frame — negligible next to detection's ~71.5ms mean
(the ~98.5%-of-budget cost Segment7_Task_G already established).** Steady-state fps drops
13.43 → 13.35, a ~0.6% difference, within normal run-to-run noise (compare Segment7_Task_G
Section 1's own two views of one baseline run: 13.46 full-run vs 13.44 steady-state, a
similar-sized wobble with NO code change at all between them). Face-found percentage
differed more between the two captures (99.3% vs 77.9%) than fps did — almost certainly
session-to-session face positioning during the live capture, not an effect of
`secondRegionEnabled` (detection itself, which determines whether a face is found, does
not depend on that flag at all).

## Verdict: **promising**

A second ROI crop-and-average pass is effectively free on this hardware — consistent with
Segment7_Task_G's own finding that ROI/averaging work is a small fraction of the frame
budget even for one region; a second region just adds another small fraction of the same
kind. **This means a bigger port (actually wiring forehead+cheek into the live HR
pipeline, e.g. to feed a region-switching or region-fusion rule) is not blocked by
throughput** — if it doesn't happen, it should be for a signal-processing/accuracy
reason, not a performance one. This pilot does NOT show whether adding cheek to the live
pipeline would actually IMPROVE HR accuracy on Android — that is a separate question,
deliberately out of scope here (no signal-quality/HR-accuracy comparison was run; this
was a throughput-only check, per the task's own gating instruction to not wire this into
the live pipeline).

## Explicit scope boundary respected

Not wired into `MainActivity.kt`'s committed state (reverted after each capture, `git
status` confirms zero diff), not wired into `RealHeartRateEstimator`/`SignalBuffer`
(no callback exists in `MultiRegionProfilingFaceAnalyzer` to route samples there), and
`FaceAnalyzer.kt`'s own frame-skip logic was not touched or exercised by this pilot.
`RoiCalculator.foreheadRoiFrom` and `RoiPixelAverager.averageRgb` (the ones the live
pipeline actually calls) are unmodified — only new, additive functions were added
alongside them.

## Files added/touched

- `android/app/src/main/java/com/spandan/app/camera/RoiCalculator.kt` — added
  `cheekRoisFrom` (existing `foreheadRoiFrom` unchanged).
- `android/app/src/main/java/com/spandan/app/camera/RoiPixelAverager.kt` — added
  `averageRgbMultiRect` (existing `averageRgb` unchanged).
- `android/app/src/main/java/com/spandan/app/camera/MultiRegionProfilingFaceAnalyzer.kt`
  — new file, debug-only.
- `android/app/src/main/java/com/spandan/app/MainActivity.kt` — temporarily swapped
  twice (once per capture), reverted both times; committed state unchanged.
- This file.
