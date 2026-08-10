# Segment 5 — Line-by-Line Explanation

This document walks through `matlab/src/spo2/ratioOfRatios.m`,
`matlab/src/spo2/calibrateSpO2.m`, `matlab/src/io/loadGroundTruth.m`, and
the two batch/sanity scripts (`matlab/scripts/run_segment5_dataset1_
calibration_batch.m` and `matlab/scripts/run_segment5_hoffman_sanity_
check.m`) block by block, in plain teaching language. It assumes you've
just finished Chapter 8 of the project's Orientation Lecture (ratio-of-
ratios and why empirical calibration is mandatory) but haven't seen this
specific implementation before. As with Segments 2-4, the code files
themselves are deliberately bare of inline comments — this document is
where the *why* lives.

---

## Part 0 — Two Judgment Calls You Need to Understand First

**Judgment call 1: `ratioOfRatios.m`'s signature grew, same reason as
Segment 4.** The original stub was:

```matlab
function R = ratioOfRatios(redSignal, blueSignal)
```

The shipped version is:

```matlab
function R = ratioOfRatios(R_filtered, G_filtered, B_filtered, R_raw, G_raw, B_raw, fs)
```

This is the exact same numerical problem Segment 4 already solved for
`chromCombine.m`/`posCombine.m`, applied here: `DC_channel = mean(raw_
channel)` needs a raw, pre-filter signal to mean anything physically. A
bandpass filter's whole job is to reject the 0 Hz component, so
`mean(filtered_channel)` is a near-zero number left over from filter edge
effects, not a real brightness baseline. The two-argument stub simply
didn't have anywhere to get a DC value from. The fix is the same one
Segment 4 already established: pass both the raw trace (for DC) and the
filtered trace (for AC) for each channel that's actually used.

::: pitfall
**Common beginner mistake.** Assuming "AC/DC ratio" means "compute
everything from one already-processed signal." AC and DC are, by
definition, two *different* views of the same physical quantity — DC is
the signal's steady average level, AC is how much it wiggles around that
level. A signal that's already been bandpass-filtered has had its DC
component deliberately removed, so it can only ever give you the AC half
of the story. You need the pre-filter version too, on purpose.
:::

`G_filtered` and `G_raw` are accepted but never used in the body — the
classic ratio-of-ratios formula only ever compares two wavelengths (here:
Red and Blue-as-infrared-substitute), never three. They're kept in the
signature purely so this function's inputs mirror the same `.mat` files
every other Segment 4/5 batch script already loads
(`<subjectID>_rgb_traces.mat` and `<subjectID>_filtered_traces.mat` both
carry all three channels) — passing all three keeps every caller's code
symmetrical, at the cost of two intentionally-unused parameters. Likewise
`fs` is accepted but unused: this function returns one whole-clip number,
so no sampling-rate-dependent computation happens inside it. Both are the
same kind of judgment call Segment 4 already documented for `posCombine.m`'s
unused `frameRate` argument.

**Judgment call 2: the whole-clip granularity, and why Hoffman needed
something different.** `ratioOfRatios.m` returns exactly **one** number
per call — DC and AC are each computed once, over the *entire* input
vector. Why is that the right choice for DATASET_1, and why did the
Hoffman sanity check (Part 3 below) need to do something different?

DATASET_1's own ground truth confirms the answer: per `docs/DATA_FORMAT.md`,
DATASET_1's SpO2 column is "typically near-constant or slowly varying
within a recording" — subjects sat resting for ~80-90 seconds, and their
oxygenation genuinely did not change much in that time (confirmed
end-to-end in this segment's own results: the 5 subjects' true SpO2 values
were all clustered in 96-99%, see Part 4). When the physical quantity
you're estimating barely moves during the clip, one whole-clip AC/DC
estimate — using the *entire* recording's worth of samples to compute a
single, low-noise `std()` and `mean()` — is strictly better than chopping
the clip into short windows and accepting a noisier per-window estimate
for no benefit, since there's no real within-clip trend to resolve.

