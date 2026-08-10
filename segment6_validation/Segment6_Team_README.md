# Segment 6 (Formal Validation: LOSO, Metrics, Bland-Altman) — Team Instructions

This covers Segment 6 of the pipeline: pooling the already-computed
per-subject results sitting in Segment 4's HR CSVs and Segment 5's SpO2
CSVs (UBFC + VIPL), running MAE/RMSE/Pearson correlation and Bland-Altman
analysis across the full pool, and producing a genuine leave-one-subject-out
(LOSO) SpO2 calibration refit across **both datasets pooled together**.

This segment does **not** reprocess any video or raw signal trace, and does
**not** touch `roi/extractROISignals.m`, `filtering/bandpassClean.m`,
`pulseextraction/chromCombine.m`/`posCombine.m`, `heartrate/fftHeartRate.m`,
`spo2/ratioOfRatios.m`, or any of the `io/` loaders — all of those are
Segments 2-5's job, already done and frozen. Segment 6 is a pure
consumer of their CSV output.

The actual code lives in the main scaffold, not in this folder:

- [`matlab/src/validation/computeMetrics.m`](../matlab/src/validation/computeMetrics.m)
- [`matlab/src/validation/blandAltman.m`](../matlab/src/validation/blandAltman.m)
- [`matlab/src/validation/runLOSO.m`](../matlab/src/validation/runLOSO.m)
  (SpO2 only — see below for why HR doesn't get this treatment)
- [`matlab/scripts/run_segment6_validation.m`](../matlab/scripts/run_segment6_validation.m)

This `segment6_validation/` folder is docs only (no code):

- `Segment6_Validation_Guideline.pdf` — theory background (what
  Bland-Altman actually shows vs. a plain scatter, why pooling UBFC+VIPL
  for SpO2 calibration is the right move, the calibrated-vs-uncalibrated
  distinction, and how this maps onto Dr. Hasan's live defense-day
  comparison).
- `Segment6_LineByLine_Explanation.md` — a plain-language walkthrough of
  every block of `computeMetrics.m`, `blandAltman.m`, `runLOSO.m`, and the
  batch script, including the actual results obtained.
- This README.

## Why HR and SpO2 are validated differently — the one thing to internalize before running anything

**HR has no fitted parameter.** `heartrate/fftHeartRate.m` just reads an
FFT peak — nothing is learned from any subject's ground truth, so there is
no leakage risk, and HR is pooled and scored directly with
`computeMetrics.m`, no held-out folds needed.

**SpO2's `calibrateSpO2.m` fits a line (`A`, `B`) from data.** If a
subject's own point helped fit the line that then "predicts" that same
subject, the result is leaked and looks better than it should. So SpO2 gets
a genuine leave-one-subject-out refit via `runLOSO.m`: every fold fits fresh
on every *other* subject in the **entire pooled UBFC+VIPL set**, then
predicts the held-out one.

See `Segment6_LineByLine_Explanation.md` Part 0 for the full argument, with
a worked analogy.

## The current pooled SpO2 N is still thin — say so, every time

As of this segment's own verification run:

```
SpO2 pooled: 8 total subjects with SpO2 ground truth (UBFC + VIPL combined).
  UBFC: 5 subjects (5-gt, 6-gt, 7-gt, 12-gt, after-exercise)
  VIPL: 3 subjects (VIPL_p1_v1_source1, VIPL_p2_v1_source1, VIPL_p3_v1_source1)
```

**8 subjects total is not enough to call this a validated calibration.**
The pooled MAE (1.23 percentage points) and the physiologically-correct-
direction Pearson r (-0.755) are genuinely encouraging early signals —
better than Segment 5's own DATASET_1-only 5-subject result — but 8 is
still a small number for a leave-one-out study, and every fold's fit is
still built on only 7 training subjects. **Do not present these numbers in
the report or defense as "the SpO2 calibration is validated."** Present
them as "early pooled results, N=8, improving as more VIPL subjects come
in" — which is the honest, defensible framing.

HR's pooled N is currently even thinner and for a different, fixable
reason: UBFC's own `segment4_hr_summary.csv` has `HR_groundtruth = NaN` for
all 3 of its rows (that CSV was written before `io/loadGroundTruth.m` was
implemented — see the Line-by-Line doc Part 4). Today's pooled HR metrics
are effectively **VIPL's 3 subjects only**. Re-running
`run_segment4_heartrate_batch.m` on the UBFC subjects now that
`loadGroundTruth.m` exists (a Segment 4 task, not this segment's to do) is
the fix, and once that CSV has real UBFC ground truth, the very next run of
`run_segment6_validation.m` will pool it in automatically.

## Why this segment auto-picks-up whatever data currently exists

`run_segment6_validation.m` checks whether each of the four source CSVs
exists with a plain `isfile(...)` before reading it, and pools however many
rows it actually finds — there is no hardcoded subject count or list
anywhere in this script. **As more VIPL subjects get extracted and run
through `run_vipl_integration_batch.m`, and as `segment5_vipl_calibration.csv`
grows, re-running `run_segment6_validation.m` periodically will tighten
every number in this segment's output automatically, with zero code
changes needed.** This is the concrete mechanism behind the "keep re-running
this as data comes in" instruction — there is nothing else to configure.

## 1. Before you run anything

Confirm these exist (all should already be present from Segments 4-5's own
work):

```
results/metrics/segment4_hr_summary.csv        (UBFC HR, from Segment 4)
results/metrics/segment4_hr_summary_vipl.csv   (VIPL HR, from VIPL integration)
results/metrics/segment5_dataset1_calibration.csv  (UBFC SpO2, from Segment 5)
results/metrics/segment5_vipl_calibration.csv      (VIPL SpO2, from VIPL integration)
```

If any one of these is missing, `run_segment6_validation.m` prints which
one and continues with whatever it can find rather than stopping — but
fewer inputs means a smaller, weaker pool, so it's worth running the
relevant upstream batch script first if you can.

## 2. Running Segment 6

1. Open MATLAB, `cd` into `spandan/matlab/`.
2. Run `startup` (adds `src/` to the path).
3. `addpath('scripts')` (or `cd scripts`), then run
   `run_segment6_validation`.

No subject list to edit, no configuration — it always pools whatever the
four source CSVs currently contain.

Output:

- `results/metrics/segment6_hr_pooled_metrics.csv` — one row per
  (method, scope), columns `method, scope, N, MAE, RMSE, Pearson_r`, scope
  in `{pooled, UBFC, VIPL}`.
- `results/metrics/segment6_spo2_loso_pooled.csv` — one row per subject's
  LOSO fold, columns `subjectID, dataset, R_value, SpO2_true,
  SpO2_predicted, abs_error`.
- `results/metrics/segment6_spo2_loso_metrics.csv` — one row per scope,
  columns `scope, N, MAE, RMSE, Pearson_r`.
- `results/figures/segment6_hr_bland_altman_chrom.png`,
  `segment6_hr_bland_altman_pos.png`, `segment6_hr_bland_altman_green.png`
  — pooled HR Bland-Altman, dataset-colored.
- `results/figures/segment6_spo2_bland_altman_pooled.png` — pooled SpO2
  LOSO Bland-Altman, dataset-colored.
- `results/figures/segment6_spo2_predicted_vs_true.png` — SpO2 LOSO
  predicted vs. true scatter with a y=x reference line, dataset-colored.

The script also prints a final plain-text summary (pooled and per-dataset
N/MAE/RMSE/Pearson r for SpO2-LOSO and each HR method) straight to the
console — that block is what to quote in the report or read from live on
defense day, since it's always freshly computed from whatever data exists
at run time.

**Look at the Bland-Altman and scatter plots before quoting any number.**
With this few points, a single unusual subject can visibly shift a bias
line or a limit of agreement — the plots make that obvious in a way a bare
MAE number does not.

## 3. What to do next as a team

- **Whoever extracts more VIPL subjects**: run
  `run_vipl_integration_batch.m` on your assigned subjects (per
  `vipl_integration/VIPL_Team_README.md`), which grows
  `segment4_hr_summary_vipl.csv` and `segment5_vipl_calibration.csv`. Then
  just re-run `run_segment6_validation.m` — nothing else to do.
- **Whoever owns Segment 4's UBFC CSV**: re-running
  `run_segment4_heartrate_batch.m` on `5-gt`/`6-gt`/`7-gt` now that
  `io/loadGroundTruth.m` is implemented will replace those `NaN`
  ground-truth rows with real values, immediately widening HR's pooled N
  the next time Segment 6 runs.
- **Before the defense**: re-run `run_segment6_validation.m` one more time
  the day before, so the numbers you present are the freshest ones
  available, and re-read this README's N caveats so nobody accidentally
  overstates confidence in front of Dr. Hasan.
