# SpO2 Live Implementation

Status as of **2026-08-12**. This is the "how SpO2 actually works on-device
now" reference -- `Defense_Readiness_Checklist.md` is the broader
defense-readiness summary, `../README.md` is the full build history.

## Standing decision (Task R)

With real phone-camera (source2) data, Task R
(`matlab/docs/Segment6_Task_R_Phone_SpO2_Centering.md`) found phone-specific
R centering is statistically a wash against the uncentered production
formula once known fault-code subjects are excluded (MAE 1.2609 centered
vs. 1.2590 uncentered). **Decision: use the uncentered production formula
directly** -- simpler, no accuracy cost. This also supersedes an earlier
plan to add a startup "Calibrating..." session-relative-baseline period --
**not implemented**, not needed.

## Exact formula used

Two stages, both read directly from MATLAB source before porting (not from
memory/description) -- see `signal/LiveSpo2Estimator.kt`'s KDoc for the
full citation trail.

### Stage 1 -- ratio-of-ratios R (`matlab/src/spo2/ratioOfRatios.m`)

```
DC_R = mean(R_raw)
DC_B = mean(B_raw)
AC_R = std(R_filtered)      # sample std, N-1 denominator, matching MATLAB's std()
AC_B = std(B_filtered)
R = (AC_R / DC_R) / (AC_B / DC_B)
```

`R_raw`/`B_raw` are the live buffer's raw per-frame RGB averages; `R_filtered`/
`B_filtered` are those same traces after `BandpassFilter.detrend()` +
`BandpassFilter.apply()` -- the exact same, already-validated detrend/
bandpass chain `RealHeartRateEstimator` uses, reused (not reimplemented) via
the shared `BandpassFilter`/`PulseExtraction.sampleStdDev` utilities. G is
accepted by `ratioOfRatios.m`'s own signature but never used in its formula;
`LiveSpo2Estimator.kt` simply doesn't take a G parameter, rather than port an
unused argument.

### Stage 2 -- linear calibration (`matlab/docs/SpO2_Final_Calibration_Spec.md`)

```
A = 96.47630625
B = -0.4159452784
SpO2 = A - B * R        # no centering step -- applied directly to live, uncentered R
```

