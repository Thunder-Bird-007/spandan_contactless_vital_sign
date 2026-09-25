# Segment 18 — Camera Throughput + Buffer Window Revisit

Run 2026-09-15/16. Real on-device measurement, Samsung Galaxy A35 (`SM-A356E`,
`RFCXC0FFFSN`), the same device used throughout this project. No device was attached at
the start of this session; work proceeded on everything that didn't need one, and the
device was attached partway through once asked for — see the on-device sections below
for exactly what that unlocked.

## Context

Action 6a (documented in `SESSION_HANDOFF.md` and `Segment7_Task_G_Throughput_Profiling.md`)
already added an every-Nth-frame (N=3) ML Kit detection-skip with last-box reuse in
between, measured real: **13.44fps → 21.40fps steady-state (~1.59x)**, short of the naive
3x projection — meaning something *other* than ML Kit detection eats a meaningful share
of per-frame time once detection got cheaper. This task's brief was to (1) profile the
current path to find what's actually capping throughput now, (2) try replacing the
frozen-box reuse with real inter-detection tracking, (3) re-measure real fps, (4) revisit
`SignalBuffer.WINDOW_DURATION_SECONDS` given whatever fps results, and (5) NOT
re-investigate GC jitter (already closed, see `android/README.md`'s own SPANDAN_TIMING
diagnostic, CV=0.063, zero bursty gaps).

## Task 1 — profile the current path

`ProfilingFaceAnalyzer.kt` has gone stale twice before this project's history (still
detecting every frame after `FaceAnalyzer.kt` gained the N=3 skip). Checked again this
session, per the task's own "re-sync before trusting a new capture" instruction — **found
already in sync this time**, no update needed before profiling.

Read `camera/RoiPixelAverager.kt` and `signal/RealHeartRateEstimator.kt` directly (not
re-profiled with new instrumentation, since Segment 7 Task G's own per-phase timing split
already isolates exactly this): ROI averaging is a stride-2 pixel loop over a small
forehead crop, and the HR/SpO2 recompute is gated to at most once/second and independent
of the per-frame camera-analysis callback. Neither is a plausible new bottleneck; nothing
in this task's own on-device captures (below) contradicts that — `roiMs` stayed
sub-5ms and `otherMs` sub-2ms throughout every capture, ML Kit detection remained the
overwhelmingly dominant cost.

## Task 2 — real inter-detection tracking (gated, off by default)

Two new files, deliberately NOT a KLT/optical-flow-library tracker: `matlab/docs/
Segment7_Task_D_Landmark_ROI.md`'s own finding (a KLT-tracked ROI net-regressing the
MATLAB pipeline's accuracy, 4/5→2/5 subjects above the notch-confidence bar) was a direct
reason to keep this simpler.

- **`camera/OpticalFlowMatcher.kt`** — pure integer-grid brute-force SAD (sum-of-absolute-
  differences) block matching. No Android dependency at all; unit-tested
  (`OpticalFlowMatcherTest.kt`) against synthetic shifted patches with and without noise,
  a zero-search-radius identity check, and a flat-patch rejection check (a blank/uniform
  reference patch returns `null` rather than a confident-looking but meaningless offset).
- **`camera/OpticalFlowFaceTracker.kt`** — the Android wrapper: samples an 8px-stride luma
  grid from the Y-plane around the last known face box (in SENSOR-space pixel
  coordinates, the only space the buffer actually lives in), matches it against a stored
  reference patch via `OpticalFlowMatcher`, and incrementally re-anchors at the new
  position each call. Re-anchored fully on every REAL detection (`reset()`), so drift is
  bounded to at most the 1-2 skipped frames between real detections, never longer.
- **`camera/CoordinateMapper.kt`** gained `sensorRectToRotatedRect` — the mathematical
  inverse of the existing (already-relied-upon) `rotatedRectToSensorRect`, needed because
  tracking happens in sensor space but every other consumer (`RoiCalculator`, the overlay)
  expects the rotated-image space ML Kit itself uses. Derived by hand for all four
  rotation values and verified via a random-rect round-trip property test
  (`CoordinateMapperTest.kt`, 200 random rects × 4 rotations) before trusting it on a real
  device — no device was available yet when this function was written, so this test was
  the only verification possible at that point.
