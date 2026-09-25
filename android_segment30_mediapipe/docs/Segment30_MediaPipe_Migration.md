# Segment 30 — MediaPipe Face Detector Migration (candidate, NOT promoted)

All work for this segment happened in a new, isolated sibling directory,
`android_segment30_mediapipe/` (applicationId `com.spandan.app.mediapipe`), duplicated from
`android/` per this segment's own task brief — the original `android/` (production
`com.spandan.app`) was never edited. Both apps installed side by side on the same device
(Galaxy A35, `RFCXC0FFFSN`) for direct A/B comparison.

Motivated by a research pass after Segment 29: ML Kit's `FaceDetectorOptions` (even at
Segment 29's own `minFaceSize=0.35` promotion, ~19-25ms mean real-detection cost) was
compared against Google's own published MediaPipe Face Detector (BlazeFace short-range)
benchmark — 2.94ms on a Pixel 6, a 6-30x claimed gap. `github.com/namdpran8/Ojas` (a public
Android rPPG app already using MediaPipe) was read first per this task's own brief, before
any design decisions below.

**Bottom line, stated up front**: MediaPipe is **NOT promoted**. On THIS device, in THIS
integration, it is both **slower** than Segment 29's ML Kit baseline and **produces a
face box shifted low enough to misplace the forehead ROI** — confirmed by real on-device
timing, a real on-device accuracy comparison against ML Kit's own box, AND direct visual
observation during testing ("it doesn't even detect the forehead properly"). Google's
2.94ms benchmark number measures the model in isolation; it does not survive contact with
this app's actual CameraX YUV_420_888 pipeline, for a concrete, diagnosed reason (see
below). `useMediaPipeDetection` stays `false` everywhere it was added.

## What was built

- `app/build.gradle.kts`: `com.google.mediapipe:tasks-vision:1.0.0` (checked against
  `dl.google.com/dl/android/maven2/.../maven-metadata.xml` directly — `1.0.0` is the actual
  `<release>`/`<latest>`, not a guess; earlier `0.10.x` tags exist but are superseded).
  `applicationId` suffixed to `com.spandan.app.mediapipe` so this build installs alongside
  production `com.spandan.app`.
- `app/src/main/assets/blaze_face_short_range.tflite` (229,746 bytes, `TFL3` magic verified
  before committing) — downloaded from
  `storage.googleapis.com/mediapipe-models/face_detector/blaze_face_short_range/float16/1/`,
  the model MediaPipe's own Face Detector solution references.
- `FaceAnalyzer.kt`: new `useMediaPipeDetection: Boolean = false` + `context: Context?`
  constructor params, OFF by default (this project's standing "evidence before promotion"
  convention, same shape as `useMotionTracking`/`useCroppedDetection`). When true, real
  (un-skipped) detection frames run MediaPipe's `FaceDetector` (LIVE_STREAM mode) instead of
  ML Kit's `detector.process()` — the skip-detection/Kalman/motion-tracking machinery
  upstream and the `emitFaceDetected` ROI/averaging tail downstream are completely
  unchanged, only the "run a real detector" call itself is swapped.
- `ProfilingFaceAnalyzer.kt`: same `useMediaPipeDetection` swap (for a clean MediaPipe-only
  fps capture), PLUS an independent `logMediaPipeVsMlKitComparison: Boolean = false` flag —
  when true, ML Kit stays the PRIMARY detector (production behavior, unaffected), and on
  every real ML-Kit-detection frame MediaPipe ALSO runs on the SAME frame purely to log an
  IoU/center-distance comparison against ML Kit's own box. This is exactly the capability
  Segment 28's own doc flagged as missing ("`ProfilingFaceAnalyzer` does not yet log this")
  and is now built.