**Sign-convention correction, flagged plainly rather than applied silently:**
the task brief's shorthand was `SpO2_estimate = 96.4763 + (-0.41595) * R_live`
(i.e. `A + B*R`). The calibration's own defining function,
`matlab/src/spo2/calibrateSpO2.m` line 51, is `spo2Est = A - B * R` (its own
KDoc: `"SpO2 = A - B*R"`). Since `B` is already negative
(`-0.4159452784`), `A - B*R` and `A + B*R` are **not** the same value --
they differ by `2*B*R`, sign-flipped. `LiveSpo2Estimator.kt` implements
`A - B*R`, matching `calibrateSpO2.m` exactly (source-of-truth, not the
chat paraphrase) -- concretely, `CALIBRATION_A - CALIBRATION_B * ratioOfRatios`
in the code, which expands to `96.4763 + 0.41595*R` (SpO2 rises with R,
per the fitted coefficients on this project's pool). Flagging this the same
way the `RoiCalculator.kt` fraction mismatch was flagged earlier in this
project: verify against source, fix real discrepancies, report plainly
rather than silently pick one.

### No centering step

Per the standing decision above -- `SpO2 = A - B*R` is applied directly to
the live R computed each window, with no per-device or per-session offset
subtracted. `matlab/docs/Segment6_Task_R_Phone_SpO2_Centering.md` is the
evidence that a phone-specific centering offset was checked and found
unnecessary for this device, not an oversight.

### Clamp (Action 2)

```kotlin
val clampedSpo2 = rawSpo2.coerceIn(90.0, 100.0)
```

Stated explicitly in code (`LiveSpo2Estimator.kt`), same transparency
standard as `RealHeartRateEstimator`'s own guards. 90-100% is deliberately
a little wider than this project's own validated ground-truth range
(87.28-99%, fault-codes excluded, per `SpO2_Final_Report_Section.md`) --
room for real signal noise on live camera data, without silently accepting
values in the range of this project's own already-identified VIPL
sensor-fault codes (44%, 103.79%).

## UI (Action 3)

`activity_main.xml`'s HR/SpO2 block is restored to a two-column layout,
matching HR's visual style (value + subtitle, same sizes/margins):

- **HR** (left): value + green `"● LIVE — CHROM/POS + FFT"` chip.
- **SpO2** (right): value + amber `"Estimate — validated against a narrow
  reference range (87-99%)"` subtitle -- deliberately not green (this is a
  narrower-validated estimate than HR) and deliberately not red (this
  isn't a fake/placeholder value, so the old "PLACEHOLDER" language would
  now be inaccurate).

No "Calibrating..." state: `spo2_placeholder_default` (`"SpO2: -- %"`) shows
only until the first valid computation, same timing as HR's own
`hr_placeholder_default`, per the standing decision to drop the
session-baseline plan entirely.

## Action 4 -- regression check: HR side unaffected

- `git diff --stat` on `signal/RealHeartRateEstimator.kt` and
  `camera/RoiCalculator.kt`: **empty** -- neither file was touched.
- `MainActivity.onResume()` (the prior session's permission-recheck fix) is
  unchanged and still present.
- `LiveSpo2Estimator` is instantiated and called independently in
  `MainActivity.refreshUi()`, reading the same `signalBuffer.snapshot()` HR
  already reads, but not calling into or reading `RealHeartRateEstimator`'s
  state (or vice versa) -- confirmed by inspection of both classes' source,
  not just by the compiler not complaining.
- `./gradlew assembleDebug` + `testDebugUnitTest --tests
  "...BandpassFilterTest"`: **BUILD SUCCESSFUL**, unit test passed, same
  single harmless `@OptIn` warning as every prior build in this project. No
  new warnings introduced by this change.
- On-device (see Action 5 below): `RealHeartRateEstimator` logged **209**
  lines over the SpO2 verification run, `LiveSpo2Estimator` logged
  **209** -- identical cadence (both recompute at most once per second off
  the same buffer), confirming the two ran in parallel for the whole run
  with neither one blocking or interfering with the other.

## Action 5 -- real on-device test

**VERIFIED on the same physical Samsung Galaxy A35 (SM-A356E)** used for
every prior on-device verification in this project. `adb devices` confirmed
attached (`RFCXC0FFFSN`); `./gradlew assembleDebug`, `adb install -r`,
launched via `adb shell am start`. Ran **4.5 minutes (273s)** with a face in
frame, parallel `adb logcat -v time` capture for the whole session.

### Zero crashes, zero exceptions

- `pidof com.spandan.app` = `25950` at launch, confirmed unchanged at every
  45s check (6 checks) and at the final check before stopping the app --
  **no restart**.
- `grep -E "FATAL EXCEPTION|AndroidRuntime|ANR |tombstone"` across the full
  37,237-line capture: **0 matches**.
- `grep -i spandan | grep -i exception`: **1 match**, and it is not an app
  exception -- `W/WindowManager( 1511): Exception thrown during
  dispatchAppVisibility Window{... com.spandan.app/... EXITING}`, logged by
  the system `WindowManager` process (PID 1511, not the app's own PID) at
  the moment `adb shell am force-stop` tore the app down at the end of the
  test. Zero exceptions during the actual 4.5-minute run itself.
- Zero `"Degenerate DC/AC value"` warnings (the divide-by-zero guard in
  `LiveSpo2Estimator.update()`) -- never triggered on real data.

### SpO2 displayed, stayed in range, responded plausibly to real R changes

**209 SpO2 recomputes** over the run:

| | Value |
|---|---|
| Readings | 209 |
| SpO2 range | 96.72% - 96.94% |
| Unique values | 20 (not flat-lined) |
| R range (live, uncentered) | 0.5843 - 1.1078 |
| Clamp (90-100%) triggered | 0 times -- every raw value landed naturally in-range |

**SpO2 tracked R directly, moving together sample to sample** -- spot-check
across the run:

```
19:19:13.713  R=0.7205  rawSpo2=96.78%  clampedSpo2=96.78%  fs=9.38Hz  n=61
19:19:54.420  R=0.8515  rawSpo2=96.83%  clampedSpo2=96.83%  fs=13.33Hz n=334
19:20:34.888  R=1.0490  rawSpo2=96.91%  clampedSpo2=96.91%  fs=13.30Hz n=333
19:21:15.289  R=0.8175  rawSpo2=96.82%  clampedSpo2=96.82%  fs=13.14Hz n=329
19:21:55.668  R=0.7084  rawSpo2=96.77%  clampedSpo2=96.77%  fs=13.38Hz n=335
19:22:36.043  R=0.8139  rawSpo2=96.81%  clampedSpo2=96.81%  fs=13.27Hz n=332
19:22:44.114  R=0.8488  rawSpo2=96.83%  clampedSpo2=96.83%  fs=13.32Hz n=333
```

Higher R consistently produces higher SpO2 (e.g. the run's R peak, 1.0490,
lines up with its SpO2 peak, 96.91% -- the run's highest values in this
excerpt) -- exactly the `A - B*R` (positive R-coefficient after expanding
the negative `B`) relationship the corrected formula implements.

**On the narrow 96.72-96.94% observed band, reported honestly rather than
just as a clean pass:** this ~0.22-percentage-point span across the whole
run is real and expected given this specific calibration's own already-
documented characteristics, not a bug. With `B = -0.4159452784` and the
observed R range spanning 0.52 (0.5843 to 1.1078), the formula's own slope
predicts almost exactly this span (`0.416 * 0.52 ≈ 0.22`) -- consistent
with `SpO2_Final_Report_Section.md`'s and `SpO2_Final_Calibration_Spec.md`'s
own repeated finding that this project's SpO2 calibration is a very flat,
narrow-variance fit (it loses to a trivial "guess the training mean"
baseline in the validated LOSO numbers). The live implementation is a
faithful port of that same flat relationship, not an implementation bug
suppressing variation that should be there.

**Screenshot confirmation** (taken mid-run): HR and SpO2 both visible
side by side, `HR: 65 bpm` / green `"● LIVE — CHROM/POS + FFT"` chip on the
left, `SpO2: 96.8%` / amber `"Estimate — validated against a narrow
reference range (87-99%)"` subtitle on the right, face/ROI overlay boxes
correctly positioned. Matches the Action 3 spec visually, not just in code.

### Honest bottom line

Zero crashes, zero app-side exceptions, SpO2 displayed from the first valid
computation (no "Calibrating..." state, as decided), values held inside the
90-100% clamp without the clamp ever needing to fire, and the estimator
visibly tracked real R changes rather than being flat/frozen. HR-side
regression check is clean: neither `RealHeartRateEstimator.kt` nor
`RoiCalculator.kt` was touched, and both estimators ran in parallel for the
full run at identical cadence with no interference.