The Hoffman dataset is the opposite case by design: subjects are actively
desaturating from ~100% down toward ~65% over a controlled ~15-20 minute
protocol specifically so their SpO2 *does* move substantially within a
single recording. A single whole-clip R value per subject would average
away exactly the variation the dataset exists to provide, collapsing 6
subjects' worth of the 65-100% range down to 6 points that might all
average out close together. That's why `run_segment5_hoffman_sanity_
check.m` computes one R value per **5-second window** instead of one per
subject — see Part 3.

::: intuition
**Intuition first.** Think of whole-clip vs. windowed the same way you'd
think about how long to average a noisy classroom thermometer reading.
If the room's temperature is genuinely stable, averaging over a longer
stretch of readings only helps — it cancels out sensor noise with no
downside, because there's no real signal changing underneath. If instead
someone is deliberately opening and closing a window every few minutes to
swing the temperature, averaging over the whole session bulldozes right
over the very thing you were trying to measure. Which one is right isn't
a fixed rule — it depends on whether the underlying physical quantity is
actually moving during your observation window.
:::

::: pausecheck
**Pause and check yourself.** DATASET_1's `after-exercise` subject has a
visibly elevated heart rate (per Segment 4's data) but a fairly normal
resting SpO2 in the low-to-high 90s. If a future dataset specifically
recorded subjects' SpO2 *during* a rapid exercise-to-rest transition
(genuinely changing within one clip), would whole-clip `ratioOfRatios.m`
still be the right choice for that dataset, or would it need the same
windowed treatment the Hoffman script uses? What physical property of the
recording is actually the deciding factor?
:::

---

## Part 1 — `ratioOfRatios.m`

### Signature and DC computation

```matlab
DC_R = mean(R_raw);
DC_B = mean(B_raw);
```

Two scalars: the average pixel-intensity level of the Red and Blue
channels across the whole clip, computed from the **raw** (pre-detrend,
pre-filter) traces — the physically meaningful "how bright is this
channel on average" baseline, exactly the same DC concept Segment 4's
CHROM/POS normalization step already relied on.

### AC computation

```matlab
AC_R = std(R_filtered);
AC_B = std(B_filtered);
```

`std()` of the *filtered* (detrended + bandpass-limited to 0.7-4 Hz)
trace measures how much the signal wiggles around its own mean — and
because the filter has already restricted this to the physiological pulse
band, that wiggle amplitude is a genuine measure of pulsatile
(heartbeat-driven) variation, not just generic noise or slow drift. This
is the "AC" (alternating/pulsatile component) half of the classic
pulse-oximetry AC/DC framework.

### The ratio-of-ratios itself

```matlab
R = (AC_R / DC_R) / (AC_B / DC_B);
```

`AC_R / DC_R` is the Red channel's pulsatile amplitude *as a fraction of*
its own average brightness — this normalization matters because a
brighter-skinned subject or a brighter room would otherwise produce a
larger raw `AC_R` for reasons that have nothing to do with oxygenation.
Dividing by `DC_R` cancels that out, the same normalization idea Segment
4's CHROM/POS used for a different reason. The outer division compares
that normalized pulsatility between Red and Blue: oxygenated vs.
deoxygenated hemoglobin absorb red and infrared light differently, so as
true SpO2 changes, the *relative* pulsatility of Red vs. Blue-as-infrared
shifts in a predictable direction. `R` is that shift, captured as a
single number.

::: intuition
**Intuition first.** Picture squeezing a clear balloon full of blood
under two different colored lights. Every heartbeat, the balloon's volume
pulses slightly, and both lights dim very slightly in sync with the
pulse. How *much* each light dims relative to its own steady brightness
depends on how strongly that specific color of light is absorbed by the
blood inside — and how strongly blood absorbs red vs. infrared light
depends specifically on how much oxygen the hemoglobin is carrying. Two
oxygenation levels that look identical in plain brightness can still pulse
by different *relative* amounts under red vs. infrared light — R is built
specifically to pick up on that difference.
:::

Why Blue instead of a real infrared channel: a phone/webcam sensor has no
IR channel at all. Blue is used as a published, known substitute (see the
Guideline PDF for the citation and the physical reasoning) — this is an
established approximation from the remote-photoplethysmography
literature, not something invented for this project.

---

## Part 2 — `calibrateSpO2.m`

### Signature

```matlab
function [spo2Est, calibParams] = calibrateSpO2(R, groundTruthSpO2, calibParams)
```

Unchanged from the original stub. This function is deliberately a plain
black box with two modes, selected by whether `calibParams` is empty:

### Fit mode (`calibParams` passed in as `[]`)

```matlab
fitCoeffs = polyfit(R, groundTruthSpO2, 1);
slopeCoeff = fitCoeffs(1);
interceptCoeff = fitCoeffs(2);

