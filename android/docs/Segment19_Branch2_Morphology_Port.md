# Segment 19 — Branch 2 (Waveform Morphology / Dicrotic Notch) Ported to Android

Run 2026-09-15/16. Real on-device verification, Samsung Galaxy A35 (`SM-A356E`,
`RFCXC0FFFSN`), same device as Segment 18 (attached partway through this session).

## Context

`matlab/src/roi/extractROISignals.m` feeds two deliberately separate branches: Branch 1
(production HR/SpO2, narrow 0.7-4Hz band, already on Android) and Branch 2 (waveform
morphology/dicrotic-notch analysis, wide 0.5-8Hz band + harmonic-comb filtering). These
are NOT merged on purpose — the wide-band/comb filtering Branch 2 needs measurably breaks
Branch 1's HR accuracy (a documented harmonic-lock case, one VIPL subject's CHROM jumped
69.4→140.8bpm under it). Branch 2 has never been ported to Android before this segment —
confirmed multiple times in this project's history as a deliberate prior scope decision
(most recently re-confirmed, still correctly, in Segment 14's own Android-scope check) —
so this was genuinely new territory on the Kotlin side.

Per this project's own stated discipline, every MATLAB source file below was read
directly before writing any Kotlin — not from memory or from this task's own brief's
description of them:

- `matlab/src/pipeline/estimateVitalsAndMorphology.m` (the orchestrator)
- `matlab/src/morphology/bandpassMorphology.m` ('wide'/'mid' modes)
- `matlab/src/morphology/adaptiveHarmonicFilter.m` (ABPF)
- `matlab/src/morphology/notchDetectIEM.m` (IEM notch detector)
- `matlab/src/morphology/harmonicSelectiveGaussianFilter.m`
- `matlab/src/morphology/harmonicFilterConfidenceGate.m`
- `matlab/src/morphology/extractMorphologyWaveform.m`
- `matlab/src/morphology/ensembleAverageBeats.m`
- `matlab/src/morphology/fixPolarity.m`
- `matlab/src/morphology/resampleUniform.m`

`fixPolarityByGroundTruth.m` and `estimateLagPolarityByGroundTruth.m` were explicitly
**not** ported, per the task's own instruction — they are ground-truth-anchored and
Android never has a contact-PPG reference to anchor against, live or otherwise.

## What was ported

All new files live flat under `signal/`, parallel to (never merged into) Branch 1's
`RealHeartRateEstimator.kt`/`BandpassFilter.kt`, matching this project's existing package
convention.

- **`PchipInterpolator.kt`** — a shared Fritsch-Carlson PCHIP interpolator. **Structural
  deviation from the MATLAB source, stated explicitly**: MATLAB has no single file for
  this — it's inlined via three separate `interp1(...,'pchip')` call sites across
  `resampleUniform.m`, `ensembleAverageBeats.m`, and `notchDetectIEM.m`. Consolidating it
  into one shared Kotlin utility is a deliberate port-time structural choice (avoiding
  three copies of the same algorithm), not a missed file or a misunderstanding of the
  source layout. Unit-tested: exact knot reproduction, exact straight-line reproduction,
  a no-overshoot check on a monotone step-like signal (PCHIP's whole reason for existing
  over a cubic spline), out-of-range clamping, and a sine-wave interpolation accuracy
  check.
- **`MorphologyBandpassFilter.kt`** — wide (0.5-8Hz)/mid (0.6-6.0Hz), order 3. Reuses
  [`BandpassFilter.designButterworthBandpass`/`filtfilt`](../app/src/main/java/com/spandan/app/signal/BandpassFilter.kt)
  directly (both already `public fun`) rather than duplicating Butterworth-design code —
  `BandpassFilter.kt` itself (on this project's "do not touch" list) was never modified,
  only called with different arguments. Adds `isAdmissible(fs, mode)`/`pick(fs)`, which
  MATLAB's own batch scripts never needed (their clips are always well above 16fps) but a
  live camera at 13-22fps genuinely does — see Segment 18's own note on this real
  interaction. Unit-tested against the Nyquist admissibility boundary and a synthetic
  4.5Hz tone that Branch 1's narrow filter would reject but the wide band should retain.
- **`AdaptiveHarmonicFilter.kt`** — the ABPF harmonic comb (Moço/Stuijk/de Haan, *Sci Rep*
  8:8501, 2018), via JTransforms' `DoubleFFT_1D` complex forward/inverse (already a
  dependency, used by `HeartRateFft.kt`). The FFT-bin masking logic was hand-translated
  from MATLAB's 1-based indexing to Kotlin's 0-based arrays; verified with a synthetic
  multi-harmonic-plus-interference signal (the comb should recover a clean cardiac shape
  from a signal contaminated by a strong non-harmonic tone) and a Nyquist-boundary check.
- **`HarmonicSelectiveGaussianFilter.kt`** — the Gaussian-tapered alternative
  (Dominguez-Hernandez, Paez & Padilla, *Sensors* 26(12):3710, 2026). Verified it rejects
  far interference the same way the hard comb does, and that a wider `alpha` passes more
  of a near-harmonic tone than a narrower one (the mechanism the parameter is supposed to
  control).
- **`HarmonicFilterConfidenceGate.kt`** — the safe single-fallback selection logic ONLY.
  **Deliberately NOT ported**: the MATLAB source's own discouraged multi-candidate "pick
  the highest self-reported confidence" mode (its own header calls this "VERIFIED AND
  ACTIVELY DISCOURAGED" — it produced the worst median waveform correlation of every
  method MATLAB compared, a selection-bias artifact). Flagged directly in this file's own
  KDoc so a future session doesn't reach for it blind by passing more than one fallback
  candidate.
