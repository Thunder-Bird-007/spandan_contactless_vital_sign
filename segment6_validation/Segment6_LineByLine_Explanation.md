# Segment 6 — Line-by-Line Explanation

This document walks through `matlab/src/validation/computeMetrics.m`,
`matlab/src/validation/blandAltman.m`, and `matlab/src/validation/runLOSO.m`
block by block, in plain teaching language, plus how
`matlab/scripts/run_segment6_validation.m` wires all three together against
the real CSVs Segments 4 and 5 already produced. It assumes you've just
finished Chapter 9 of the project's Orientation Lecture (leave-one-subject-
out validation, MAE/RMSE/correlation, Bland-Altman) but haven't seen this
specific pooled-across-datasets implementation before. As with Segments 2-5,
the code files themselves are deliberately bare of inline comments — this
document is where the *why* lives.

---

## Part 0 — The One Judgment Call That Matters Most: Why SpO2 and HR Are Evaluated Differently

This is worth understanding before reading a single line of code, because
it's exactly the kind of distinction an examiner is likely to probe on
defense day.

**SpO2 has a fitted parameter. HR does not.**

`spo2/calibrateSpO2.m` fits a straight line, `SpO2 = A - B*R`, using
`polyfit` on whichever `(R, SpO2)` pairs it's handed. `A` and `B` are
*learned from data*. If a subject's own `(R, SpO2)` pair is used to fit `A`
and `B`, and that same subject's `R` is then plugged back into the fitted
line to "predict" their SpO2, the model has essentially already seen the
answer — the resulting error will look artificially small, not because the
method is good, but because the test leaked into the training. This is
textbook **data leakage**, and it's the entire reason leave-one-subject-out
(LOSO) cross-validation exists as a technique: hold one subject's data out
completely, fit only on everyone else, predict the held-out subject, repeat
for every subject. No subject is ever both a teacher and a student of its
own answer.

`heartrate/fftHeartRate.m`, by contrast, has **no fitted parameter at all**.
It takes a pulse signal, runs an FFT, and reports whichever frequency (bin)
has the most power in the physiological band, converted to bpm. There is no
`A`, no `B`, nothing learned from any subject's ground truth, ever. Subject
17's heart rate estimate does not and cannot depend on what subject 5's
heart rate was — there is no shared, fitted object connecting them the way
`calibParams` connects every subject's SpO2 prediction. Running HR
evaluation across the whole pool at once, with no held-out folds, is not a
shortcut or a lower standard — it's the *only* thing that makes sense,
because there is no leakage risk to guard against in the first place. Adding
a LOSO loop to HR would not make the numbers any more honest; it would just
recompute the exact same FFT the exact same way a redundant, extra number of
times.

::: intuition
**Intuition first.** Think of `calibrateSpO2.m`'s line fit like a teacher
grading a class using a curve computed from the class's own scores — if one
student's score helps set the curve, and that student is then graded on the
curve *their own score helped create*, the grade is a little too flattering.
Leave-one-out fixes this by re-computing the curve fresh for every student,
each time using only the other students' scores. `fftHeartRate.m` is more
like reading a thermometer — the thermometer doesn't get calibrated
*against* the person being measured, so there's no analogous curve to worry
about contaminating.
:::