A = interceptCoeff;
B = -slopeCoeff;

calibParams = struct();
calibParams.A = A;
calibParams.B = B;
```

`polyfit(R, groundTruthSpO2, 1)` fits the best-fit **line**
`groundTruthSpO2 ≈ slopeCoeff*R + interceptCoeff` in the ordinary
least-squares sense (minimizing total squared vertical distance between
the line and every training point) — a single, well-tested MATLAB
built-in was chosen over hand-rolling the normal-equations math, since a
degree-1 polynomial fit is exactly what `polyfit` is for and re-deriving
it by hand would only add a chance to get the linear algebra wrong for no
benefit.

The task's target form is `SpO2 = A - B*R` (the standard way this
particular relationship is written in the pulse-oximetry literature,
since SpO2 falls as R rises — a positive `B` means a normal, physically
expected downward-sloping relationship). `polyfit` returns the line in
`slope*R + intercept` form, so `A = interceptCoeff` directly, and
`B = -slopeCoeff` (flipping the sign converts "slope of a line written as
`+slope*R`" into "the size of the drop per unit R, written as `-B*R`").

### Apply mode (`calibParams` passed in as an existing `{A, B}` struct)

```matlab
A = calibParams.A;
B = calibParams.B;
```

Skips fitting entirely and just reuses the coefficients handed in.

### Prediction (both modes)

```matlab
spo2Est = A - B * R;
```

Same formula either way — evaluate the (fitted-or-given) line at whatever
`R` value(s) were passed in. In fit mode, `R` here is still the *training*
data, so `spo2Est` is the model's own prediction on the data it was just
fit to — not a held-out prediction. Callers that want a genuine held-out
prediction (both this segment's DATASET_1 and Hoffman scripts) call
`calibrateSpO2` a **second time**, in apply mode, on data the fit never
saw. The fit-mode `spo2Est` is returned anyway so a caller can compute
training-set residuals (`spo2Est - groundTruthSpO2`) as a quick sanity
check on the fit itself, if they want one — this segment's batch scripts
don't currently use that, but it's there because the task brief asked for
it to be optionally available.

Nothing here is DATASET_1-specific or Hoffman-specific — this is exactly
what "usable as a black box for both" means: both callers pass in plain
`R`/SpO2 vectors and get back plain numbers, with no dataset-aware
branching inside this function at all.

---

## Part 3 — `run_segment5_dataset1_calibration_batch.m`

This is a new batch script, added on top of the files the task brief
explicitly named, because Steps 3 and 5(a) of the brief require producing
`results/metrics/segment5_dataset1_calibration.csv` and `results/figures/
segment5_dataset1_calibration_scatter.png` — there was no existing script
that could do that, and every prior segment in this project (2, 3, 4)
follows the same one-script-per-batch-purpose convention under
`matlab/scripts/`. This mirrors Segment 4's own documented precedent of
extending beyond the literal stub file list when the brief's own
requirements need it.

### Loading each subject

```matlab
rgbData = load(rgbMatPath);
...
filteredData = load(filteredMatPath);
...
R_value = ratioOfRatios(R_filtered, G_filtered, B_filtered, R_raw, G_raw, B_raw, fs);
```

Straightforward: load both of Segment 2/3's saved `.mat` files per
subject (exactly like `run_segment4_heartrate_batch.m` does), call
`ratioOfRatios.m` once per subject to get that subject's single whole-clip
`R`.

### Timestamp-based ground-truth alignment — not a naive index match

```matlab
gt = loadGroundTruth(gtPath, 'dataset1');

