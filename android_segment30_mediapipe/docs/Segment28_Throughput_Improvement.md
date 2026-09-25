# Segment 28 — Camera Throughput Improvement Attempt

Continues Segment 18's own line (`Segment18_Camera_Throughput_And_Buffer_Window.md`,
whose "Honest verdict" section is unchanged, not rewritten — read it first for the
baseline this segment starts from: 19.96fps at `useMotionTracking=false`, 16.33fps at
`useMotionTracking=true`, and the leading, never-confirmed hypothesis that
`OpticalFlowFaceTracker.track()`'s per-skipped-frame `IntArray` allocations were costing
real wall-clock throughput despite looking cheap in their own `SystemClock` timing).

**No physical Android device was attached when the code changes below were written** (`adb
devices` returned an empty list, checked repeatedly). A device (the same Samsung Galaxy A35,
`RFCXC0FFFSN`, Segment 18/19's own device) was connected later in this same session, and the
real on-device measurement below was then run against it — see "Real on-device measurement"
for the numbers and honest verdict. Nothing in this segment changes a shipped default; every
new lever stays off unless a caller explicitly opts in, same convention as
`useMotionTracking`, `useConfidenceGate`, `useWaveletDenoise` — the measurement below found
no candidate clearly beating the existing baseline strategy given this session's own
measured session-to-session noise, so none was promoted.

## What was fixed: `OpticalFlowFaceTracker`'s per-skipped-frame allocations

Segment 18's own leading hypothesis. `track()` used to call the private `sampleGrid()`
twice per skipped frame (once for the search-window sample, once for the post-shift
resample), each allocating a fresh `IntArray`. Rewritten so `searchScratch` and
`resampleScratch` are class-level buffers, reused via a `size`-matching check
(`obtainBuffer`), and the committed reference patch is updated via `System.arraycopy`
into its own persistent buffer rather than by reassigning it to point at a scratch array
(that aliasing would let a sample that fails partway through a future frame silently
corrupt the last-known-good reference — kept the buffers un-aliased specifically to avoid
that). Steady-state (constant face-box grid dimensions between resets), this eliminates
essentially all allocation inside `track()`.

`OpticalFlowMatcherTest.kt` (the pure SAD-matching math, unaffected by this change) still
passes unchanged, 49/49 → 57/57 total unit tests pass after this segment's additions (see
below).

**Measured** (see "Real on-device measurement" below): yes, this closes the gap. Segment
18 found `useMotionTracking=true` a clear, reproducible regression (16.33fps vs a 19.19-
19.96fps baseline bracketing it). This session's re-measurement found `useMotionTracking=true`
at 21.27fps against a same-session baseline that itself ranged 18.80-21.45fps across two
captures — i.e. motion tracking now sits inside the baseline's own noise band, no longer a
measurable regression.

## What was added: `CroppedDetectionStrategy` (new candidate, off by default)

A genuinely new lever, not a re-test of anything already tried: on a skipped-detection
frame, run REAL ML Kit detection on a small, padded crop around the last known face box,
instead of either freezing the box (the plain default) or estimating its motion
(`useMotionTracking`). A smaller `InputImage` should cost `detector.process()` less than
the full-frame call every un-skipped frame already pays — untested assumption, see below.

- `CroppedDetectionStrategy.paddedCropRect` / `.remapCropRectToSensorRect` — pure rect
  math (padding, even-alignment for YUV 4:2:0 chroma subsampling, sensor-bounds clamping,
  and the inverse offset back into full-frame space). Unit-tested in
  `CroppedDetectionStrategyTest.kt` the way `CoordinateMapperTest.kt` tests
  `CoordinateMapper`'s own rect math (8 tests: padding math, bounds clamping, even-ness
  invariant, containment invariant, offset math, and a crop→detect→remap round trip).
- `CroppedDetectionStrategy.extractCroppedNv21` / `.buildCroppedInputImage` — the
  Android-dependent half: manually extracts an NV21 byte array for just the crop region
  out of the `ImageProxy`'s YUV_420_888 planes (same rowStride/pixelStride-aware indexing
  convention `RoiPixelAverager`/`OpticalFlowFaceTracker` already use — planes are NOT
  guaranteed contiguous), optionally subsampled by an integer `downscaleFactor` (stride
  skipping, satisfying this segment's "try a downscaled detection input" item with the
  same code path rather than a separate one). NOT unit-tested (needs a real `ImageProxy`),
  exercised on a physical device below.