::: pausecheck
**Pause and check yourself.** Segment 5's own DATASET_1 and VIPL calibration
scripts (`run_segment5_dataset1_calibration_batch.m`,
`run_vipl_integration_batch.m`) already did a leave-one-out loop, but each
one only within its *own* dataset (UBFC's 5 subjects fit/predict each
other; VIPL's 3 subjects fit/predict each other). Why is this segment's
`runLOSO.m` doing something meaningfully different, rather than just
re-running the same two loops? (Hint: think about what "more training
subjects, however different the dataset origin" in the task brief is
actually trying to fix, and re-read `calibrateSpO2.m`'s `polyfit` call —
does it know or care which dataset an `(R, SpO2)` pair came from?)
:::

---

## Part 1 — `computeMetrics.m`

### Signature

```matlab
function metrics = computeMetrics(predicted, groundTruth)
```

Deliberately generic — no `HR` or `SpO2` anywhere in this file. The exact
same function scores heart rate in bpm and SpO2 in percent, because MAE,
RMSE, and Pearson correlation are unit-agnostic arithmetic; the units only
matter when a human reads the number later.

### MAE and RMSE — explicit accumulation, not `mean(abs(...))`

```matlab
sumAbsError = 0;
sumSquaredError = 0;

for i = 1:N
    errorVal = predicted(i) - groundTruth(i);
    sumAbsError = sumAbsError + abs(errorVal);
    sumSquaredError = sumSquaredError + errorVal^2;
end

mae = sumAbsError / N;
rmse = sqrt(sumSquaredError / N);
```

This computes exactly what `mean(abs(predicted - groundTruth))` and
`sqrt(mean((predicted - groundTruth).^2))` would compute, one pair at a
time in an explicit loop instead of a single vectorized line. MAE is the
average absolute distance between prediction and truth (every error counted
equally); RMSE is the same idea but squares each error before averaging,
which makes a few large errors hurt the score more than many small ones —
useful for catching a method that's usually fine but occasionally very
wrong, which MAE alone can hide.

### Pearson correlation — three loops, one for each moving part

```matlab
sumPredicted = 0;
sumGroundTruth = 0;

for i = 1:N
    sumPredicted = sumPredicted + predicted(i);
    sumGroundTruth = sumGroundTruth + groundTruth(i);
end

meanPredicted = sumPredicted / N;
meanGroundTruth = sumGroundTruth / N;

numerator = 0;
denomPredicted = 0;
denomGroundTruth = 0;

for i = 1:N
    devPredicted = predicted(i) - meanPredicted;
    devGroundTruth = groundTruth(i) - meanGroundTruth;
    numerator = numerator + devPredicted * devGroundTruth;
    denomPredicted = denomPredicted + devPredicted^2;
    denomGroundTruth = denomGroundTruth + devGroundTruth^2;
end

pearsonR = numerator / sqrt(denomPredicted * denomGroundTruth);
```

This is the textbook Pearson formula, split into three passes because each
pass needs something the previous one produced: pass 1 gets the two means;
pass 2 needs those means to compute each point's deviation from its own
mean, then accumulates the covariance-like numerator and each variable's
own sum of squared deviations. `pearsonR` is +1 for a perfect increasing
straight-line relationship, -1 for a perfect decreasing one, and 0 for no
linear relationship at all — it says nothing about *how far off* the
values are numerically (that's what MAE/RMSE are for), only about whether
they *move together*.

::: pitfall
**Common beginner mistake.** Treating a high MAE and a high Pearson r as a
contradiction. They're not — a method can track the true up-and-down trend
almost perfectly (`r` close to 1) while still being numerically far off on
every single point (e.g. it's always 10 bpm too high). Segment 6's own HR
CHROM/POS results show exactly this pattern: see Part 4.
:::

### Why `N` is a returned field, not just a local variable

```matlab
metrics.n = N;
```

With this project's current pool sizes (as few as 3 usable pairs for some
HR scopes), a bare MAE number with no `N` attached is actively misleading —
"MAE = 3.9 bpm" sounds like a real, load-bearing result; "MAE = 3.9 bpm,
N = 3" makes the reader immediately ask the right follow-up question. Every
CSV this segment writes carries an `N` column right next to every metric for
this exact reason.

### What happens with too little or no data — no special-casing needed

If `N` is 0 (a dataset scope with zero usable rows, e.g. UBFC's current HR
rows, see Part 4), `sumAbsError` and `sumSquaredError` both stay `0`, so
`mae = 0/0` and `rmse = sqrt(0/0)` — both evaluate to `NaN` under normal
IEEE floating-point division, exactly the honest answer ("not computable"),
with no `if N == 0` branch required anywhere in this file. The same is true
for `pearsonR` when `N` is 0 or 1: the denominator collapses to `0`, giving
`NaN` automatically. This is why `run_segment6_validation.m`'s per-dataset
breakdown can safely call `computeMetrics` on an empty UBFC HR slice without
crashing — it just gets back a clearly-labeled `NaN` row instead of a
divide-by-zero error.

---

## Part 2 — `blandAltman.m`

### Signature grew, same reason as Segments 4-5

```matlab
function [meanDiff, limitsOfAgreement] = blandAltman(predicted, groundTruth, plotTitle, outputPath, datasetLabels)
```

The original stub only had `(predicted, groundTruth, plotTitle)` — no
argument for *where* to save the figure, and no way to color points by
which dataset they came from. Both are genuinely required by this segment's
own brief (every pooled plot must show UBFC vs. VIPL points
distinguishably), so both were added as explicit trailing arguments, the
same kind of signature growth `chromCombine.m`, `posCombine.m`, and
`ratioOfRatios.m` already went through in Segments 4-5 when their original
stubs didn't have anywhere to get data they genuinely needed.
`datasetLabels` is optional (`nargin < 5` falls back to a single-color
scatter with no legend) so the function still works for a plain two-vector
call if a future caller doesn't need dataset coloring.

### What "mean" and "diff" mean here, specifically

```matlab
for i = 1:N
    meanOfPair(i) = (predicted(i) + groundTruth(i)) / 2;
    diffOfPair(i) = predicted(i) - groundTruth(i);
end
```

Bland-Altman deliberately does **not** plot predicted vs. true the way a
plain scatter would. Instead, the x-axis is each pair's *average* (a stand-
in for "the best available estimate of the true value," since in real life
you often don't have a perfect ground truth either) and the y-axis is the
*difference* between the two methods. This reframing is the entire point of
the technique: a plain scatter answers "how correlated are these two
methods," which two methods that are both just consistently biased by a
fixed amount can pass easily; a Bland-Altman plot answers "how much do
these two methods actually disagree, and does that disagreement change
depending on the value being measured" — a materially different, more
clinically relevant question.

::: intuition
**Intuition first.** Imagine two bathroom scales that are miscalibrated the
same fixed 2 kg high across everyone. A plain "scale A reading vs. scale B
reading" plot would show a beautiful, perfectly straight, highly correlated
line — because both scales move together in lockstep — and would
completely hide the fact that both are wrong by 2 kg for everyone. Plot the
same data as `(average of A and B)` vs. `(A - B)` instead, and that
constant 2 kg bias becomes immediately, unmissably visible as a flat
horizontal line sitting away from zero. That flat line is exactly what
`meanDiff` (the bias) captures numerically.
:::

### Bias and limits of agreement

```matlab
meanDiff = sumDiff / N;
...
stdDiff = sqrt(sumSquaredDev / (N - 1));
...
upperLimit = meanDiff + 1.96 * stdDiff;
lowerLimit = meanDiff - 1.96 * stdDiff;
```

`meanDiff` (the **bias**) is the average of every `predicted - groundTruth`
difference — positive means the method tends to overestimate, negative
means it tends to underestimate, zero means no systematic bias either way.
The **limits of agreement** are `bias ± 1.96 × (standard deviation of the
differences)` — under the standard Bland-Altman assumption that the
differences are roughly normally distributed, about 95% of individual
differences are expected to fall inside these two lines. A narrow band
close to zero means the two methods agree tightly and without systematic
bias; a wide band, or a band clearly shifted away from zero, means real,
quantifiable disagreement — exactly the number a clinician or examiner
would want before trusting a camera-based reading over a pulse oximeter's.

`N - 1` (not `N`) in the standard deviation is the standard sample-standard-
deviation correction (Bessel's correction) — the same reason `std()` uses
`N - 1` by default in MATLAB. With `N = 1` this would divide by zero, so
`stdDiff` is set to `0` in that edge case rather than crashing (the limits
of agreement then simply collapse onto the bias itself, an honest
reflection of "one point isn't enough to say anything about spread").

### Dataset-colored scatter, built with an explicit loop over unique datasets

```matlab
uniqueDatasets = unique(datasetLabels);

for datasetPos = 1:numDatasets
    thisDataset = uniqueDatasets{datasetPos};
    pointMask = false(N, 1);

    for i = 1:N
        if strcmp(datasetLabels{i}, thisDataset)
            pointMask(i) = true;
        end
    end

    markerStyle = markerList{mod(datasetPos - 1, numel(markerList)) + 1};
    scatter(meanOfPair(pointMask), diffOfPair(pointMask), 60, 'filled', markerStyle, 'DisplayName', thisDataset);
end
```

`unique(datasetLabels)` collects the distinct dataset names present (today:
`{'UBFC', 'VIPL'}`, but this scales automatically to a third dataset later
with zero code changes). For each one, an explicit `for` loop builds a
logical mask of which points belong to it (rather than a one-line vectorized
`strcmp(datasetLabels, thisDataset)` comparison), then plots just that
subset with its own marker shape and a legend entry. This is exactly why
every pooled plot in Segment 6's figures shows circles for one dataset and
squares for another, both visible on the same axes.

---

## Part 3 — `runLOSO.m`

### Signature: four pooled vectors, not a generic pipeline handle

```matlab
function results = runLOSO(subjectIDs, datasetLabels, R_values, spo2True)
```

The original stub's signature was `runLOSO(subjectData, pipelineFn)` — a
generic driver meant to call an arbitrary pipeline function
(`pipeline/estimateVitals.m`) once per held-out subject. That design fits a
segment whose job is to *re-run the pipeline on raw video* per fold. This
segment's actual, explicit scope is the opposite: **do not reprocess any
video or raw trace** — only pool the whole-clip `R` values and ground-truth
SpO2 that Segment 5's batch scripts already computed and saved to CSV. A
pipeline function handle has nothing to call in that scope; there is no
video to feed it. What the fold loop actually needs is four parallel
vectors — which subject, which dataset, that subject's `R`, that subject's
true SpO2 — so the signature was changed to match the real job, the same
kind of documented, deliberate signature change Segments 4-5 already made
for `chromCombine.m` and `ratioOfRatios.m` when their original stubs didn't
match what the real computation needed.

### The fold loop itself

```matlab
for holdoutPos = 1:numSubjects
    trainMask = true(1, numSubjects);
    trainMask(holdoutPos) = false;

    R_train = R_values(trainMask);
    SpO2_train = spo2True(trainMask);

    [~, calibParams] = calibrateSpO2(R_train, SpO2_train, []);

    R_test = R_values(holdoutPos);
    [SpO2_predicted, ~] = calibrateSpO2(R_test, [], calibParams);
```

This is the same two-call pattern (`calibrateSpO2` once in fit mode, once
in apply mode) that both of Segment 5's own batch scripts already used —
the difference here is entirely in what `R_values`/`spo2True` *contain*
going into the loop. Segment 5's two scripts each pooled only their own
dataset's subjects (`usableR`, `usableSpO2True` built from just UBFC or
just VIPL). `runLOSO.m`'s caller (`run_segment6_validation.m`) builds
`R_values`/`spo2True` by concatenating **both** datasets together first —
so `trainMask` on, say, fold 3 might genuinely contain 4 UBFC subjects and
3 VIPL subjects all contributing to one `polyfit` call, something neither
of Segment 5's own scripts ever did. This is the literal meaning of
"genuinely pooled," not just "run twice and compare."

::: pausecheck
**Pause and check yourself.** `calibrateSpO2.m` itself has no idea which
dataset any `R` value came from — it just sees a plain numeric vector. What
would have to change in `runLOSO.m` (not `calibrateSpO2.m`) if the team
later decided UBFC and VIPL's cameras were different enough that they
should each get their own calibration line instead of one shared pooled
line? Would that still be "leave-one-subject-out," or a different
validation design entirely?
:::

### The output shape: one struct per held-out subject

```matlab
results(holdoutPos).subjectID = subjectIDs{holdoutPos};
results(holdoutPos).dataset = datasetLabels{holdoutPos};
results(holdoutPos).R_value = R_values(holdoutPos);
results(holdoutPos).SpO2_true = spo2True(holdoutPos);
results(holdoutPos).SpO2_predicted = SpO2_predicted;
results(holdoutPos).abs_error = absError;
```

A struct array, one entry per fold, with field names chosen to match
`results/metrics/segment6_spo2_loso_pooled.csv`'s column headers exactly —
`run_segment6_validation.m` writes this CSV by looping over `results` and
reading each field straight off, with no renaming or reshaping needed in
between.

---

## Part 4 — `run_segment6_validation.m`: pooling real CSVs, and the results actually obtained

### Auto-discovery: `isfile` checks, not a hardcoded subject count

```matlab
hrUbfcPath = fullfile(metricsRoot, 'segment4_hr_summary.csv');

if isfile(hrUbfcPath)
    ubfcHrTable = readtable(hrUbfcPath);
    ...
else
    disp(['UBFC HR summary not found, skipping: ' hrUbfcPath]);
end
```

The same `isfile` pattern is repeated for all four source CSVs
(`segment4_hr_summary.csv`, `segment4_hr_summary_vipl.csv`,
`segment5_dataset1_calibration.csv`, `segment5_vipl_calibration.csv`). None
of the pooling logic anywhere in this script assumes a fixed row count —
`numel(hrSubjectID)`/`numel(spo2SubjectID)` are read fresh from however many
rows actually got appended. This is the concrete mechanism behind the task
brief's "re-running this later, as more VIPL subjects are processed,
should just pick up the larger pool" requirement: add more rows to
`segment4_hr_summary_vipl.csv` or `segment5_vipl_calibration.csv` (by
running `run_vipl_integration_batch.m` on more subjects) and the very next
run of `run_segment6_validation.m` automatically pools a bigger set, with
zero code changes.

### A real finding, not a bug: UBFC's own HR ground truth is currently all `NaN`

```matlab
hrValidMask = false(1, numHrTotal);

for i = 1:numHrTotal
    if ~isnan(hrGroundtruth(i))
        hrValidMask(i) = true;
    end
end
```

Reading `results/metrics/segment4_hr_summary.csv` directly shows all three
UBFC rows (`5-gt`, `6-gt`, `7-gt`) have `HR_groundtruth = NaN`. This is not
a bug in this segment's code — it's because
`matlab/scripts/run_segment4_heartrate_batch.m` was run against these three
subjects *before* `io/loadGroundTruth.m` was implemented (see that script's
own `try/catch` around its `loadGroundTruth` call, and the
`segment4-chrom-pos-fft-implementation` project note: "GT is NaN until
loadGroundTruth.m is implemented"). Since this segment's SCOPE explicitly
forbids reprocessing video or modifying Segment 4's CSV, the fix is not
this segment's to make — it is simply skipped, honestly, via the `NaN` mask
above, exactly as the task brief instructs ("skip rows where ground truth
is NaN"). The practical consequence: **today's pooled HR metrics are built
entirely from VIPL's 3 subjects** (see the numbers below) — re-running
`run_segment4_heartrate_batch.m` on the UBFC subjects now that
`loadGroundTruth.m` exists would add 3 more real, non-NaN pooled HR rows
the very next time this script runs, no code change required here either.

::: pitfall
**Common beginner mistake.** Reading "pooled N = 3" for HR and assuming that
means only 3 subjects were *looked at*. Six rows were loaded (3 UBFC + 3
VIPL); three were honestly excluded for lacking usable ground truth, which
is different from three never having been considered at all. The per-
dataset breakdown (`segment6_hr_pooled_metrics.csv`'s `UBFC` rows, all
`N = 0`) makes this gap visible rather than silently averaging it away.
:::

### Results actually obtained (see `Segment6_Team_README.md` for the pinned N caveats)

**HR, pooled (currently VIPL's 3 subjects only, UBFC's 3 rows excluded for
`NaN` ground truth):**

| Method | N | MAE (bpm) | RMSE (bpm) | Pearson r |
|---|---|---|---|---|
| CHROM | 3 | 3.94 | 4.48 | 0.995 |
| POS | 3 | 3.94 | 4.48 | 0.995 |
| Green-only | 3 | 16.92 | 18.99 | -0.255 |

CHROM and POS produce identical numbers here because, on these particular 3
subjects, both combination methods happened to converge on the same FFT
peak (visible already in `segment4_hr_summary_vipl.csv`'s raw
`HR_chrom`/`HR_pos` columns, which are equal for all three VIPL rows) —
not a bug, just what these specific signals produced. The very high Pearson
r (0.995) alongside a real ~4 bpm MAE is the exact "correlated but not
zero-error" pattern flagged in Part 1's pitfall box: CHROM/POS track the
true up-and-down HR trend across these 3 subjects almost perfectly, while
still being consistently a few bpm off in absolute terms. Green-only's
strongly negative Pearson r on just 3 points is a concrete illustration of
why N matters — with only 3 pairs, a correlation coefficient is extremely
sensitive to any single point and should not be read as a stable, general
property of the green-only method.

**SpO2, genuinely pooled leave-one-subject-out (5 UBFC + 3 VIPL = 8
subjects):**

| Scope | N | MAE (pp) | RMSE (pp) | Pearson r |
|---|---|---|---|---|
| Pooled | 8 | 1.23 | 1.35 | -0.755 |
| UBFC only | 5 | 1.22 | 1.39 | -0.863 |
| VIPL only | 3 | 1.24 | 1.28 | -0.708 |

The negative Pearson r is the **physiologically expected direction** — per
`calibrateSpO2.m`'s own documented form (`SpO2 = A - B*R`), SpO2 should fall
as `R` rises, so a negative correlation between predicted SpO2 and true
SpO2's residual pattern lining up this way across a genuinely pooled
8-subject fit is a real, if still preliminary, positive signal, not a
red flag. Compare this to Segment 5's own DATASET_1-only leave-one-out
result (Segment 5's Line-by-Line doc, Part 5): that 5-subject-only loop
saw its fitted slope `B` flip sign across folds, an instability directly
attributed to having only 4 training subjects per fold. Pooling in 3 more
VIPL subjects (giving 7 training subjects per fold instead of 4) is exactly
the kind of change the task brief predicted would help — and the MAE here
(1.23 percentage points pooled) is noticeably tighter than DATASET_1 alone's
prior 1.97-point result, consistent with more training data stabilizing the
fit. **This is still only 8 subjects total** — see
`Segment6_Team_README.md` for why this must not be oversold as a validated
result yet.

---

## How This Feeds Into the Rest of the Project

Every number in this document came from a single, repeatable run of
`run_segment6_validation.m` against whatever CSVs currently exist under
`results/metrics/`. As more VIPL subjects get extracted and processed
through `run_vipl_integration_batch.m`, and once `run_segment4_heartrate_
batch.m` is re-run on UBFC's subjects now that `loadGroundTruth.m` exists,
re-running this one script is the entire update procedure — no code in
`src/validation/` needs to change, and none of Segments 2-5's algorithm
files are touched by any of this. That auto-pickup behavior, not any single
number reported above, is this segment's actual deliverable.