videoDurationSec = numel(R_raw) / fs;
inClipMask = gt.timestamp <= videoDurationSec;
spo2InClip = gt.spo2(inClipMask);

SpO2_true = mean(spo2InClip);
```

DATASET_1's oximeter samples at ~62 Hz, completely independent of and
asynchronous with the video's ~28.67 fps — row 100 of `gtdump.xmp` does
**not** correspond to video frame 100. `roi/extractROISignals.m` computes
each frame's real acquisition time as `(frameIdx - 1) / frameRate`
internally, but that per-frame `roiTimestamps` array isn't saved to
`<subjectID>_rgb_traces.mat` (only `R`, `G`, `B`, `fs` are) — so this
script reconstructs the clip's total duration the same way,
`numFrames / fs`, and keeps only the ground-truth rows whose own timestamp
column falls inside that duration. This is genuine timestamp-based
alignment: it uses real elapsed seconds on both sides (video duration vs.
GT sample time) rather than assuming row-for-row correspondence between
two differently-sampled data streams.

::: pitfall
**Common beginner mistake.** Taking the first `numFrames` rows of
`gtdump.xmp` and treating them as "the ground truth for this video,"
because both start at index 1. At ~62 Hz vs. ~28.67 fps, `numFrames` rows
of oximeter data cover *less* real time than the video does — for a
~2400-frame DATASET_1 clip, `numFrames` GT rows would only span about
38-39 seconds of the oximeter's ~84-second recording, silently discarding
the back half of the ground truth and, worse, doing so without any error
or warning.
:::

### The leave-one-out loop

```matlab
for holdoutPos = 1:numUsable
    trainMask = true(1, numUsable);
    trainMask(holdoutPos) = false;

    R_train = usableR(trainMask);
    SpO2_train = usableSpO2True(trainMask);

    [~, calibParams] = calibrateSpO2(R_train, SpO2_train, []);

    R_test = usableR(holdoutPos);
    [spo2Pred, ~] = calibrateSpO2(R_test, [], calibParams);
```

Five subjects, five folds. Each fold fits `calibrateSpO2.m` fresh on the
other four subjects, then predicts the held-out fifth subject's SpO2 using
only that fit — the held-out subject's own `(R, SpO2)` pair never
participates in its own prediction. This is a **leakage-avoidance
measure**, not a claim that a 4-subject calibration is trustworthy. It
exists purely because DATASET_1 only has 5 subjects total, which is far
too few to carve out a separate, disjoint train/test split and still have
enough of either side to mean anything — leave-one-out is the smallest
possible way to guarantee no subject ever calibrates and then predicts
itself, given only 5 subjects to work with.

::: pitfall
**Common beginner mistake — and the single most important warning in this
document.** Do not confuse this loop with Segment 6's formal
leave-one-subject-out validation (`validation/runLOSO.m`,
`validation/computeMetrics.m`, `validation/blandAltman.m` — all still
untouched stubs, out of scope for this segment on purpose). This loop
produces exactly 5 (predicted, actual) pairs from 5 subjects with a
range of true SpO2 spanning less than 3 percentage points (96-99%, see
the results table below). That is not enough data, and not enough
dynamic range, to make any real claim about this method's accuracy on
facial video — it only proves the *code* runs correctly end-to-end and
produces plausible-looking numbers on real data. Segment 6's job is the
actual, statistically meaningful validation, across every available
subject and metric.
:::

### Results actually obtained (see Part 5 for the full run log)

The five leave-one-out folds produced a mean absolute error of about
**1.97 percentage points**, with individual errors ranging from about 1.2
to 3.8 points, and the fitted slope (`B`) flipping sign between folds (a
mix of positive and negative values across the 5 refits). Both of those
facts are expected and worth understanding, not swept under the rug —
see Part 5.

---

## Part 4 — `run_segment5_hoffman_sanity_check.m`

### Windowing instead of whole-clip

```matlab
windowSeconds = 5;
windowFrames = windowSeconds * cameraFps;
...
for windowPos = 1:numWindows
    frameStart = (windowPos - 1) * windowFrames + 1;
    frameEnd = windowPos * windowFrames;
    ...
    gtSecStart = (windowPos - 1) * windowSeconds + 1;
    gtSecEnd = windowPos * windowSeconds;
    SpO2_windowTrue = mean(spo2Valid(gtSecStart:gtSecEnd));
