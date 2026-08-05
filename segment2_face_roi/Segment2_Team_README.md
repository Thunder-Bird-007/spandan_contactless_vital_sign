# Segment 2 (Face Detection + ROI Extraction) — Team Instructions

This covers only Segment 2 of the pipeline: turning each subject's raw
video into raw `R(t), G(t), B(t)` traces plus the true sampling rate
`fs`. It does **not** cover filtering, CHROM/POS, FFT heart rate, or
SpO2 — those are later segments and are still stubs.

The actual code lives in the main scaffold, not in this folder:

- [`matlab/src/io/loadUBFCVideo.m`](../matlab/src/io/loadUBFCVideo.m)
- [`matlab/src/roi/extractROISignals.m`](../matlab/src/roi/extractROISignals.m)
- [`matlab/scripts/run_segment2_roi_batch.m`](../matlab/scripts/run_segment2_roi_batch.m)

This `segment2_face_roi/` folder is docs only:

- `Segment2_Face_ROI_Guideline.pdf` — theory background (why forehead
  skin, Viola-Jones intuition, the choir-effect averaging analogy, why
  `fs` must be read from the file, common pitfalls).
- `Segment2_LineByLine_Explanation.md` — a plain-language walkthrough of
  every block of the two implementation files, including the reasoning
  behind each design choice.
- This README.

## 1. Where to put your subject videos

Each of the 4 team members is processing a different 5-subject subset of
the shared 42-subject **DATASET_2** pool. Put your assigned subjects
here, one folder per subject, matching the existing convention:

```
data/raw/UBFC-rPPG/DATASET_2/subject9/vid.avi
data/raw/UBFC-rPPG/DATASET_2/subject9/ground_truth.txt
data/raw/UBFC-rPPG/DATASET_2/subject10/vid.avi
data/raw/UBFC-rPPG/DATASET_2/subject10/ground_truth.txt
...
```

`data/raw/UBFC-rPPG/DATASET_2/` is the path relative to the `spandan/`
project root — i.e. it's a sibling of `matlab/`, not inside it. See
`docs/DATA_FORMAT.md` for the full breakdown of what's in the dataset and
`README.md` for the overall folder layout. `data/raw/` is git-ignored, so
your videos won't get committed or pushed — everyone keeps their own
copy locally.

If any of your subjects only have DATASET_1-style ground truth
(`gtdump.xmp` instead of `ground_truth.txt`), put those under
`data/raw/UBFC-rPPG/DATASET_1/<subjectID>/` instead. The batch script
below works with either — it doesn't assume a fixed video filename, it
just looks for the one `.avi` file in your subject's folder, so it
doesn't matter whether your video is called `vid.avi`, `vid-001.avi`, or
something else.

## 2. Editing the subject list

Open `matlab/scripts/run_segment2_roi_batch.m`. Right at the top there
are two variables to edit — nothing else in the file needs to change:

```matlab
datasetName = 'DATASET_1';
subjectList = {'5-gt', '6-gt', '7-gt'};
```

Change `datasetName` to `'DATASET_2'` and `subjectList` to your own
assigned subject IDs, e.g.:

```matlab
datasetName = 'DATASET_2';
subjectList = {'subject9', 'subject10', 'subject11', 'subject12', 'subject13'};
```

Each ID in `subjectList` must match one of your folder names under
`data/raw/UBFC-rPPG/<datasetName>/` exactly.

## 3. Running it

1. Open MATLAB, `cd` into `spandan/matlab/`.
2. Run `startup` (adds `src/` to the path).
3. Either `cd scripts` and run `run_segment2_roi_batch`, or add
   `matlab/scripts` to the path first (`addpath('scripts')`) and run it
   from `matlab/`.

It prints progress per subject as it goes — how many frames, the actual
frame rate it read from the file, how many frames needed a fallback
bounding box, and where each output file was saved. If one of your
subjects errors out (corrupt file, wrong folder name, etc.) it will say
so and continue to the next subject rather than stopping the whole
batch — check the summary printed at the very end for anything that
failed.

## 4. Where your output lands (and how we merge it later)

For every subject in your list, two files are produced, both named after
that subject's own ID so there are no collisions when we combine
everyone's results into one shared folder:

- `data/processed/<subjectID>_rgb_traces.mat` — contains `R`, `G`, `B`
  (the raw per-frame color traces), `fs` (the true frame rate read from
  that subject's video), `subjectID`, and `numDroppedFrames`.
- `results/figures/<subjectID>_roi_sanity.png` — one frame from that
  subject's video with the detected face box (yellow) and the final ROI
  box (green) drawn on it. **Look at this before trusting the `.mat`
  output for that subject** — it's the whole point of this step. If the
  green box is sitting on hair, background, or an eye instead of
  forehead skin, something's wrong (wrong subject folder, an unusual
  video, etc.) and it's worth flagging before that subject's data feeds
  into filtering/CHROM/POS later.

Once everyone's done, we can just copy all `*_rgb_traces.mat` files into
one shared `data/processed/` folder and all `*_roi_sanity.png` files into
one shared `results/figures/` folder — since every filename is tagged
with its own subject ID, nobody's files will overwrite anyone else's.

## 5. A note on subject 27

Per the official UBFC-rPPG readme: **subject 21 and subject 27's facial
images must not be included in any publication, presentation, or
report.** If subject 27 ends up in your subset, it's fine to process it
for the `.mat` traces, but don't include its sanity PNG (or any other
frame from it) in slides, the report, or anywhere else the face would be
shown.
