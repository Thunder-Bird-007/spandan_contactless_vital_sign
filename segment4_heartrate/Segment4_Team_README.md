# Segment 4 (CHROM/POS + FFT Heart Rate) — Team Instructions

This covers only Segment 4 of the pipeline: combining each subject's
filtered `R/G/B` traces from Segment 3 into a single pulse signal via
CHROM and via POS, running FFT-based heart-rate extraction on both
combined signals plus the raw green channel, and comparing all three
against ground truth where it's available. It does **not** cover SpO2
ratio-of-ratios/calibration or LOSO validation — those are Segments 5/6
and are still stubs.

The actual code lives in the main scaffold, not in this folder:

- [`matlab/src/pulseextraction/chromCombine.m`](../matlab/src/pulseextraction/chromCombine.m)
- [`matlab/src/pulseextraction/posCombine.m`](../matlab/src/pulseextraction/posCombine.m)
- [`matlab/src/heartrate/fftHeartRate.m`](../matlab/src/heartrate/fftHeartRate.m)
- [`matlab/scripts/run_segment4_heartrate_batch.m`](../matlab/scripts/run_segment4_heartrate_batch.m)

This `segment4_heartrate/` folder is docs only:

- `Segment4_HeartRate_Guideline.pdf` — theory background (why raw-green
  FFT is motion-fragile, what CHROM/POS physically do differently, why
  re-filtering after combination matters, the FFT resolution tradeoff in
  concrete bpm numbers for this dataset, common pitfalls).
- `Segment4_LineByLine_Explanation.md` — a plain-language walkthrough of
  every block of `chromCombine.m`, `posCombine.m`, and `fftHeartRate.m`,
  including the reasoning behind every parameter and judgment call.
- This README.

## 1. Before you start: confirm your Segment 3 output exists

This segment reads, for each subject, **two** files already produced by
earlier segments:

```
data/processed/<subjectID>_filtered_traces.mat   (Segment 3 output)
data/processed/<subjectID>_rgb_traces.mat        (Segment 2 output)
```

You need both, not just the filtered one — the raw `_rgb_traces.mat` is
used only to compute a physically meaningful brightness level for CHROM/
POS's normalization step (see the Guideline PDF / Line-by-Line doc for
why the filtered signal's own mean can't be used for this). If you've run
Segment 3 on your subjects already, both files should already be sitting
in `data/processed/` — Segment 3 loads `_rgb_traces.mat` itself and never
deletes it. If you don't see both files for a subject, re-run
`run_segment2_roi_batch.m` then `run_segment3_filtering_batch.m` for that
subject first.

## 2. Editing the subject list

Open `matlab/scripts/run_segment4_heartrate_batch.m`. Right at the top
there is one variable to edit:

```matlab
subjectList = {'5-gt', '6-gt', '7-gt'};
```

Change it to your own subject IDs — the same ones you already used for
Segments 2 and 3, since this script reads their `_filtered_traces.mat`
and `_rgb_traces.mat` files by that exact ID.

## 3. Running it

1. Open MATLAB, `cd` into `spandan/matlab/`.
2. Run `startup` (adds `src/` to the path).
3. Either `cd scripts` and run `run_segment4_heartrate_batch`, or add
   `matlab/scripts` to the path first (`addpath('scripts')`) and run it
   from `matlab/`.

It prints progress per subject as it goes — the frame rate and frame
count read from your Segment 3 output, the three HR estimates
(`HR_chrom`, `HR_pos`, `HR_green`), and the ground-truth HR if one was
found. If a subject's `_filtered_traces.mat` or `_rgb_traces.mat` is
missing, it says so and continues to the next subject rather than
stopping the whole batch — check the summary printed at the very end for
anything that failed.

**About the ground-truth column.** `io/loadGroundTruth.m` is a later
segment's stub and is intentionally untouched by Segment 4. This batch
script tries to call it for each subject (using `gtdump.xmp` for
DATASET_1 subjects or `ground_truth.txt` for DATASET_2 subjects, if
found under `data/raw/UBFC-rPPG/`), but until someone implements that
function, every subject's `HR_groundtruth` will read `NaN` — this is
expected, not a bug in this segment. Once `loadGroundTruth.m` is
implemented, re-running this script will start filling in real ground
truth automatically, no changes needed here.

## 4. Where your output lands (and how we merge it later)

For every subject in your list, this produces:

- `data/processed/<subjectID>_hr_estimates.mat` — contains `HR_chrom`,
  `HR_pos`, `HR_green`, `HR_groundtruth`, `subjectID`, `fs`. Named after
  the subject's own ID, same collision-free pattern as Segment 3.
- `results/figures/<subjectID>_heartrate_sanity.png` — three stacked FFT
  spectra (CHROM, POS, green-only), each restricted to 0-5 Hz with the
  valid 0.7-4 Hz band shaded and the detected peak marked. **Look at this
  before trusting a subject's numbers** — you want to see one clean,
  obvious peak inside the shaded band for CHROM and POS. If instead you
  see scattered, ambiguous energy with no clear winner (this is somewhat
  expected for the green-only subplot — that's the whole point of this
  segment — but is a red flag if it happens for CHROM or POS too), flag
  that subject before its numbers move on to Segment 5/6.
- One appended row in the **shared** `results/metrics/segment4_hr_summary.csv`
  — see below.

## 5. How the shared CSV works — read this before running on a shared folder

`results/metrics/segment4_hr_summary.csv` is a single file all four team
members write to. The script is written so this is safe:

- **It checks whether the file already has a header before writing one.**
  If the CSV already exists (because you or a teammate already ran this
  script at least once), it will NOT write a second header row — it just
  appends your subjects' rows underneath whatever's already there.
- **It appends one row per subject as that subject finishes processing**,
  not all at once at the end. It never reads the whole file into memory
  and rewrites it, so it can't accidentally overwrite rows a teammate
  already wrote.
- **Columns**: `subjectID, HR_chrom, HR_pos, HR_green, HR_groundtruth,
  abs_error_chrom, abs_error_pos, abs_error_green` — the `abs_error_*`
  columns are `NaN` for any subject without ground truth (which, per the
  note above, is currently *every* subject until `loadGroundTruth.m` is
  implemented).
- **What this does NOT protect against**: if you and a teammate both run
  the script on the exact same subject ID, you'll get two rows for that
  subject (harmless duplication, not data loss — just dedupe by
  eyeballing `subjectID` before using the CSV for anything final). And if
  the folder is synced live (e.g. a cloud-synced drive) and two people
  run the script at literally the same moment, there's a small window
  where both could check "does the header exist yet" at once — in
  practice, just don't both run it in the very same minute and this isn't
  an issue.

Once everyone's done, the shared CSV already has everyone's rows in it —
there's no separate merge step needed, unlike Segment 3's per-team-member
`.mat`/`.png` files (which still need manual copying into one shared
folder, since those aren't append-safe the way a CSV is).

## 6. Sanity-checked on this project's own data

This segment was run end-to-end on `5-gt`, `6-gt`, `7-gt` (the three
DATASET_1 subjects with both Segment 2 and Segment 3 output available).
See the Guideline PDF's "Verification" section for the actual numbers —
CHROM/POS landed within 1-3 bpm of ground truth on all three, while
green-only was off by nearly 17 bpm on one subject, visibly confirmed by
that subject's scattered sanity-PNG spectrum.