- Wired into `FaceAnalyzer.kt` behind a new `useCroppedDetection` constructor flag
  (default `false`), plus `croppedDetectionPaddingFraction` (default 0.5) and
  `croppedDetectionDownscaleFactor` (default 1, i.e. off). Takes priority over
  `useMotionTracking` on a skipped frame when both are somehow true — an arbitrary
  precedence choice, not a measured one, since the two were never run together. After
  `MAX_CONSECUTIVE_CROPPED_MISSES` (3) consecutive no-face results from the cropped path,
  the *next* skipped frame forces a full-frame detection instead of another crop attempt,
  so a subject who moved out of the cropped region (or left and re-entered frame) gets
  reacquired rather than staying stuck.
- Mirrored into `ProfilingFaceAnalyzer.kt` with a new `cropMs` timing phase (the combined
  cost of building the cropped `InputImage`, NV21 extraction included, plus
  `detector.process()` on it) and a `cropMissCount` counter, so the measurement protocol
  below is ready to run the moment a device is available — nothing further to build first.

### A real bug found and fixed while building this: `Rect`'s 4-arg constructor is a no-op under this project's unit-test harness

While writing `CroppedDetectionStrategyTest.kt`, every test that constructed a `Rect` via
`Rect(left, top, right, bottom)` and checked its fields failed with the fields reading
back as `0` regardless of the arguments passed. Probed directly: `android.graphics.Rect`'s
4-arg constructor body is stubbed to a no-op under `app/build.gradle.kts`'s
`testOptions.unitTests.isReturnDefaultValues = true` (needed elsewhere for `Log.d`/`.w`
calls to return harmlessly instead of throwing) — the object allocates, but no field gets
set. Direct field assignment (`rect.left = x`) is real field access, never stubbed, and
works fine.

**This means `CoordinateMapperTest.kt` — this project's own existing rect-math test —
has been passing vacuously.** It builds its test rects via the same 4-arg constructor, so
every rect it constructs has all-zero fields regardless of the random values generated,
and its round-trip assertions compare zero against zero every time. The functions under
test (`CoordinateMapper.rotatedRectToSensorRect`/`sensorRectToRotatedRect`) are not
actually broken by this — on a real device, the real `Rect` constructor works normally,
so production behavior is unaffected — but that test has never verified them.

Out of this segment's scope to fix `CoordinateMapper.kt`/`CoordinateMapperTest.kt`
themselves (untouched, per this session's own don't-touch-outside-the-four-actions
discipline), but flagged here plainly rather than left for someone to discover by
surprise. `CroppedDetectionStrategy.kt`'s own two pure rect functions build their return
values via a private `makeRect` helper (no-arg constructor + field assignment) instead,
and `CroppedDetectionStrategyTest.kt` builds every INPUT rect the same way (a `rectOf`
test helper), so this segment's own new test is not affected by the same gap.

## Real on-device measurement

A device was connected later in this session (same Samsung Galaxy A35, `RFCXC0FFFSN`).
Method: `MainActivity.kt`'s one analyzer-construction line was temporarily swapped to
`ProfilingFaceAnalyzer(...)`, rebuilt, installed, run with a face continuously in frame
(confirmed per-capture: `face=false` count was 0 in every capture below), `adb logcat -s
ProfilingFaceAnalyzer:D` captured to a file for ~40s steady-state per config, then reverted
back to plain `FaceAnalyzer { ... }` and confirmed clean via `git diff` (empty) before
rebuilding the final production APK. Battery 78-80%, temperature ~34°C throughout (checked
before starting, not concerning).

