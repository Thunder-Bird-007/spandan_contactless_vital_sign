# Segment 16 Task 1 — HR/PPG Signal Stability

Status as of **2026-09-14**. Builds on `android/README.md`'s own root-cause
chain (sparse real-device sampling → coarse FFT bin resolution → on-screen
jitter) and `matlab/docs/Segment6_Task5_RAKF_Kalman_Smoothing.md` (Kalman
smoothing already tested and rejected on the MATLAB side). **Update, same
day**: a physical device (the same Samsung Galaxy A35 used throughout this
project) became available partway through this task. §4 below now reports
a real on-device A/B capture, including a real bug the capture itself
surfaced and that was fixed before the result was trustworthy — read that
section before quoting the headline number.

---

## 1. Why RAKF/Kalman filtering is not revisited here

Read in full before considering it again. `matlab/docs/
Segment6_Task5_RAKF_Kalman_Smoothing.md`'s own verdict: on the 107-subject
VIPL pool, RAKF's MAE (12.15) and RMSE (22.04) were the **worst of six
methods compared**, worse than doing nothing (whole-clip baseline MAE
9.35), and worse than every simpler alternative tested (naive windowing,
gating-only). The doc's own honest caveat is that RAKF's `R0`/`beta`/`Q`
were data-derived defaults, not values taken from the source paper, so a
different tuning *might* do better — but the evidence in hand says
residual/quality-adaptive Kalman smoothing, as actually implemented and
tested, is a net loss on this project's own data.

**This task does not re-implement or re-propose Kalman filtering.** What it
builds instead (`signal/DisplaySmoother.kt`) is deliberately a different
mechanism, not a re-tuned RAKF:

| | RAKF (MATLAB, rejected) | DisplaySmoother (this task) |
|---|---|---|
| Operates on | The signal/estimate itself, feeding a state-space model | Only the already-final, already-switched displayed bpm number |
| Feeds back into the pipeline? | Yes — its output *is* the HR estimate | No — never read by `RealHeartRateEstimator`/`LiveSpo2Estimator`, only by `MainActivity`'s own display code |
| Failure mode if wrong | Corrupts the actual measurement | Displays a slightly stale/lagged number for a few seconds; the underlying pipeline is completely unaffected and unaware it exists |
| Claim | "This is a better estimate of the true HR" | "This is a smoother number to look at" — explicitly not an accuracy claim |

This is exactly the distinction `android/README.md`'s own "Diagnostic" follow-up
section already drew when it first flagged this idea and declined to build
it without an explicit decision: *"Temporal smoothing... could reduce the
on-screen jitter for display purposes, but MATLAB's validated pipeline
doesn't do this... adding it here would be a real deviation from 'faithful
port,' not just a bug fix, so it wasn't added without an explicit decision
from the team."* This task is that explicit decision, made deliberately
narrow (display-layer only) precisely because the pipeline-level version of
this idea (RAKF) already failed on real data.

## 2. What was built

`signal/DisplaySmoother.kt` — takes the already-computed, already-CHROM/POS-
switched bpm value each UI tick and applies either:

- **Rolling median** (default), window of 5 ticks — robust to a single wild
  outlier reading (the exact failure mode the README's manual-pulse
  comparisons repeatedly documented: individual readings 20-50+ bpm off
  while neighbors are fine).
- **EMA** (alpha=0.3) — reacts faster to a sustained step change, at the
  cost of not fully rejecting a single outlier the way the median does.
- **NONE** — passthrough, for a clean on/off toggle without removing the
  class from the call site.

Wired into `MainActivity` behind `ENABLE_HR_DISPLAY_SMOOTHING_DEFAULT` —
**promoted to `true` this session, after §4's real on-device A/B result**
(started `false`, per this project's own standing discipline of not
promoting an unevaluated change, same pattern as `cpaceProjection.m`/
`harmonicSelectiveGaussianFilter.m` on the MATLAB side; flipped only once
real evidence existed, not blindly). When off, `hrBpm` in
`MainActivity.refreshUi()` is exactly `heartRateEstimator.update(samples)`'s
own return value — byte-for-byte the existing pipeline output, unchanged;
turning smoothing on never alters what `RealHeartRateEstimator` itself
computes or logs.

**Unit-tested (no device needed)**: `DisplaySmootherTest.kt`, 8 tests (grew
from 6 to 8 during this task — see §4's real bug), covering NONE
passthrough, outlier rejection, step-change tracking, EMA behavior, the
null/warm-up-gap edge case, and the repeated-identical-input de-duplication
added after the on-device capture surfaced it. `./gradlew testDebugUnitTest
--tests "com.spandan.app.signal.DisplaySmootherTest"`: **PASSED**, all 8
tests, alongside `BandpassFilterTest` (also re-run, unaffected: `in-band
gain=0.9804`, `out-of-band gain=0.0131`, identical to every prior run).

### A real bug found and fixed via the unit test, before any device was involved

The first implementation's null-handling (`smooth(null)`, called when the
pipeline itself has no value yet) returned `history.lastOrNull()` for
`ROLLING_MEDIAN` mode — the last *raw input*, not the last *median output*.
For history `{70, 72}` (median 71), a `null` tick incorrectly returned `72`
instead of `71`. The `null input (warm-up gap) is a no-op` test caught this
immediately (`AssertionError`, expected `71.0`). Fixed by tracking
`lastOutput` explicitly rather than deriving it from the raw history deque.
This is exactly why `DisplaySmootherTest.kt` was written before any
device-facing work — the same "unit test before trusting it on real data"
discipline `BandpassFilterTest` already established for this app.

