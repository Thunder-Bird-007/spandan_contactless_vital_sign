# Segment 5 (SpO2 Ratio-of-Ratios + Calibration) — Team Instructions

This covers only Segment 5 of the pipeline: computing each subject's
AC/DC ratio-of-ratios from Segment 2/3 output, fitting a linear
calibration from R to SpO2%, a leave-one-out calibration attempt on
DATASET_1's 5 subjects with facial SpO2 ground truth, and a separate
code-correctness sanity check against the Hoffman finger-camera dataset.
It does **not** cover LOSO cross-validation, MAE/RMSE/correlation metrics,
or Bland-Altman plots — those are Segment 6 and are still stubs
(`validation/runLOSO.m`, `validation/computeMetrics.m`,
`validation/blandAltman.m`).

The actual code lives in the main scaffold, not in this folder:

- [`matlab/src/spo2/ratioOfRatios.m`](../matlab/src/spo2/ratioOfRatios.m)
- [`matlab/src/spo2/calibrateSpO2.m`](../matlab/src/spo2/calibrateSpO2.m)
- [`matlab/src/io/loadGroundTruth.m`](../matlab/src/io/loadGroundTruth.m)
  (implemented as part of this segment, since Step 3 below needs it — see
  the Line-by-Line doc's Part 0 for why)
- [`matlab/scripts/run_segment5_dataset1_calibration_batch.m`](../matlab/scripts/run_segment5_dataset1_calibration_batch.m)
- [`matlab/scripts/run_segment5_hoffman_sanity_check.m`](../matlab/scripts/run_segment5_hoffman_sanity_check.m)

This `segment5_spo2/` folder is docs only (no code):

- `Segment5_SpO2_Guideline.pdf` — theory background (why AC/DC per channel
  encodes oxygenation, why Blue substitutes for Infrared, why the R-to-
  SpO2 relationship must be fit empirically, the leakage risk on thin
  data, what the Hoffman check does and doesn't prove).
- `Segment5_LineByLine_Explanation.md` — a plain-language walkthrough of
  every block of `ratioOfRatios.m`, `calibrateSpO2.m`, and both batch
  scripts, including the actual results obtained.
- This README.

## Why this segment doesn't need splitting across 4 people the way Segments 2-4 did

Segments 2-4 split a **42-subject** pool across 4 team members, each
processing their own subset. Segment 5's primary calibration task
(`run_segment5_dataset1_calibration_batch.m`) runs against **DATASET_1's
5 subjects total** (`5-gt, 6-gt, 7-gt, 12-gt, after-exercise`) — there is
no meaningful way to split 5 subjects across 4 people, and the leave-
one-out loop needs all 5 loaded together in a single run anyway (each
fold's fit depends on having every other subject's data available at once,
unlike Segment 2-4's fully independent per-subject processing). **One
person running this script end-to-end is both sufficient and necessary**
— there's no parallelizable version of this particular step.

That doesn't mean the other 3 people have nothing to do this segment.
Two genuinely useful things to split instead:

### (a) Run the Hoffman sanity check on different subject subsets

`run_segment5_hoffman_sanity_check.m` currently trains on subjects
`100001-100004` and tests on `100005-100006` (see the script's top
variables). Different team members can re-run it with a different
train/test split (e.g. rotate which 2 subjects are held out) to see
whether the fitted `A`/`B` and the test-set error are stable across
different splits, or whether they swing around a lot — useful evidence
either way, and something one person alone doing a single split wouldn't
catch. This needs the Hoffman dataset cloned/copied into
`data/raw/Hoffman/data/` (see `docs/HOFFMAN_DATA_FORMAT.md` for exactly
what should be there) — small enough (a few MB of CSVs, no multi-GB
videos) to do independently of whichever DATASET_1 subjects you personally
have on disk.

### (b) Make sure your assigned DATASET_2 subjects have Segments 2-4 done

DATASET_2's 42 subjects have **no SpO2 ground truth at all** (confirmed in
`docs/DATA_FORMAT.md`) — they're irrelevant to this segment's SpO2 work.
But they still matter a lot for **Segment 6**, which will run its formal
LOSO validation on the **HR side** across every subject with HR ground
truth, DATASET_2 included, not just the 5 DATASET_1 subjects. If your
assigned DATASET_2 subjects don't have `run_segment2_roi_batch.m` and
`run_segment3_filtering_batch.m` (and ideally `run_segment4_heartrate_
batch.m`) run on them yet, doing that now is directly useful groundwork
for Segment 6, even though it has nothing to do with SpO2.

## 1. Before you start: confirm your Segment 2/3 output exists for DATASET_1

`run_segment5_dataset1_calibration_batch.m` needs, for **all 5** DATASET_1
subjects:

```
data/processed/<subjectID>_rgb_traces.mat        (Segment 2 output)
data/processed/<subjectID>_filtered_traces.mat   (Segment 3 output)
```

As of this segment's own verification run, all 5 subjects
(`5-gt, 6-gt, 7-gt, 12-gt, after-exercise`) already have both files —
`5-gt/6-gt/7-gt` were done as part of Segment 4's work, and `12-gt`/
`after-exercise` were run as part of finishing this segment (their raw
video+ground-truth junctions didn't exist under `data/raw/UBFC-rPPG/
DATASET_1/` before). If you're re-running this fresh and a subject's
files are missing, the script prints exactly which subject and which
segment's batch script to run first, then continues with whichever
subjects it *can* find rather than stopping entirely.

## 2. Running the DATASET_1 calibration

1. Open MATLAB, `cd` into `spandan/matlab/`.
2. Run `startup` (adds `src/` to the path).
3. `addpath('scripts')` (or `cd scripts`), then run
   `run_segment5_dataset1_calibration_batch`.

No subject list to edit — it always runs all 5 DATASET_1 subjects, since
the leave-one-out loop needs all of them together. It prints each
subject's `R` value and windowed ground-truth SpO2 as it loads, then each
leave-one-out fold's fitted `A`/`B` and prediction as it runs.

Output:
- `results/metrics/segment5_dataset1_calibration.csv` — one row per
  subject (`subjectID, R_value, SpO2_true, SpO2_predicted, abs_error`).
- `results/figures/segment5_dataset1_calibration_scatter.png` — predicted
  vs. actual SpO2, all 5 subjects labeled, with a y=x reference line.
  **Look at this before trusting the numbers** — with only 5 points and a
  ~3-percentage-point true-SpO2 spread, don't expect (or present) this as
  a validated calibration; see the Guideline PDF for why.

## 3. Running the Hoffman sanity check

1. Confirm `data/raw/Hoffman/data/` exists with `ppg-csv/` and `gt/`
   subfolders (see `docs/HOFFMAN_DATA_FORMAT.md` — clone
   `github.com/ubicomplab/oximetry-phone-cam-data` and copy its `data/`
   folder in, if you don't have it yet).
2. From `spandan/matlab/` (with `startup` and `addpath('scripts')` already
   done), run `run_segment5_hoffman_sanity_check`.

Output:
- `results/metrics/segment5_hoffman_sanity_check.csv` — one row per
  **held-out test window** (many rows per subject, not one; see the
  Line-by-Line doc for why this dataset is windowed instead of
  whole-clip).
- `results/figures/segment5_hoffman_sanity_scatter.png` — R vs. true SpO2
  for every window, with the fitted line overlaid.

**Remember what this does and doesn't prove.** A sensible-looking trend
here means `ratioOfRatios.m`/`calibrateSpO2.m` are implemented correctly
and respond to real SpO2 variation the way they should — it says nothing
about facial-video accuracy, since this is finger-on-camera data, a
completely different signal path. Don't cite this dataset's numbers as
evidence for how well the actual facial pipeline will do on DATASET_1 or
DATASET_2.

## 4. How this segment's outputs feed into Segment 6

Both CSVs here are raw material for Segment 6's job, not a substitute for
it — same relationship Segment 4's `segment4_hr_summary.csv` has to
Segment 6. `validation/runLOSO.m`, `validation/computeMetrics.m`, and
`validation/blandAltman.m` (all still untouched stubs) will eventually run
the actual statistically meaningful leave-one-subject-out validation, for
both HR (across DATASET_1 + DATASET_2) and SpO2 (across DATASET_1 only,
since that's the only source of SpO2 ground truth), with proper
MAE/RMSE/correlation/Bland-Altman reporting. This segment's job was to get
`ratioOfRatios.m`/`calibrateSpO2.m` implemented and demonstrably working
on real data — not to answer "is this method good enough," which is
Segment 6's call to make.