- **`FixPolarity.kt`** — the skewness heuristic, the ONLY polarity method Android can ever
  use live. Carries over the MATLAB source's own stated caveat verbatim: measured on
  UBFC-D1, this heuristic agreed with the ground-truth-anchored rule on only 3/5 subjects,
  with a systematic all-flip bias (a plausible forehead-vs-fingertip PPG asymmetry
  reversal, per den Brinker et al., arXiv:2306.09879) — a real, known limitation of the
  only option Android has, not fixed by this port.
- **`ResampleUniform.kt`** — uniform-grid PCHIP resample from real per-sample timestamps
  (`RgbSample.timestampMs`, converted to seconds), same role as `roiTimestamps` on the
  MATLAB side.
- **`EnsembleAverageBeats.kt`** — the most involved port: negative-going zero-crossing
  beat segmentation, duration gating, per-beat PCHIP resample, two-anchor time warp
  (aligning each beat's systolic peak to a common cycle fraction), a correlation-based
  quality gate, and trimmed-mean/median/IQR combination. Throws on too-few-beats, matching
  the MATLAB source's own hard `error(...)` calls exactly (a faithful, unsoftened port —
  see the fail-soft note below for who catches this live). Unit-tested against a synthetic
  beat train: recovers the right beat count, and the two-anchor warp's *guaranteed*
  properties (peak lands near the 0.25 anchor fraction, real rise/decay shape) — not a
  naive fraction-for-fraction shape match, since beat segmentation starts on a zero
  crossing partway through the cycle, not at any fixed reference point (see the test file's
  own comment for the full reasoning on why a literal correlation check would have been
  testing the wrong thing).
- **`NotchDetectIEM.kt`** — the Iterative Envelope Mean (IEM) notch detector (Pal, Rudas,
  Kim, Chiang, Barney & Cannesson, *Comput Biol Med* 254:108283, 2024). **Boundary-handling
  deviation from MATLAB, stated explicitly** (same discipline `WaveletDenoise.kt`'s own
  header already uses for its own boundary difference): the Savitzky-Golay smoothing step
  here refits a fresh local least-squares polynomial window at every sample instead of
  matching `sgolayfilt`'s exact edge convention — cheap and harmless since this only ever
  runs on a small (typically 256-sample) prototype, and exact bit-for-bit match to MATLAB
  was never required, only a real Savitzky-Golay smooth. Verified against a synthetic
  prototype with an actual carved-in notch-shaped dip (detects it, reports a sensible
  position/depth/confidence) and a constant-signal guard (throws, matching MATLAB).
  Carries over the source's own confidence-clip caveat: `confidence` clips at 1.0 (a
  resolution-floor artifact, not a real tie across subjects) — `confidenceRaw` (unclipped)
  is what actually carries ranking information, and per this task's own instruction, it's
  the one surfaced in the UI, not a bare pass/fail.
- **`MorphologyWaveformEstimator.kt`** — the live orchestrator, mirroring
  `estimateVitalsAndMorphology.m`'s Branch 2 sequence exactly: detrend → shared f0 from a
  wide/mid-band CHROM pulse → ABPF comb (all three channels forced onto that one shared
  f0) → `chromCombine` → `FixPolarity` → `ResampleUniform` → `EnsembleAverageBeats` →
  `NotchDetectIEM`, with `useConfidenceGate` (default `true`, matching the MATLAB
  production default since Segment 14) substituting the Gaussian(0.15) candidate wherever
  ABPF's own confidence fails the 0.3 bar. Reuses the **existing** `EstimatorStatus` enum
  (`OK`/`WARMING_UP`/`LOW_SIGNAL_QUALITY`) — per this task's own instruction to extend the
  established convention rather than invent a new one. **Fail-soft layer, a deliberate,
  stated divergence from a pure port**: `EnsembleAverageBeats`/`FixPolarity` can throw on a
  bad window (too few beats, too-short signal) exactly as their MATLAB sources do — this
  live orchestrator, running on uncontrolled camera data (unlike MATLAB's own offline batch
  scripts, which only ever see clean pre-vetted clips), catches those and reports
  `LOW_SIGNAL_QUALITY` instead of crashing. This is the same "ported function stays
  MATLAB-faithful, the live caller adds the fail-soft layer" split `RealHeartRateEstimator`
  already uses around `BandpassFilter`/`HeartRateFft`.