- `CoordinateMapper.kt`: new `mediaPipeSensorBoxToRotatedRect(...)`. MediaPipe's
  `Detection.boundingBox()` convention is the OPPOSITE of ML Kit's — confirmed by reading
  Google's own official `mediapipe-samples` repo (`examples/object_detection/android`'s
  `OverlayView.kt`, which applies its own rotation matrix to the box AFTER detection, around
  the MPImage's raw/unrotated dimensions). MediaPipe returns the box in the RAW SENSOR
  buffer's own pixel space, not the rotated/upright space ML Kit returns — this migration's
  own task brief explicitly warned not to assume the two match, and they don't. The new
  function is a thin RectF→Rect conversion followed by the EXISTING
  `sensorRectToRotatedRect` (a MediaPipe box already IS a "sensor-space" rect by this
  object's own terminology — no new rotation math needed).
- `MediaPipeImageConverter.kt` (new) — see "A real crash, and what it means" below.
- `MediaPipeVsMlKitComparator.kt` (new) — pure `intersectionOverUnion`/`centerDistance` rect
  math, unit-tested the way `CroppedDetectionStrategy`'s own pure math is.
- 12 new unit tests (`CoordinateMapperMediaPipeTest.kt`, 5; `MediaPipeVsMlKitComparatorTest.kt`,
  7) — 64 → 76 total, all passing. See "A deeper testability bug, found and fixed" below for
  a real production bug these tests surfaced along the way.

## A real crash, and what it means for "zero-copy"

The original design used `com.google.mediapipe.framework.image.MediaImageBuilder` directly
on the raw `android.media.Image` from `imageProxy.image` — zero-copy, no per-frame Bitmap
conversion, matching this project's own existing YUV-plane-direct philosophy
(`RoiPixelAverager`). `MediaImageBuilder`'s constructor accepts any `android.media.Image`
with no compile-time format check, so this looked safe and was even cross-checked against a
real third-party repo (`appexcoda/excoda`) that does the same thing.

**Confirmed wrong on-device, twice, reproducibly**: every `detectAsync` call crashed the app
(`com.spandan.app.mediapipe` process death, `errorType=crash`):

```
java.lang.UnsupportedOperationException: Android media image must use RGBA_8888 config.
	at com.google.mediapipe.framework.AndroidPacketCreator.createImage(AndroidPacketCreator.java:106)
	at com.google.mediapipe.tasks.vision.core.BaseVisionTaskApi.sendLiveStreamData(BaseVisionTaskApi.java:155)
	at com.google.mediapipe.tasks.vision.facedetector.FaceDetector.detectAsync(FaceDetector.java:344)
```

MediaPipe Tasks Vision's Android packet creator does not accept a raw YUV_420_888 image
through `MediaImageBuilder`/`detectAsync` at all — LIVE_STREAM or otherwise. In hindsight,
this explains why EVERY real-world example this segment's research read (Google's own
official `mediapipe-samples` Android helpers, `namdpran8/Ojas`) converts every frame to a
`Bitmap` before handing MediaPipe anything, instead of using `MediaImageBuilder` on the
camera's own YUV buffer — at the time that looked like avoidable overhead; it turned out to
be load-bearing.

Fixed via `MediaPipeImageConverter.yuv420ToArgb8888Bitmap(image)` (new file): a full-
resolution YUV→ARGB8888 conversion using the SAME rowStride/pixelStride-aware plane
indexing and BT.601 formula as `RoiPixelAverager.averageRgb` (per this task's own brief —
"reuse RoiPixelAverager... as the reference for correct plane handling"), just over every
pixel instead of a strided ROI average. `BitmapImageBuilder` wraps the result instead of
`MediaImageBuilder`.

**This conversion is the real cost this migration could not avoid, and it dominates the
fps result below.**

## Real on-device measurement (Galaxy A35, `RFCXC0FFFSN`, battery 77%, ~33°C)

Method: same as Segments 28/29 — `MainActivity.kt`'s one analyzer-construction line
temporarily swapped, rebuilt, installed, run with a face continuously in frame, `adb logcat`
captured, then reverted back to plain `FaceAnalyzer { ... }` and confirmed **byte-identical**
to `android/`'s own `MainActivity.kt` via a direct `diff` (this directory is untracked by
git, so a `git diff` against a prior commit isn't meaningful here — a direct file diff
against the known-good original is the equivalent check) before the final build.

### FPS (`useMediaPipeDetection=true`, MediaPipe as the sole detector)

45.03s capture, 909 frames (idx 243→1151), **0 missed-face frames**:

| Metric | Value |
|---|---|
| fps | **20.19** (909 frames / 45.03s) |
| Mean bundled `detectMs` (Bitmap conversion + `detectAsync` round trip) | **94.88ms** |
| `detectMs` range | 81.15 – 127.51ms (n=303 real detections) |

Segment 29's own ML Kit baseline (`minFaceSize=0.35`, same device): **23.7-23.84fps**,
**~19-25ms** mean real-detection cost. MediaPipe is slower on both axes, not faster —
directly contradicting the 2.94ms Pixel 6 benchmark that motivated this segment.

