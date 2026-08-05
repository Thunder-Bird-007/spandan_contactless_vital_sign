# Segment 3 (Detrending + Bandpass Filtering) — Team Instructions

This covers only Segment 3 of the pipeline: taking each subject's raw
`R(t), G(t), B(t)` traces from Segment 2 and cleaning them up into
detrended, bandpass-filtered traces ready for CHROM/POS combination. It
does **not** cover CHROM/POS, FFT heart rate, or SpO2 — those are later
segments and are still stubs.

The actual code lives in the main scaffold, not in this folder:

- [`matlab/src/filtering/detrendSignal.m`](../matlab/src/filtering/detrendSignal.m)
- [`matlab/src/filtering/bandpassClean.m`](../matlab/src/filtering/bandpassClean.m)
- [`matlab/scripts/run_segment3_filtering_batch.m`](../matlab/scripts/run_segment3_filtering_batch.m)

This `segment3_filtering/` folder is docs only:

- `Segment3_Filtering_Guideline.pdf` — theory background (why raw R/G/B
  has drift and out-of-band noise, polynomial detrending intuition,
  Butterworth bandpass intuition, `filtfilt` vs `filter`, common
  pitfalls).
- `Segment3_LineByLine_Explanation.md` — a plain-language walkthrough of
  every block of the two implementation files, including the reasoning
  behind every parameter choice.
- This README.

## 1. Before you start: confirm your Segment 2 output exists

This segment reads, for each subject, a file already produced by
Segment 2:

```
data/processed/<subjectID>_rgb_traces.mat
```

containing `R`, `G`, `B`, `fs`, `subjectID`, `numDroppedFrames`. If you
haven't run `run_segment2_roi_batch.m` on your assigned subjects yet (or
don't see their `*_rgb_traces.mat` files in `data/processed/`), do that
first — Segment 3 has nothing to work on without it. See
`segment2_face_roi/Segment2_Team_README.md` if you need a refresher on
that step.

## 2. Editing the subject list

Open `matlab/scripts/run_segment3_filtering_batch.m`. Right at the top
there is one variable to edit:

```matlab
subjectList = {'5-gt', '6-gt', '7-gt'};
```

Change it to your own subject IDs — the same ones you already used for
Segment 2, since this script reads their `_rgb_traces.mat` files by that
exact ID:

```matlab
subjectList = {'subject9', 'subject10', 'subject11', 'subject12', 'subject13'};
```

## 3. Running it

1. Open MATLAB, `cd` into `spandan/matlab/`.
2. Run `startup` (adds `src/` to the path).
3. Either `cd scripts` and run `run_segment3_filtering_batch`, or add
   `matlab/scripts` to the path first (`addpath('scripts')`) and run it
   from `matlab/`.

It prints progress per subject as it goes — the frame rate and frame
count it read from your Segment 2 output, and the detrend/filter orders
used. If one of your subjects is missing its `_rgb_traces.mat` file (or
it fails to load), it will say so and continue to the next subject
rather than stopping the whole batch — check the summary printed at the
very end for anything that failed.

## 4. Where your output lands (and how we merge it later)

For every subject in your list, two files are produced, both named after
that subject's own ID so there are no collisions when we combine
everyone's results into one shared folder:

- `data/processed/<subjectID>_filtered_traces.mat` — contains
  `R_filtered`, `G_filtered`, `B_filtered` (the detrended and
  bandpass-filtered traces), `fs`, `subjectID`, `detrendOrder`, and
  `filterOrder` (the exact parameters used, so anyone can audit the
  choices later without re-reading the code).
- `results/figures/<subjectID>_filtering_sanity.png` — three stacked
  plots of the green channel for that subject: raw, after detrending
  only, and after detrending + bandpass filtering, all on the same time
  axis. **Look at this before trusting the `.mat` output for that
  subject** — the slow drift should visibly be gone by the second plot,
  and the third plot should look like a repeating, roughly periodic
  wave, not a flat line and not still-noisy random wiggling. If it
  doesn't, something's worth flagging before that subject's data moves
  on to CHROM/POS combination.

Once everyone's done, copy all `*_filtered_traces.mat` files into one
shared `data/processed/` folder and all `*_filtering_sanity.png` files
into one shared `results/figures/` folder — since every filename is
tagged with its own subject ID, nobody's files will overwrite anyone
else's.