## 3. The fs/window-length question — DSP analysis (no device data needed for this part)

The brief also asked whether the frame-skip optimization's higher analyze()
throughput (13.44→21.40fps, `FaceAnalyzer.kt`'s `DETECT_EVERY_N_FRAMES=3`)
changes the window-length tradeoff, since `SignalBuffer.WINDOW_DURATION_
SECONDS=25.0` was tuned against the OLDER ~13.4Hz measurement, before the
frame-skip optimization existed.

**Since `RoiPixelAverager.averageRgb` runs on every `analyze()` call
regardless of whether that call's ML Kit detection was skipped** (skipped
frames reuse the last face box but still sample fresh pixels from it — see
`FaceAnalyzer.emitFaceDetected`), the higher analyze() throughput directly
means a higher real RGB sample rate feeding `SignalBuffer`, not just faster
face detection. This part is a plumbing fact, confirmed by reading
`FaceAnalyzer.kt`, not requiring a device to establish.

**However, the DSP theory here needs to be stated precisely, because the
naive intuition is wrong**: for a fixed-duration window of length `T`
seconds, the FFT's frequency-bin spacing is `Δf = fs/N = fs/(fs·T) = 1/T` —
**a function of window duration alone, independent of the sampling rate
`fs`**, as long as sampling stays uniform. Raising `fs` while holding
`WINDOW_DURATION_SECONDS` fixed does **not** sharpen the bpm resolution
readers might assume it does; the number of FFT bins landing inside the
fixed 0.7-4.0Hz search band (`(4.0-0.7)/Δf = 3.3·T`) is likewise a function
of `T` alone. This directly informs (and slightly corrects) the framing of
the original question: **a higher-fs window at the SAME duration does not,
by itself, produce a finer bpm resolution than the 25s window already has.**

What a higher `fs` at a fixed duration DOES plausibly help with, and why
these are genuinely different benefits from "resolution":

1. **More independent samples per unit time** → more averaging within the
   detrend/bandpass/CHROM-POS chain, which can reduce variance from
   per-frame ROI-averaging noise (the same coherent-averaging principle
   `ensembleAverageBeats.m`'s own `sqrt(N)` SNR-gain logic documents on the
   MATLAB side, applied here to raw sample density rather than beat count).
2. **A larger Nyquist safety margin.** `RealHeartRateEstimator`'s own guard
   (`fs <= 2.0 * HIGH_BAND_HZ`, i.e. `fs <= 8.0`) is comfortably satisfied
   at both ~13.4Hz (1.6x margin) and ~21.4Hz (2.65x margin) — higher fs
   makes this guard trip less often under a momentary fps dip, not a
   resolution change.
3. **Better-conditioned filter design.** `BandpassFilter`'s Butterworth
   design normalizes cutoffs by `fs`; a low `fs`-to-cutoff ratio can distort
   the bilinear-transform-designed filter's response near Nyquist. Higher
   `fs` gives the 0.7-4.0Hz band more headroom relative to Nyquist.

**None of these three benefits is "shorten the window and keep the same
resolution" — that specific trade is not physically available (resolution
is duration-bound, full stop).** The genuinely open, testable question this
DSP analysis leaves is narrower than the brief's original framing: *does
the extra per-window sample count at ~21.4Hz make a SHORTER window (e.g.
15s, trading some resolution for faster responsiveness) perform
comparably to the current 25s window did back when it was tuned against
~13.4Hz data* — an empirical SNR/robustness question the theory above
cannot resolve on its own, since the magnitude of benefit (1) is a real
device measurement, not a formula.

