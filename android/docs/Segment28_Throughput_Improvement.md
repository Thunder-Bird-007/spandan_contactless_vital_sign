# Segment 28 — Camera Throughput Improvement Attempt

Continues Segment 18's own line (`Segment18_Camera_Throughput_And_Buffer_Window.md`,
whose "Honest verdict" section is unchanged, not rewritten — read it first for the
baseline this segment starts from: 19.96fps at `useMotionTracking=false`, 16.33fps at
`useMotionTracking=true`, and the leading, never-confirmed hypothesis that
`OpticalFlowFaceTracker.track()`'s per-skipped-frame `IntArray` allocations were costing
real wall-clock throughput despite looking cheap in their own `SystemClock` timing).

**No physical Android device was attached this session** (`adb devices` returned an empty
list, checked at the start of this segment and again after all code changes below). Every
item in this doc is therefore a code change plus unit tests, or a note on what remains
unmeasured — never a fabricated or assumed fps number. Nothing below changes a shipped
default; every new lever stays off unless a caller explicitly opts in, same convention as
`useMotionTracking`, `useConfidenceGate`, `useWaveletDenoise`.

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

**Not yet measured**: whether this actually closes the 19.96→16.33fps gap Segment 18
found. That requires the same three-capture re-measurement protocol Segment 18's own Task
3 used, on a physical device.

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
  same code path rather than a separate one). NOT unit-tested (needs a real `ImageProxy`)
  and NOT exercised on a physical device this session.
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

## What was NOT attempted this session, and why

Every item below from the original task list needs a physical device to produce a real
number, which this session did not have:

- **Re-measuring the allocation fix's actual fps impact** (Segment 18's own three-capture
  protocol).
- **Measuring `CroppedDetectionStrategy`'s actual `cropMs` vs. full-frame `detectMs`**,
  and its miss rate / IoU-vs-next-real-detection accuracy (both already instrumented in
  `ProfilingFaceAnalyzer`, ready to run).
- **Downscaled-detection's actual detect-time-vs-miss-rate tradeoff** (same
  `croppedDetectionDownscaleFactor` knob, needs the same capture).
- **Retrying `DETECT_EVERY_N_FRAMES` at 4/5** once the above are measured — no code change
  needed here (it is already a single constant in `FaceAnalyzer.kt`/`ProfilingFaceAnalyzer.kt`),
  just a re-measurement once a cheaper tracker/detector makes more aggressive skipping
  worth trying.
- **Combining winning candidates and picking final defaults for `useMotionTracking`,
  `useCroppedDetection`, `croppedDetectionDownscaleFactor`, and `DETECT_EVERY_N_FRAMES`.**
  None of these defaults were changed this session — all stay at their prior, unmeasured-here
  values, per this project's own "off by default, evidence before promotion" convention.

## Measurement protocol for the next session with device access

Same as Segment 18 Task 3, extended for the new phase:

1. Swap `MainActivity.kt`'s analyzer construction to
   `ProfilingFaceAnalyzer(useMotionTracking = ..., useCroppedDetection = ..., croppedDetectionDownscaleFactor = ...) { ... }`.
2. `adb logcat -s ProfilingFaceAnalyzer:D` for a steady-state capture (face continuously in
   frame, same duration/lighting discipline as Segment 18's captures).
3. Parse the `SPANDAN_PROFILE` lines for `cropMs` alongside the existing
   `detectMs`/`roiMs`/`motionMs`/`otherMs`, and `dumpSummary()`'s `missRate=x/y` line.
4. For any candidate that changes what box gets used (cropped detection, motion tracking),
   also log IoU or center-distance between the box actually used and the NEXT full-frame
   detection's box — a faster-but-wrong box is not a win. Not yet implemented as of this
   segment; flagged as the next code addition before trusting a capture's fps number alone.
5. Revert the `MainActivity.kt` swap and confirm via `git diff` that the revert is clean,
   same discipline Segment 18 already used.

## Files touched

- `android/app/src/main/java/com/spandan/app/camera/OpticalFlowFaceTracker.kt` (allocation
  fix)
- `android/app/src/main/java/com/spandan/app/camera/CroppedDetectionStrategy.kt` (new)
- `android/app/src/test/java/com/spandan/app/camera/CroppedDetectionStrategyTest.kt` (new)
- `android/app/src/main/java/com/spandan/app/camera/FaceAnalyzer.kt` (wired
  `useCroppedDetection`)
- `android/app/src/main/java/com/spandan/app/camera/ProfilingFaceAnalyzer.kt` (wired
  `useCroppedDetection` + `cropMs`)