A follow-up diagnostic split (temporary extra `Log.d` around just the Bitmap conversion,
20s/138-sample capture, removed before the final commit) attributes the cost:

| Phase | Mean |
|---|---|
| YUV→ARGB8888 Bitmap conversion alone | **71.20ms** (43.65-263.14ms) |
| Bundled `detectMs` (same window) | 87.38ms |
| Implied `detectAsync`-only cost | **~16ms** |

**~81% of the total cost is the forced format conversion, not the detector.** The
`detectAsync`-only portion (~16ms) is roughly comparable to ML Kit's own ~19-25ms — meaning
BlazeFace itself may well be competitive on this hardware, but THIS integration path (a
pure-Kotlin, unvectorized, full-frame per-pixel YUV→RGB loop, forced by the RGBA_8888
requirement above) can't reach it. A native/vectorized conversion, `RenderScript`/
`android.graphics.ImageDecoder`-style hardware path, or CameraX's own
`ImageAnalysis.Builder().setOutputImageFormat(OUTPUT_IMAGE_FORMAT_RGBA_8888)` (not attempted
this session — would require reconfiguring the shared `ImageAnalysis` use case, which
`RoiPixelAverager`'s existing YUV-plane-direct code also depends on, so it is not a
drop-in change) are the directions a future session would need to test before this
conclusion could flip.

### Accuracy (`logMediaPipeVsMlKitComparison=true`, ML Kit stays primary; MediaPipe runs alongside for comparison only)

~40s capture, 189 comparison samples, **0 mismatches** (MediaPipe found a face on every
frame ML Kit did):

| Metric | Mean | Range |
|---|---|---|
| IoU (ML Kit box vs. MediaPipe box, same rotated space) | **0.617** | 0.50 – 0.70 |
| Center distance | **28.07px** | 19.45 – 33.96px |
| Top-edge offset (MediaPipe top − ML Kit top) | **+38.24px** | +28 – +47px |

The top-edge offset is the diagnostic finding: it is tight (19px spread across 189 samples)
and always the SAME sign — MediaPipe's box consistently starts ~38px LOWER (further down the
face) than ML Kit's, not random noise. `RoiCalculator.foreheadRoiFrom` derives the forehead
ROI as the TOP 10-30% of the face box, anchored to `faceBox.top` — a systematically-lower
`top` therefore systematically mis-places the forehead ROI further down the face (toward the
eyebrows/eyes), independent of whether the coordinate-space transform itself is correct.
This was independently confirmed by direct visual observation during testing (the on-screen
ROI overlay did not look like it was tracking the forehead) before the numeric comparison
capture was even run — the numbers explain what was already visible, not the other way
around. Sample boxes (rotated space, `[left,top,right,bottom]`):

```
mlKitBox=[161,245,328,412]  mediaPipeBox=[179,282,323,426]
mlKitBox=[157,234,317,394]  mediaPipeBox=[169,264,316,411]
```

A moderate IoU (never below 0.50) means MediaPipe is finding roughly the right face at
roughly the right scale — this is not a coordinate-space bug (the rotation math in
`mediaPipeSensorBoxToRotatedRect` is doing something sane, not returning garbage) — it looks
like BlazeFace's own box convention (anchor/keypoint-derived, not a full face-contour box)
genuinely does not extend as far up the forehead as ML Kit's does. This was not verified
against MediaPipe's own model documentation this session; flagged as the most likely
explanation, not a certainty.

## A deeper testability bug, found and fixed