- **`camera/FaceAnalyzer.kt`** gained a `useMotionTracking: Boolean = false` constructor
  parameter (placed before `onResult` so the existing trailing-lambda call site in
  `MainActivity.kt` needed no change). When `false` (the default, unchanged from before
  this task), `motionTracker` is `null`, `trackViaMotionEstimate` immediately returns
  `null`, and the skipped-frame box is always `staleFaceBox` — byte-for-byte the prior
  behavior. When `true`, the tracker's result (if non-null) replaces the frozen box.
- **`camera/ProfilingFaceAnalyzer.kt`** was updated to mirror this exactly (same
  `useMotionTracking` param, plus a new `motionMs` fourth profiling phase so a capture can
  see the tracker's own real cost alongside `detectMs`/`roiMs`/`otherMs`).

## Task 3 — real re-measurement (three back-to-back captures, same device/session)

Method: `MainActivity.kt`'s one analyzer-construction line was temporarily swapped to
`ProfilingFaceAnalyzer(useMotionTracking = ...) { ... }`, rebuilt, installed, run with a
face continuously in frame, `adb logcat -s ProfilingFaceAnalyzer:D` captured to a file,
then the wiring was reverted back to plain `FaceAnalyzer { ... }` and rebuilt/reinstalled
to confirm the revert (`git diff` on `MainActivity.kt` shows a pure addition, zero
deletions — the analyzer-construction line itself is identical to before this task).

**Capture 1 — baseline, `useMotionTracking=false`:**

| | value |
|---|---|
| Steady-state window (last 40s) | 798 frames, 39.93s |
| **fps** | **19.96** |
| Skip fraction | 66.7% (matches N=3's ideal ratio) |
| Mean detectMs (real-detect frames only) | 73.35ms |
| Mean totalMs (all frames) | 26.07ms |

**Capture 2 — `useMotionTracking=true`:**

| | value |
|---|---|
| Steady-state window (last 40s) | 654 frames, 39.98s |
| **fps** | **16.33** |
| Skip fraction | 66.7% |
| Mean detectMs (real-detect frames only) | 80.08ms |
| Mean motionMs (skipped frames) | 0.874ms (max observed: 7.35ms) |

**Capture 3 — baseline re-check, `useMotionTracking=false` again (to isolate thermal/session drift):**

| | value |
|---|---|
| Steady-state window (last 30s) | 573 frames, 29.81s |
| **fps** | **19.19** |
| Mean detectMs (real-detect frames only) | 80.86ms |

### Honest verdict: a real throughput regression, NOT fully explained by thermal drift, NOT adopted

Captures 1→2 look, at first glance, consistent with simple session/thermal drift: raw ML
Kit `detectMs` itself rose 73.35→80.08ms between the two captures (a component the
tracker never touches, since it only runs on *skipped* frames), and a warmer phone after
several minutes of continuous camera use is a completely plausible cause of that rise on
its own.

**But Capture 3 rules that explanation out as the *whole* story.** It shows `detectMs`
*matching* Capture 2's elevated level (80.86 vs 80.08ms) — i.e. the same thermal/session
state — while `useMotionTracking` was back to `false`. If the fps drop in Capture 2 were
purely thermal, Capture 3 should have shown a similarly depressed fps. It didn't: **19.19
fps**, close to Capture 1's 19.96, not Capture 2's 16.33.

So something about `useMotionTracking=true` itself costs real end-to-end throughput —
**despite the tracker's own `SystemClock`-measured cost being negligible** (0.874ms mean,
max 7.35ms, against a ~62ms whole-frame budget at 16fps). That is a genuine, unrounded-up
contradiction worth stating plainly rather than smoothing over: the instrumentation
inside the tracker says it's cheap, but the measured wall-clock fps says otherwise.

**Leading hypothesis, NOT proven this session**: `OpticalFlowFaceTracker.track()`
allocates two new `IntArray`s every skipped frame (the search-window sample and the
re-anchored reference-patch resample). At 16-20fps with ~2 skips per real-detection cycle,
that's a real, if small, per-frame allocation rate — GC pauses from that pressure can land
in the surrounding scheduling gaps (CameraX's `ImageAnalysis` callback dispatch, or the
`STRATEGY_KEEP_ONLY_LATEST` frame-drop logic) rather than inside the exact `motionMs`
timing window that measures only the matcher call itself, which would make the tracker
look cheap in its own logs while still costing real wall-clock throughput. This is a
plausible mechanism, not a measured one — this session had no heap/allocation profiling
tool available to confirm it.

**Recommendation: `useMotionTracking` stays off by default** (unchanged — it always was).
This is a real, honest negative result: implemented, unit-tested at the pure-math layer,
and real-device-measured to genuinely cost more throughput than it saves in ROI accuracy
benefit (which itself was never separately validated this session — no ground-truth face
position was available to confirm the tracker actually reduces staleness error, only that
it runs without crashing). A future session revisiting this should profile with a real
allocation/GC tool (e.g. Android Studio's Memory Profiler) before assuming the hypothesis
above, and should also independently validate the accuracy side (does tracking actually
reduce ROI positional error between detections?) before any promotion — currently neither
side of the cost/benefit tradeoff supports turning this on.

## Task 4 — buffer window revisit

`SignalBuffer.WINDOW_DURATION_SECONDS` (currently `25.0`) is **kept unchanged**. This
session's real measured baseline fps (19.19-19.96fps across two captures) sits close to
the previously documented 21.40fps figure (Segment 7 Task G's own re-measurement) — real
device/session-to-session variance, same order of magnitude, same underlying N=3
mechanism, not a regression of anything already adopted. Nothing in this session's data
changes Segment 16 Task 1's own accuracy-vs-responsiveness tradeoff analysis (25s is a
deliberate middle ground between the original 10s and MATLAB's ~80s validated clips), so
there's no new evidence to act on here.

**A real interaction with Segment 19 is worth stating explicitly, since it's no longer
theoretical**: Branch 2's `MorphologyBandpassFilter` needs `fs` comfortably above 16Hz for
its `'wide'` 0.5-8Hz band to be admissible under Nyquist. This session's live camera fs
varied **14.16-22.08Hz** during actual use (see Segment 19's own on-device capture) —
meaning the wide/mid band-mode fallback this task's brief anticipated is a **real,
frequently-exercised code path** on this hardware, not a hypothetical edge case. A future
throughput improvement that reliably pushed fs above ~17-18Hz would have a real, direct
benefit for Branch 2's morphology quality, independent of anything HR/SpO2-side.

## Task 5 — GC jitter

**Explicitly NOT re-investigated**, per this task's own instruction that it was already
closed (a 45s SPANDAN_TIMING capture previously showed CV=0.063, zero bursty gaps). The
throughput regression found in Task 3 above is a DIFFERENT question (a new code path's
own real cost), not a re-opening of that closed jitter investigation.

## Files touched

New: `camera/OpticalFlowMatcher.kt`, `camera/OpticalFlowFaceTracker.kt`,
`app/src/test/java/com/spandan/app/camera/OpticalFlowMatcherTest.kt`,
`app/src/test/java/com/spandan/app/camera/CoordinateMapperTest.kt`.

Modified (additive only — default behavior unchanged): `camera/CoordinateMapper.kt` (new
`sensorRectToRotatedRect` function), `camera/FaceAnalyzer.kt` (new `useMotionTracking`
param, default `false`), `camera/ProfilingFaceAnalyzer.kt` (mirrored, plus a new
`motionMs` profiling phase). `MainActivity.kt`'s final committed state is unchanged from
before this task (confirmed via `git diff` showing zero deletions on that file from this
segment).
