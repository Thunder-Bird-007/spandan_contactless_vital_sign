# Segment 29 — ML Kit `minFaceSize` Tuning + Kalman Box Tracking

Follows a research pass (papers + GitHub) run after Segment 28 found no candidate there
(`useMotionTracking`, `useCroppedDetection`) demonstrated a clear win over baseline. The
research's top two ranked, lowest-risk recommendations were tried here: (1) raise ML Kit's
`FaceDetectorOptions.minFaceSize` (Google's own docs: a larger value lets the detector skip
pyramid levels and run faster) and (2) a constant-velocity Kalman filter over box geometry
(a different risk class from Segment 18/28's pixel-content trackers, standard in
multi-object tracking). Both were measured on-device (same Galaxy A35, `RFCXC0FFFSN`) and,
unlike Segment 28's candidates, **both are promoted to the production default.**

## What was built

- `FaceAnalyzer`/`ProfilingFaceAnalyzer`: new `minFaceSize: Float` constructor parameter,
  threaded into `FaceDetectorOptions.Builder().setMinFaceSize(...)`.
- `KalmanBoxTracker.kt` (new): a constant-velocity Kalman filter over the face box's center
  x/y, width, height, decomposed into four independent 1D filters (`Kalman1D`) rather than
  one coupled 8-state filter — mathematically equivalent under the diagonal-process-noise
  simplification used here, far simpler to implement/verify. Never reads pixel content, so
  it cannot inherit the skin-texture/lighting drift failure mode
  `matlab/docs/Segment7_Task_D_Landmark_ROI.md` documented for a KLT-tracked ROI — a
  genuinely different mechanism from `OpticalFlowFaceTracker`, not a variant of it.
  `predict()` must be called once per frame (skipped or real) to keep the internal dt=1
  time base consistent; `correct()` fuses a real detection in immediately after `predict()`.
- 7 new unit tests (`KalmanBoxTrackerTest.kt`): `Kalman1D` against synthetic constant-
  velocity motion (converges, tracks the true velocity) and synthetic measurement noise
  (reduces mean absolute error vs. the raw noisy signal); `KalmanBoxTracker`'s box-geometry
  wiring (null before first correction, hard-init on first correction, extrapolates a moving
  box in the right direction after several correction steps, forgets state on `clear()`).
  64/64 total unit tests pass (57 → 64).
- Wired into both analyzers with `useKalmanTracking` taking priority over `useMotionTracking`
  on a skipped frame (arbitrary precedence — the two were never measured together);
  `useCroppedDetection` still takes priority over both, unchanged from Segment 28.

## Real on-device measurement

Method: same as Segment 28 — `MainActivity.kt`'s analyzer swapped to `ProfilingFaceAnalyzer`,
rebuilt, installed, run with a face continuously in frame, `adb logcat` captured per config,
reverted to plain `FaceAnalyzer` and confirmed clean via `git diff` before the final build.
Learning from Segment 28's own noise-band finding (baseline swung 18.80-21.45fps across two
captures there), baselines were captured immediately before AND after the `minFaceSize`
candidate this time, bracketing it rather than relying on one distant comparison point.

| Capture | Config | Frames | fps | Mean real-detectMs | Faces missed |
|---|---|---|---|---|---|
| 1 | baseline (minFaceSize=0.1) | 803 | **19.05** | 87.71ms | 0/803 |
| 2 | minFaceSize=0.35 | 1004 | **23.84** | 18.80ms | 1/1004 |
| 3 | baseline re-check | 777 | **18.50** | 89.88ms | 0/777 |
| 4 | useKalmanTracking=true (minFaceSize=0.1) | 777 | **18.45** | 91.71ms | 0/777 |
| 5 | minFaceSize=0.35 + useKalmanTracking=true | 999 | **23.70** | 25.31ms | 1/1000 |
| 6 | minFaceSize=0.35, increased camera distance | 744 | **23.21** | 24.06ms | 0/744 |

Kalman `predict()` cost: 0.027ms mean / 0.39ms max (Capture 4), 0.036ms mean / 2.93ms max
(Capture 5) — negligible either way, even cheaper than `OpticalFlowFaceTracker`'s SAD
matching (Segment 18: 0.43-0.87ms mean).

### Verdict: both promoted to the production default

**`minFaceSize=0.35` is a real, mechanism-level win, not noise.** Captures 1 and 3 (baseline,
bracketing Capture 2) agree closely (19.05fps/87.71ms vs. 18.50fps/89.88ms) — nothing like
the 14% baseline swing Segment 28 found. Against that stable baseline, Capture 2's 18.80ms
mean detect cost is a ~4.7x reduction, not a few-percent fluctuation, and it holds up in
Capture 5 (combined) and Capture 6 (increased distance) too. Miss rate stayed at 0-1 frames
per ~750-1000 (i.e. ≤0.13%) across every capture that used it, including the deliberate
increased-distance check (Capture 6: 0/744) — the failure mode Google's own docs warn
about (missing smaller/more distant faces) was watched for specifically and not observed
at the distances tested.

**`useKalmanTracking=true` costs nothing measurable and composes cleanly** with the
`minFaceSize` change (Capture 5's fps, 23.70, matches Capture 2's 23.84 closely — no
interaction penalty). Its own fps effect is correctly near-zero on its own (Capture 4 vs.
baseline: 18.45 vs. 18.50-19.05, well within noise) since it does not touch the dominant
cost (`detectMs`) at all — its value is in box-extrapolation quality between detections,
not throughput.

**Honest caveat, not smoothed over**: `useKalmanTracking`'s promotion rests on "measurably
free, plausible upside (never reads pixel content, so avoids the KLT drift failure mode;
extrapolates rather than assumes-stationary), no measured downside" — NOT on a validated
reduction in ROI positional error, since no ground-truth face-position data was available
this session to check `KalmanBoxTracker`'s predicted boxes against reality (only synthetic
motion in the unit tests). Likewise, the distance range tested for `minFaceSize=0.35` was
one normal framing plus one deliberately-further-back framing, not an exhaustive sweep
across lighting conditions, face angles, or multiple users. A future session with more
time/ground-truth data could tighten both of these; this segment's promotion decision is
based on what was actually measured, stated plainly rather than either overclaimed or
withheld pending unavailable perfect evidence.

**`useMotionTracking` and `useCroppedDetection` stay `false`, `DETECT_EVERY_N_FRAMES` stays
3** — Segment 28's own verdicts on those are unchanged by this segment's work.

## Files touched

- `android/app/src/main/java/com/spandan/app/camera/KalmanBoxTracker.kt` (new)
- `android/app/src/test/java/com/spandan/app/camera/KalmanBoxTrackerTest.kt` (new)
- `android/app/src/main/java/com/spandan/app/camera/FaceAnalyzer.kt` (`minFaceSize`,
  `useKalmanTracking` — both now default-on)
- `android/app/src/main/java/com/spandan/app/camera/ProfilingFaceAnalyzer.kt` (mirrors the
  above for future profiling sessions)