Writing `CoordinateMapperMediaPipeTest.kt` surfaced that `CoordinateMapper.
rotatedRectToSensorRect`/`sensorRectToRotatedRect` build their return value via the 1-arg
`Rect(Rect)` COPY constructor (their `0`/`else` branches) and the 4-arg `Rect(l,t,r,b)`
constructor (every other branch) — BOTH are no-ops under this project's plain-JUnit harness
(`isReturnDefaultValues = true`), not just the 4-arg form `CroppedDetectionStrategyTest`'s
own header already documented. This is a DEEPER version of the gap Segment 28 flagged (that
segment only found the TEST's own input construction was vacuous; this means the PRODUCTION
functions themselves returned an all-zero `Rect` regardless of rotation or input, for ANY
caller, under test). Fixed at the root: both functions now build their return value via a
new private `makeRect` helper (no-arg constructor + field assignment, matching
`CroppedDetectionStrategy`'s own established convention) — real-device behavior is
unchanged (plain field assignment either way), this only makes the functions testable for
the first time.

This exposed a second, consequential effect: `CoordinateMapperTest`'s existing round-trip
test had been passing as a DOUBLE-vacuous 0-equals-0 coincidence (input always zeroed via
the 4-arg constructor, output always zeroed via the same bug) — fixing only the production
side made that existing test start FAILING for real (a genuinely-zeroed input rect sits
exactly on `clampToBounds`'s own zero-area edge case, so it no longer round-trips cleanly).
Since this was directly caused by this segment's own change, fixing it was in scope (unlike
Segment 28's own "flagged, not fixed" call) — `CoordinateMapperTest`'s `original` rect is now
built the same `rectOf` no-arg-plus-field-assignment way `CroppedDetectionStrategyTest`
already does, so it finally exercises real random rects instead of always comparing zero to
zero.

## Honest verdict: NOT PROMOTED

`useMediaPipeDetection` and `logMediaPipeVsMlKitComparison` both stay `false` everywhere
they were added — this is a clean negative result, not an inconclusive one:

- **Slower**: ~20.2fps vs. ML Kit's Segment 29 baseline of ~23.7-23.84fps, and the gap is
  attributable to a specific, understood cause (the forced Bitmap conversion), not noise —
  unlike Segment 28's candidates, which mostly landed inside baseline's own measurement
  noise band.
- **Systematically less accurate for this app's specific downstream need**: a real,
  quantified, consistent ~38px top-edge bias that mis-places the forehead ROI, independently
  confirmed by direct visual observation, not just an IoU number taken on faith.
- **A faster-but-wrong box would not have been a win even if the fps numbers had favored
  MediaPipe** — this segment's own accuracy-comparison instrumentation (built specifically
  because Segment 28's doc flagged its absence as a gap) is what makes that claim checkable
  rather than assumed.

Google's own 2.94ms Pixel 6 benchmark is not wrong, but it measures the model in isolation,
not this specific CameraX-YUV-to-MediaPipe integration path on this specific device — the
gap between "a published benchmark" and "this app's own measured reality" is exactly the
kind of thing this project's own "evidence before promotion" convention exists to catch.

**What would make a future re-attempt worth trying**: (1) a fast/native/vectorized YUV→RGBA
conversion (or CameraX's native `OUTPUT_IMAGE_FORMAT_RGBA_8888`, which would require
reconciling with `RoiPixelAverager`'s own YUV-plane assumption) to remove the ~71ms
conversion tax and see whether the underlying ~16ms `detectAsync` cost holds up under
repeated measurement; (2) checking MediaPipe's own model documentation/GitHub issues for
BlazeFace's documented bounding-box convention relative to the forehead, to confirm or
refute this segment's own hypothesis for the +38px offset, rather than inferring it only
from this session's own data; (3) more captures per config (this segment ran one steady-
state capture per mode, not Segment 18's own three-capture discipline), given the ~28-127ms
detectMs spread observed even within a single capture.

## Files touched (all inside `android_segment30_mediapipe/`, `android/` untouched)

- `app/build.gradle.kts` (applicationId suffix, `tasks-vision:1.0.0` dependency)
- `app/src/main/assets/blaze_face_short_range.tflite` (new)
- `app/src/main/java/com/spandan/app/camera/FaceAnalyzer.kt` (wired `useMediaPipeDetection`)
- `app/src/main/java/com/spandan/app/camera/ProfilingFaceAnalyzer.kt` (wired
  `useMediaPipeDetection` + `logMediaPipeVsMlKitComparison`)
- `app/src/main/java/com/spandan/app/camera/CoordinateMapper.kt` (new
  `mediaPipeSensorBoxToRotatedRect`; `makeRect` testability fix to the two existing
  rotation functions)
- `app/src/main/java/com/spandan/app/camera/MediaPipeImageConverter.kt` (new)
- `app/src/main/java/com/spandan/app/camera/MediaPipeVsMlKitComparator.kt` (new)
- `app/src/test/java/com/spandan/app/camera/CoordinateMapperMediaPipeTest.kt` (new)
- `app/src/test/java/com/spandan/app/camera/MediaPipeVsMlKitComparatorTest.kt` (new)
- `app/src/test/java/com/spandan/app/camera/CoordinateMapperTest.kt` (input-construction fix,
  consequence of the `makeRect` fix above)
- `app/src/main/java/com/spandan/app/MainActivity.kt` (temporarily swapped for measurement,
  reverted — confirmed byte-identical to `android/`'s own copy before the final commit)