```

As established in Part 0, this dataset's whole point is that SpO2 moves
substantially *within* a single ~15-20 minute recording, so this script
carves each subject's recording into consecutive, non-overlapping
5-second windows (150 camera frames at the confirmed 30 fps) instead of
computing one number for the whole clip. Each window gets its own
`ratioOfRatios.m` call and is paired with the mean of the 5 matching
ground-truth seconds — turning one subject's single recording into
roughly 150-220 independent `(R, SpO2)` pairs that actually trace out the
desaturation trend, rather than 1 pair that averages it away.

Camera-frame-to-GT-second alignment uses the same fixed
frames-per-second grouping the dataset's own authors use in their
`examples/preprocess_data_spo2.py` (confirmed by reading that file
directly, not assumed from the README) — see `docs/HOFFMAN_DATA_FORMAT.md`
Section 4 for the full justification.

::: pausecheck
**Pause and check yourself.** Why 5 seconds specifically, and not, say,
30 seconds or 1 second? (Hint: think about what happens to the number of
usable `(R, SpO2)` pairs, and to the noisiness of each window's own
`std()`-based AC estimate, as the window gets longer or shorter — the
same tradeoff Segment 4's Guideline PDF covered for FFT frequency
resolution vs. clip length, just applied to a `std()` estimate's
statistical stability instead of a frequency bin's width.)
:::

### Reusing this project's own filtering functions, not reimplementing them

```matlab
[R_detrendedWindow, detrendOrder] = detrendSignal(R_rawWindow);
...
[R_filteredWindow, filterOrder] = bandpassClean(R_detrendedWindow, cameraFps);
...
R_value = ratioOfRatios(R_filteredWindow, G_filteredWindow, B_filteredWindow, R_rawWindow, G_rawWindow, B_rawWindow, cameraFps);
```

The task brief says this script should not reuse `roi/extractROISignals.m`
(there's no face or ROI in a finger-on-camera recording, so that function
is simply the wrong tool) and should be self-contained. It does not say
to avoid this project's own general-purpose signal-processing functions —
`detrendSignal.m` and `bandpassClean.m` have nothing face-specific about
them, and reusing them (instead of writing a second, slightly different
detrend/filter implementation just for this script) keeps every AC value
in this project computed the same way. Calling `ratioOfRatios.m` itself
here is the most important reuse of all: this sanity check is explicitly
about confirming *this segment's own production code* behaves sensibly on
real, wide-range data, not about reimplementing a parallel version of it
just to test a copy.

### Train/test split by subject, not by window

```matlab
trainSubjectList = {'100001', '100002', '100003', '100004'};
testSubjectList = {'100005', '100006'};
```

Splitting by *subject* (4 subjects' worth of windows for training, 2
subjects' worth for testing) rather than randomly shuffling individual
windows across train/test matters for the same leakage reason as
DATASET_1's leave-one-out loop: windows from the same subject's recording
are highly correlated with each other (same finger, same skin, same
device, same session), so a random per-window split would let the model
implicitly "recognize" a test subject from other windows of that same
subject it already saw in training — an easier, less honest test than
genuinely predicting an unseen subject.

### Fit once, apply once

```matlab
[~, calibParams] = calibrateSpO2(R_train, SpO2_train, []);
...
[SpO2_testPredicted, ~] = calibrateSpO2(R_test, [], calibParams);
```

One fit on all pooled training windows (from 4 subjects), applied once to
all pooled test windows (from the other 2 subjects) — a simple train/test
split, exactly as the task brief allows ("a leave-some-out or simple
train/test split calibration"), not a full cross-validation loop. This is
a sanity check, not a rigorous validation study.

### A real anomaly that had to be investigated, not accepted

The first version of this script's scatter plot (a single pooled cloud of
all subjects' windows together) looked close to a random cloud, with only
a very shallow overall trend — exactly the pattern the task brief warns
"signals a bug, not just noisy data, and must be investigated and
reported, not silently accepted." So it was investigated, with a small
throwaway diagnostic script computing Pearson correlation between `R` and
`SpO2_true` separately per subject, and pooled across all subjects:

```
Subject 100001: n = 218, corr(R, SpO2) =  0.138
Subject 100002: n = 224, corr(R, SpO2) = -0.541
Subject 100003: n = 213, corr(R, SpO2) = -0.316
Subject 100004: n = 203, corr(R, SpO2) =  0.357
Subject 100005: n = 185, corr(R, SpO2) = -0.704
Subject 100006: n = 166, corr(R, SpO2) = -0.465
Pooled (all subjects together): corr(R, SpO2) = -0.074
```

Four of the six subjects show a moderate-to-strong **negative**
correlation (the physiologically expected direction: SpO2 falls as R
rises) — two subjects (`100001`, `100004`) show a weak *positive*
correlation instead. But the pooled number, computed by throwing every
subject's windows into one bucket and ignoring which subject each point
came from, is close to zero — much weaker than almost every individual
subject's own correlation.

That gap is the real finding: **each subject has their own baseline R
offset** (different skin tone, finger pressure, perfusion, exact
positioning on the camera+flash) that shifts their whole cluster of
points left or right along the R axis, independent of their SpO2. A
single pooled straight line, fit across six differently-offset clusters,
partly cancels out the real within-subject trend instead of capturing it
— this was confirmed directly by re-computing the pooled correlation after
z-scoring each subject's `R` values individually first (removing each
subject's own offset before pooling): the pooled correlation improved from
`-0.074` to `-0.260`, a real jump, confirming the individual per-subject
signal is genuine and gets diluted, not fabricated, when naively pooled.

This is not a coincidence unique to Hoffman, either — it's the same
underlying issue as DATASET_1's leave-one-out `B` sign instability in
Part 5 below: a linear ratio-of-ratios calibration is known in the
pulse-oximetry literature to need **per-subject or per-device**
correction terms to work well; a single global line across heterogeneous
subjects is a known weak spot of this simple approach, not evidence that
`ratioOfRatios.m` itself is broken. Given this, `run_segment5_hoffman_
sanity_check.m` was extended (without changing the underlying pooled-fit
calibration itself, since that's what the task brief actually asks this
script to demonstrate) to print every subject's own correlation to the
console on every run, and to plot a second panel next to the original
pooled scatter — the same points, colored per subject instead of by
train/test — specifically so this real per-subject trend is visible
alongside the weaker pooled one, instead of hidden behind it.

::: pausecheck
**Pause and check yourself.** If this segment's calibration approach were
changed to fit a *separate* line per subject instead of one pooled line,
would that fix the accuracy problem this section describes, or would it
just trade one problem (a diluted pooled fit) for a different one (a
model that can only predict SpO2 for subjects it has already seen)? What
would you need in order to get the benefit of per-subject correction
*without* that new problem?
:::

---

## Part 5 — Results Actually Obtained (not just described)

### DATASET_1 leave-one-out (5 subjects, all real facial video)

| Subject | R (ratio-of-ratios) | SpO2 true (%) | SpO2 predicted (%) | Abs. error |
|---|---|---|---|---|
| `5-gt` | 0.8358 | 98.89 | 96.83 | 2.06 |
| `6-gt` | 0.8595 | 96.55 | 97.87 | 1.32 |
| `7-gt` | 0.8638 | 96.44 | 97.96 | 1.52 |
| `12-gt` | 0.5203 | 95.99 | 99.76 | 3.77 |
| `after-exercise` | 0.7176 | 97.96 | 96.79 | 1.17 |

Mean absolute error across all 5 folds: **1.97 percentage points**.

Two things are worth being honest about here, not glossing over:

1. **The true SpO2 range across all 5 subjects is only about 96-99%.**
   This is a resting, healthy population with no controlled desaturation
   protocol — there simply isn't much oxygenation variation for a
   calibration to explain, which is a big part of why this is being
   called a "calibration attempt," not a validated calibration.
2. **The fitted slope's sign is not stable across the 5 refits** (`B`
   ranges from about -4.7 to +7.7 across the different leave-one-out
   folds, meaning the *direction* of the fitted relationship flips
   depending on which single subject happens to be excluded). With only 4
   training points and under 3 percentage points of true spread to fit
   against, this instability is expected, not a bug — it's exactly the
   kind of thing "5 subjects is genuinely thin data" (Section 3 of the
   task brief, echoed throughout this document) was warning about in
   advance.

### Hoffman sanity check (6 subjects, finger-camera, wide FiO2-driven range)

Run end-to-end on all 6 subjects (4 training: `100001-100004`, 2 held-out
test: `100005-100006`), with 5-second windowing producing 1209 total
`(R, SpO2)` pairs (858 training, 351 test), spanning subjects' individual
window counts of 166-224 depending on each recording's actual length.

```
Fitted on training windows: A = 90.5997, B = 1.9362
Mean absolute error on 351 held-out test windows: 8.5566 percentage points
```

`B` came out positive (`1.94`), which is the physiologically correct sign
(`SpO2 = A - B*R`, so SpO2 falls as R rises) — the pooled fit did land in
the right direction. The 8.56-point test MAE, spread over this dataset's
~35-percentage-point true range (65-100%), is a modest but real result,
not a strong one: consistent with the per-subject-vs-pooled correlation
finding directly above, a single pooled line captures *some* of the real
relationship but leaves real per-subject offset variation as unexplained
error. The two-panel scatter plot
(`results/figures/segment5_hoffman_sanity_scatter.png`) shows this
directly: the left panel (pooled, train/test colored, with the fitted
line) shows a real but visually subtle downward trend; the right panel
(same points, colored per subject) shows each subject's own cluster
tracing a much clearer trend along its own R range. Together they confirm
this is genuine, physiologically-consistent signal with real per-subject
structure, not a random, structureless cloud — the specific distinction
the task brief's verification instructions asked to be checked and
reported, not assumed.

---

## How This Segment Feeds Into Segment 6

Both scripts here produce `(R, SpO2_true, SpO2_predicted, abs_error)`
rows in `results/metrics/`, in the same spirit as Segment 4's HR summary
CSV — raw material for later comparison, not a substitute for it.
Segment 6's `validation/runLOSO.m` and `validation/computeMetrics.m`
(both still untouched stubs) are where a statistically meaningful
leave-one-subject-out validation, across every subject with SpO2 ground
truth and with proper MAE/RMSE/correlation/Bland-Altman reporting, will
actually happen. What this segment provides is confirmation that the
underlying `ratioOfRatios.m`/`calibrateSpO2.m` code is implemented
correctly and behaves sensibly — Segment 6 is where the team finds out
whether the *method itself* is good enough to trust.