## UI

New `ui/WaveformView.kt` (Canvas-drawn, no external chart library, same "no dependency for
one line plot" choice as the existing `SignalChartView.kt`) draws one ensemble-averaged
cardiac cycle with a marker at the detected notch position. A new "WAVEFORM MORPHOLOGY
(BRANCH 2)" card in `activity_main.xml` matches the existing vitals-card visual language
exactly (same `bg_vitals_card`/`bg_status_pill` drawables, same caption style). The status
pill surfaces the **raw (unclipped) confidence number** and which filter was actually used
("ABPF comb" / "Gaussian (α=0.15)") — per this task's own explicit instruction not to
reduce this to a yes/no, since `notchDetectIEM.m`'s own boolean output is documented
elsewhere in this project as a near-useless gate at pool scale (100/100 "detected" in
Segment 10 Task 1's audit). The dot color reflects `EstimatorStatus` for the
no-value/no-face cases, plus (when a value IS available) a second check against the 0.3
confidence bar — `OK` alone only means "a value was computed this tick," not "a confident
one," so the color needed a second signal beyond the shared enum to be honest.

## Unit tests

10 new test files (`PchipInterpolatorTest`, `MorphologyBandpassFilterTest`,
`AdaptiveHarmonicFilterTest`, `HarmonicSelectiveGaussianFilterTest`,
`HarmonicFilterConfidenceGateTest`, `FixPolarityTest`, `ResampleUniformTest`,
`EnsembleAverageBeatsTest`, `NotchDetectIEMTest`, `MorphologyWaveformEstimatorTest`), all
against synthetic signals with known properties — same "verify before trusting real data"
discipline as `BandpassFilterTest`/`WaveletDenoiseTest`. `MorphologyWaveformEstimatorTest`
specifically exercises the whole orchestrator end to end (wiring between stages, not just
per-stage correctness) across a realistic fps sweep (9, 11, 13.44, 16, 18, 21.4, 25, 30Hz —
covering this project's own documented on-device range) and asserts it never throws.

**A real, needed fix along the way**: `android.util.Log.d`/`.w` calls (used by
`MorphologyWaveformEstimator`, and — never previously exercised by a plain-JUnit test —
also already present in `RealHeartRateEstimator`/`LiveSpo2Estimator`) throw `"Method ...
not mocked"` under plain JUnit. Added the standard, safe
`testOptions.unitTests.isReturnDefaultValues = true` to `app/build.gradle.kts` rather than
wrapping every estimator's logging behind a new testable indirection layer for no other
purpose — a standard Android Gradle config, zero production behavior change.

**Full suite: 49/49 tests pass** (10 new signal files + 2 new camera files from Segment
18 + every pre-existing test, re-run clean).

## Real on-device verification

Built, installed, launched, and captured `adb logcat` for `RealHeartRateEstimator`,
`LiveSpo2Estimator`, and `MorphologyWaveformEstimator` while a face was continuously in
frame.

**Zero crashes, zero exceptions.** App pid stable throughout every capture this session
(confirmed via `adb shell pidof` before and after).

**9 successful Branch 2 recomputes** captured over a ~40s window (the 2000ms recompute
interval matches this almost exactly — one every ~2-4.4s in practice, no backlog observed):

```
fs=14.33Hz band=MID    method=adaptiveHarmonic substituted=false notchDetected=true notchConf=0.818
fs=21.46Hz band=WIDE   method=gaussian015     substituted=true  notchDetected=true notchConf=0.267
fs=21.73Hz band=WIDE   method=gaussian015     substituted=true  notchDetected=true notchConf=0.019
fs=21.76Hz band=WIDE   method=adaptiveHarmonic substituted=false notchDetected=true notchConf=0.869
fs=22.08Hz band=WIDE   method=gaussian015     substituted=true  notchDetected=true notchConf=0.152
fs=22.01Hz band=WIDE   method=gaussian015     substituted=true  notchDetected=false notchConf=0.000
fs=21.83Hz band=WIDE   method=gaussian015     substituted=true  notchDetected=true notchConf=0.197
fs=21.94Hz band=WIDE   method=gaussian015     substituted=true  notchDetected=true notchConf=0.046
fs=21.66Hz band=WIDE   method=gaussian015     substituted=true  notchDetected=true notchConf=0.176
```

This is real, direct confirmation of the two design decisions this task's brief called
out specifically:

1. **The WIDE/MID band fallback fired for real.** At fs=14.33Hz (Nyquist=7.17Hz), WIDE's
   8Hz cutoff is correctly inadmissible and MID (6Hz cutoff) was used instead — exactly
   `MorphologyBandpassFilter.pick()`'s designed behavior, not a hypothetical. At
   fs≥21.4Hz (Nyquist≥10.7Hz), WIDE fired as expected. **Real fs this ran at, stated
   explicitly per this task's own instruction: 14.16-22.08Hz** (varying live, not a fixed
   assumed value).
2. **The confidence gate substituted for real, in both directions.** 6/9 windows
   substituted to Gaussian(0.15) (ABPF's own confidence failed the 0.3 bar); 3/9 stayed on
   ABPF (it passed). Notch confidence spread 0.019-0.869 — wide variance matching this
   project's own MATLAB-side documented pool-scale finding (Segment 10 Task 1: median r
   0.44-0.52, highly variable), not a sign of a bug.

**Branch 1 confirmed unaffected on the exact same capture** (not assumed): `HR_chrom`/
`HR_pos` continued logging every ~1s with the same jitter pattern already documented
elsewhere in this project (observed range 51-136bpm this capture, CHROM/POS switching
firing normally), and SpO2 stayed in its documented reference range (~96.8-97.1%
observed). Neither estimator's log output or behavior changed from before this segment.

**A screenshot was taken and visually confirmed the new card** (waveform line, notch
marker, status pill rendering correctly, matching the existing vitals-card style) — **not
retained**, per this project's own established practice of not keeping screenshots that
contain a real face (see Segment 16's own precedent); it was never committed. One
genuinely useful thing that screenshot caught: at that specific instant, the morphology
status pill read **"Low signal quality"** (a real `LOW_SIGNAL_QUALITY` tick) while the
HR/SpO2 pills simultaneously read "Live"/OK — direct visual confirmation that Branch 1 and
Branch 2 report their health completely independently, not just by code inspection.

## Ambiguities and deviations flagged, not silently resolved

1. **NotchDetectIEM's Savitzky-Golay boundary handling** — see above.
2. **The confidence gate's fallback candidate itself failing** — no MATLAB precedent
   exists for this (its offline batch scripts assume clean data end to end). Android's
   own resolution, stated as a real design decision rather than an oversight: if the
   Gaussian candidate throws (too few beats in a live, noisy window), the gate never runs
   and the primary (ABPF) result — which already succeeded — is kept. There was nothing
   better to fall back to.
3. **`trimmean`'s exact rounding convention.** `EnsembleAverageBeats.kt`'s trimmed-mean
   trim count (`round(n * percent/100 / 2)`) is a standard interpretation of MATLAB's
   `trimmean(X, percent, 1)` but has not been verified bit-exact against MATLAB's own
   tie-breaking rule for non-integer trim counts.
4. **Recompute cadence.** `RECOMPUTE_INTERVAL_MS = 2000` and `MIN_WINDOW_SECONDS = 10.0`
   are this port's own choice (heavier per-window cost than Branch 1: harmonic-comb
   FFT/IFFT ×3 channels, a conditional second pass, Savitzky-Golay smoothing inside the
   notch detector). The one real capture taken this session kept up without a backlog, but
   this was not tuned against a full on-device CPU/battery budget beyond that one
   observation.

## Files touched

New: `signal/PchipInterpolator.kt`, `signal/MorphologyBandpassFilter.kt`,
`signal/AdaptiveHarmonicFilter.kt`, `signal/HarmonicSelectiveGaussianFilter.kt`,
`signal/HarmonicFilterConfidenceGate.kt`, `signal/FixPolarity.kt`,
`signal/ResampleUniform.kt`, `signal/EnsembleAverageBeats.kt`, `signal/NotchDetectIEM.kt`,
`signal/MorphologyWaveformEstimator.kt`, `ui/WaveformView.kt`, and 10 test files under
`app/src/test/java/com/spandan/app/signal/`.

Modified (additive only — no existing behavior changed): `MainActivity.kt` (new estimator
instance + card wiring), `res/layout/activity_main.xml` (new card), `res/values/strings.xml`
(new strings), `app/build.gradle.kts` (`testOptions.unitTests.isReturnDefaultValues =
true`).