**Not changed this session.** `SignalBuffer.WINDOW_DURATION_SECONDS` stays
at `25.0` — changing it without a real before/after on-device comparison
would repeat the exact mistake the window-length follow-up in `android/
README.md` explicitly avoided the first time ("raises the buffer window...
and re-tests, rather than assuming the fix would work"). §5 specifies the
concrete test to run once a device is available.

## 4. On-device result: real A/B capture, a real bug found and fixed, then a real positive result

**VERIFIED on the same physical Samsung Galaxy A35 (SM-A356E)** used
throughout this project, `adb devices` confirmed attached (`RFCXC0FFFSN`).
`./gradlew assembleDebug`: **BUILD SUCCESSFUL**. Installed via `adb install
-r`, launched via `adb shell am start`.

### The bug the first capture surfaced

The first on-device attempt (smoothing temporarily enabled, a temporary
`Log.d("SPANDAN_SMOOTH", "raw=$hrRaw smoothed=$hrBpm")` line added in
`MainActivity.refreshUi()`, removed again once analyzed — same bounded
diagnostic discipline as `android/README.md`'s own `SPANDAN_TIMING`/
`SPANDAN_DIAG` instrumentation) showed the median catching up to a step
change in only 2-3 ticks (~400-600ms) instead of behaving like a genuine
5-measurement median. Root cause: `MainActivity`'s UI-refresh loop calls
`DisplaySmoother.smooth()` every 200ms, but `RealHeartRateEstimator.update()`
only recomputes a NEW value roughly once per second
(`RECOMPUTE_INTERVAL_MS=1000`) — so the identical raw value was being
pushed into the rolling-median history ~5 times per real measurement,
meaning `windowSize=5` (in ticks) only ever spanned about ONE real
recompute, not five independent ones. **Fixed** by de-duplicating
consecutive identical inputs inside `DisplaySmoother` itself (a repeated
tick of an already-seen value is now a no-op, the same contract as the
existing null-handling) — see the class's own header for the full
before/after. Two new unit tests added for this (the step-change test was
also corrected to use 5 genuinely distinct values instead of one value
repeated 5 times, which the bug had made look passing for the wrong
reason). `DisplaySmootherTest`: 8/8 passing after the fix.

### The re-run, with the fix in place

**83 distinct real recomputes over a ~66-second window** (`fs` measured at
14.3-17.4Hz on this run — notably different from both the README's older
~13.4Hz and ~21.4Hz figures, a reminder that measured fs varies run to run
and should always be re-measured, not assumed):

| | Raw (`hrRaw`) | Smoothed (`hrBpm`, rolling median, window=5) |
|---|---|---|
| Range | 42.5–132.4 bpm (89.9 span) | 44.9–125.0 bpm (80.1 span) |
| Stdev | 24.63 | 20.54 |
| Mean tick-to-tick jump | 17.46 bpm | **5.49 bpm (−69%)** |
| Max tick-to-tick jump | 67.49 bpm | 34.03 bpm (−50%) |

**Real, positive result for the stated goal (display smoothness), at zero
accuracy cost** (the raw switched value is still computed, logged, and
available unchanged — smoothing only ever touches what `hrText` shows).
The ~69% cut in mean tick-to-tick jump is the number that best matches what
a viewer actually perceives as "jumpiness." **Promoted `ENABLE_HR_DISPLAY_
SMOOTHING_DEFAULT` to `true`** on this evidence.

**Honest caveats, not smoothed over (pun noted)**: this is one ~66-second
capture, one subject, one session — no manual-pulse cross-check was taken
this round (the earlier capture in this same session, before smoothing was
enabled, used the same subject/device — see `Segment16_Task3_UI_UX_Pass.md`
§4 for that session's other on-device verification; no screenshots are
retained, per the user's request). Both raw and smoothed sequences still
swing across a physiologically-implausible range (42-132 bpm) within one
minute — **smoothing does not fix the underlying accuracy/jitter root
cause** (still the sparse-sampling/coarse-bin-resolution chain this
project has documented since the HR port); it only makes the number on
screen change less abruptly while that underlying issue persists. EMA mode
was not captured this round (median was tested first and already showed a
clear result) — a future session could still compare EMA head-to-head.

**Crash check across the whole session** (all builds/captures in this
task combined): zero `FATAL EXCEPTION`/`AndroidRuntime` entries; `pidof
com.spandan.app` confirmed unchanged across each individual run.

## 5. Window-length question: still not re-tested on-device

Unlike the `DisplaySmoother` A/B test, the window-length re-test (§3's
genuinely open empirical question) was **not** run this session — time was
spent on the smoothing test and the bug it surfaced instead.
`SignalBuffer.WINDOW_DURATION_SECONDS` stays at `25.0`, unchanged. For
whoever picks this up next:

1. With the frame-skip optimization's real, currently-measured fs
   (re-measure fresh each time — this session alone saw 14.3-17.4Hz,
   different from both of the README's older figures), capture the same
   scripted still/talking/moving timeline at `WINDOW_DURATION_SECONDS` =
   15, 20, and 25, and compare per-window sample count, HR MAE against a
   manual reference, and CHROM/POS agreement rate at each.
2. Per §3, do NOT expect FFT bin resolution itself to differ within a
   given duration regardless of fs — the comparison is about whether a
   shorter window's statistical robustness (from more samples per second)
   closes enough of the gap versus 25s to justify the faster
   responsiveness.
3. Report per this project's standing discipline: **if a shorter window
   doesn't help, say so plainly** rather than only reporting a favorable
   run.

## Files

- `android/app/src/main/java/com/spandan/app/signal/DisplaySmoother.kt` (new)
- `android/app/src/main/java/com/spandan/app/signal/EstimatorStatus.kt` (new, shared with Task 2/3)
- `android/app/src/test/java/com/spandan/app/signal/DisplaySmootherTest.kt` (new)
- `android/app/src/main/java/com/spandan/app/signal/RealHeartRateEstimator.kt` (modified — additive `lastStatus` property only, numeric logic unchanged)
- `android/app/src/main/java/com/spandan/app/MainActivity.kt` (modified — smoother wiring, gated off by default)