| Capture | Config | Frames | Span | **fps** | Mean real-detectMs | Mean skip-phase cost |
|---|---|---|---|---|---|---|
| 1 | baseline (both flags off) | 840 | 44.69s | **18.80** | 88.20ms | n/a |
| 2 | `useMotionTracking=true` | 894 | 42.03s | **21.27** | 91.61ms | motionMs 0.43ms (max 3.73ms) |
| 3 | `useCroppedDetection=true`, downscale=1 | 552 | 42.06s | **13.12** | 90.27ms | cropMs 66.33ms (max 308.70ms) |
| 4 | `useCroppedDetection=true`, downscale=2 | 858 | 42.13s | **20.37** | 93.33ms | cropMs 18.52ms (max 159.09ms) |
| 5 | baseline re-check | 903 | 42.10s | **21.45** | 87.89ms | n/a |

### Honest verdict: the allocation-fix regression is resolved; no candidate demonstrated a clear win over baseline

**Captures 1 and 5 are the same config, measured ~4 minutes apart, and disagree by 14%**
(18.80 vs 21.45fps) — this session's own baseline is not stable enough to treat a single
comparison capture as ground truth. Reading the other candidates against that noise band
rather than against a single baseline number:

- **`useMotionTracking=true` (Capture 2, 21.27fps) sits inside the baseline's own observed
  range (18.80-21.45fps).** This is the real, meaningful result: Segment 18 found this
  config a clear, reproducible regression (16.33fps against a 19.19-19.96fps baseline
  bracketing it, no overlap) — that regression is gone. It cannot be claimed as a
  *win* over baseline from this data (motion tracking's own `motionMs` cost, 0.43ms mean,
  is negligible either way), but the fix did what Segment 18's hypothesis predicted.
- **`useCroppedDetection=true` at downscale=1 (Capture 3, 13.12fps) is a clear loss** —
  well outside the baseline noise band in the wrong direction. `cropMs` averaged 66.33ms,
  not much cheaper than a full-frame `detectMs` (~88-93ms across every capture), and spiked
  to 308.70ms at least once — plausibly the manual NV21 extraction's per-pixel loop, or ML
  Kit reallocating internal buffers for a differently-shaped `InputImage` on every call
  (never profiled further this session).
- **`useCroppedDetection=true` at downscale=2 (Capture 4, 20.37fps) also lands inside the
  baseline noise band** — `cropMs` dropped to 18.52ms mean (still not cheap the way
  `motionMs` is), but the 159.09ms max outlier is a real concern for a per-frame budget at
  ~20fps (~50ms/frame) that this session did not investigate further.

**No new default was promoted.** `useMotionTracking` and `useCroppedDetection` both stay
`false`, `croppedDetectionDownscaleFactor` stays `1`, `DETECT_EVERY_N_FRAMES` stays `3` —
none of this session's candidates cleared the bar of a reproducible improvement over the
baseline's own measured noise, which is exactly the standard Segment 18 already set
(`useMotionTracking` stayed off there too, for the mirror-image reason: a reproducible
*regression*). The final APK installed on-device is the plain-`FaceAnalyzer` production
build (all of this segment's code fixes included, no flags flipped from their defaults).

**What would make this measurement more conclusive** (not done this session, next-session
work): more captures per config (3+, matching Segment 18's own three-capture discipline,
rather than one baseline pair bracketing one candidate each), randomized/interleaved
capture order to average out monotonic warm-up drift instead of letting it alias with
"which config ran first," and IoU/center-distance logging between the box a candidate
actually used and the next real detection's box (`ProfilingFaceAnalyzer` does not yet log
this — flagged, not built, this session) so a faster-but-wrong box would be visible rather
than just assumed absent from the fps number alone.

## Files touched

- `android/app/src/main/java/com/spandan/app/camera/OpticalFlowFaceTracker.kt` (allocation
  fix)
- `android/app/src/main/java/com/spandan/app/camera/CroppedDetectionStrategy.kt` (new)
- `android/app/src/test/java/com/spandan/app/camera/CroppedDetectionStrategyTest.kt` (new)
- `android/app/src/main/java/com/spandan/app/camera/FaceAnalyzer.kt` (wired
  `useCroppedDetection`)
- `android/app/src/main/java/com/spandan/app/camera/ProfilingFaceAnalyzer.kt` (wired
  `useCroppedDetection` + `cropMs`)
