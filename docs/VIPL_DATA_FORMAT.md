# VIPL-HR Dataset — Data Format Notes

This document records exactly what was found by inspecting the downloaded
VIPL-HR-V1 files at `H:\EEE 312 project\Contactless Vital Sign\VIPL-HR-V1\`
on 2026-08-08, in the same spirit as `DATA_FORMAT.md`'s own history in this
project: nothing here is taken from `ReadMe.pdf` alone. Every claim is
cross-checked against real extracted files — actual `VideoReader` output,
actual CSV content, actual byte-for-byte `time.txt` timestamps — because a
prior brief's paraphrase of a dataset readme (UBFC DATASET_2's SpO2 claim)
turned out to be wrong, which is exactly why this project insists on reading
real files directly rather than trusting a description. Where VIPL-HR's own
`ReadMe.pdf` turned out to disagree with what the files actually contain,
that is flagged loudly below, the same way the UBFC issue was flagged.

## 0. What is actually on disk right now

The VIPL-HR-V1 download is **not** inside `spandan/` at all — it landed as a
sibling top-level folder, `H:\EEE 312 project\Contactless Vital
Sign\VIPL-HR-V1\`, separate from the `spandan/` project root and from the
`UBFC dataset\` download. The scaffold's reserved
`spandan/matlab/data/raw/VIPL-HR/` folder does not exist (the project's
`data/` lives at `spandan/data/`, not nested under `spandan/matlab/` — see
`spandan-repo-layout` project convention); the correct, actually-used path
is `spandan/data/raw/VIPL-HR/`.

```
VIPL-HR-V1/
  Additional_data.txt   - 27 lines, extra "second take" folders (Section 6)
  Missing_data.txt      - 107 lines, (subject/scenario/source) combos that
                           don't exist despite the naming convention
                           predicting them (Section 6)
  NIR.txt                - 497 lines, the subset of NIR (source4) videos
                           with a detectable face, used in the original
                           paper's experiments (not used by this RGB-only
                           integration)
  ReadMe.pdf             - the official dataset readme (4 pages)
  fold/                  - fold1.mat ... fold5.mat, the paper's own
                           subject-exclusive 5-fold cross-validation splits
  data/                  - 21 zip archives, p1-5.zip, p6-10.zip, ...,
                           p101-107.zip, covering all 107 subjects,
                           ~48.6 GB compressed total (confirmed via
                           per-file size listing, not estimated)
```

**None of the 21 zip archives have been extracted.** The machine this
integration was built on has only ~55.7 GB free on the `H:` drive (confirmed
via `Get-PSDrive`), and the full archive set is ~48.6 GB compressed with an
unknown (likely larger) uncompressed footprint — extracting everything would
risk running the drive out of space. Per this segment's mandatory
small-scale-validation-first rule, only **6 individual videos** (3 subjects)
were extracted, using targeted per-entry extraction via .NET's
`System.IO.Compression.ZipFile` (list + extract only the needed entries),
**not** a full-archive `Expand-Archive`/unzip:

```
spandan/data/raw/VIPL-HR/
  p1/v1/source1/  (gt_HR.csv, gt_SpO2.csv, time.txt, video.avi, wave.csv)
  p1/v1/source2/  (gt_HR.csv, gt_SpO2.csv,           video.avi, wave.csv)
  p1/v1/source3/  (gt_HR.csv, gt_SpO2.csv, time.txt, video.avi, wave.csv)
  p1/v1/source4/  (gt_HR.csv, gt_SpO2.csv, time.txt, video.avi, wave.csv)
  p2/v1/source1/  (gt_HR.csv, gt_SpO2.csv, time.txt, video.avi, wave.csv)
  p3/v1/source1/  (gt_HR.csv, gt_SpO2.csv, time.txt, video.avi, wave.csv)
```

This means `loadVIPLVideo.m`/`loadVIPLGroundTruth.m` are validated against
real files, but **the full 107-subject pool is still zipped on disk** — see
`vipl_integration/VIPL_Team_README.md` for how each team member should
extract only their own assigned subject subset the same targeted way,
instead of unzipping entire multi-GB archives.

## 1. Subject/scenario/source addressing scheme

VIPL-HR has no single addressable "subject video" the way UBFC does. Listing
a zip archive's entries directly (`p1-5.zip`, 881 entries, confirmed without
extracting) shows the real structure:

```
p1/
  v1/
    source1/  gt_HR.csv  gt_SpO2.csv  time.txt  video.avi  wave.csv
    source2/  gt_HR.csv  gt_SpO2.csv             video.avi  wave.csv
    source3/  gt_HR.csv  gt_SpO2.csv  time.txt  video.avi  wave.csv
    source4/  gt_HR.csv  gt_SpO2.csv  time.txt  video.avi  wave.csv
  v2/  ... (same 4 source folders)
  ...
  v7/  source2, source3, source4 only (source1 missing for p1/v7 — matches
       Missing_data.txt's own listed entry "p1/v7/source1")
  v8/  source2 only (phone-only scenario, confirmed — see Section 2)
  v9/  source2 only
```

Every `(subject, scenario, source)` triple is its own independent video with
its own ground truth files (`gt_HR.csv`, `gt_SpO2.csv`, `wave.csv`, and
`time.txt` where applicable) — **not** shared across scenarios or sources in
general. This project's brief originally suggested a 2-part
`(subjectID, sourceID)` addressable unit; that is not sufficient for
VIPL-HR, so `loadVIPLVideo.m`/`loadVIPLGroundTruth.m` both take three
explicit numeric identifiers: `subjectNum`, `scenarioNum` (1-9, i.e. v1-v9),
`sourceNum` (1-3, RGB only — see Section 3). Not every subject has every
scenario/source combination — `Missing_data.txt` lists real, confirmed gaps
(107 lines), and callers must handle a missing-file error from the loader
rather than assume every triple exists.

## 2. Scenario meanings (v1-v9), from `ReadMe.pdf`

| Scenario | Meaning |
|---|---|
| v1 | Stable: seated naturally, 1 m from camera, ceiling lamp on |
| v2 | Motion: large head movements, otherwise same as v1 |
| v3 | Talking: reads a prepared text, otherwise same as v1 |
| v4 | Dark: ceiling lamp off |
| v5 | Bright: filament lamp on |
| v6 | Long distance: seated 1.5 m from camera |
| v7 | Exercise: 2 min rope skipping immediately before recording |
| v8 | Phone stable: held phone, kept still, phone front-camera only |
| v9 | Phone motion: held phone, large head movements, phone front-camera only |

v8/v9 use **only source2** (the phone's own front camera) — confirmed by the
zip listing (`p1/v8/source2/` and `p1/v9/source2/` exist with no sibling
source1/3/4 folders for those two scenarios), consistent with the ReadMe's
"Only the front-camera of the phone is used for recording" note for both.

## 3. Recording sources (source1-source4), from `ReadMe.pdf`

| Source | Device | ReadMe's claimed fps | ReadMe's claimed resolution | Has `time.txt`? |
|---|---|---|---|---|
| source1 | Logitech C310 webcam | ~25 fps | 960x720 | Yes |
| source2 | HUAWEI P9 phone front camera | 30 fps | 1920x1080 | **No** |
| source3 | RealSense F200 color camera | ~30 fps | 1920x1080 | Yes |
| source4 | RealSense F200 **NIR** camera | ~30 fps | 640x480 | Yes |

**source4 is near-infrared, not RGB.** Per this segment's brief, NIR loading
is explicitly out of scope — `loadVIPLVideo.m` rejects `sourceNum == 4` with
a clear error rather than silently loading it. Of VIPL-HR's 752 total NIR
videos, only 497 (listed in `NIR.txt`) were even usable in the original
paper's own experiments ("face sizes in the NIR videos are small for the
face detector") — noted here for completeness only, not used.

**source2 has no `time.txt` in every folder checked** (confirmed for
`p1/v1/source2`, `p1/v7/source2`, `p1/v8/source2`, `p1/v9/source2` — zero
exceptions in the 881-entry listing for `p1-5.zip`). This matches the
ReadMe's own text, which explicitly lists `time.txt` as existing "For each
video recorded using the web-camera and RealSense cameras (source1, source3
and source4)" and says nothing of the sort for source2. See Section 4 for
why this matters.

**All four sources retain "only the face area"** per the ReadMe — i.e. every
video ships already cropped to that recording's own detected face bounding
box, not a full camera scene the way UBFC's 640x480 videos are. This was
independently confirmed by measuring actual video dimensions (Section 4):
they are far smaller than, and a different aspect ratio from, the ReadMe's
claimed native camera resolutions, and they vary from video to video (crop
tightness differs by how close/far the subject's face happened to be),
whereas the ReadMe's numbers are fixed per source. **This is a structural
difference from UBFC that Segment 2's `extractROISignals.m` was not
originally designed around** — see Section 7 for the validation result.

## 4. Real measured video properties — confirmed discrepancy from `ReadMe.pdf`

Measured directly via `VideoReader` in MATLAB on all 6 extracted videos:

| Video | Container FrameRate | Container NumFrames | Container Duration | Measured resolution | ReadMe's claimed resolution |
|---|---|---|---|---|---|
| p1/v1/source1 | 25 | 1036 | 41.44 s | 442x446 | 960x720 |
| p1/v1/source2 | 25 | 1313 | 52.52 s | 584x664 | 1920x1080 |
| p1/v1/source3 | 25 | 1041 | 41.64 s | 438x488 | 1920x1080 |
| p1/v1/source4 | 25 | 1041 | 41.64 s | 138x174 | 640x480 |
| p2/v1/source1 | 25 | 668 | 26.72 s | 392x376 | 960x720 |
| p3/v1/source1 | 25 | 754 | 30.16 s | 422x404 | 960x720 |

**Finding 1 (loud flag, analogous to the UBFC DATASET_2 SpO2 overclaim):**
`VideoReader.FrameRate` reports **exactly 25 fps for every single video
tested, regardless of source** — even source3/source4, whose ReadMe entry
claims "~30 fps". This is not a coincidence: the ReadMe itself explains why,
in text easy to skim past — *"Please note that the videos are only used for
compression and the time steps for the frames are recorded in the
`time.txt`"* (stated for source1, source3, source4). In other words, VIPL-HR's
own authors are telling us the container's declared frame rate is a
re-encoding artifact, not real acquisition timing, and to use `time.txt`
instead. This project's existing house rule ("always read fps via
`VideoReader.FrameRate`, never hardcode") is **not sufficient on its own for
VIPL-HR** — it must be read, but then corrected using `time.txt` when one
exists. Reconstructing real fps from each video's own `time.txt`
(`(numTimestamps - 1) / ((lastTimestampMs - firstTimestampMs) / 1000)`):

| Video | time.txt frame count | time.txt-derived duration | time.txt-derived fps | vs. container's 25 fps |
|---|---|---|---|---|
| p1/v1/source1 | 1036 | 34.736 s | 29.82 fps | **+19.3% off** |
| p1/v1/source3 | 1041 | 34.716 s | 29.99 fps | **+20.0% off** |
| p1/v1/source4 | 1041 | 34.716 s | 29.99 fps | **+20.0% off** |
| p2/v1/source1 | 668 | 26.751 s | 24.97 fps | -0.1% (matches) |
| p3/v1/source1 | 754 | 30.208 s | 24.96 fps | -0.2% (matches) |

`source3`/`source4` share **identical** `time.txt` content within a given
`(subject, scenario)` (confirmed byte-for-byte for p1/v1) because both are
captured by the same physical RealSense F200 rig at the same time — their
~30 fps real rate, once corrected, matches the ReadMe's own "~30fps" claim
for those two sources. `source1`'s real rate does **not** reliably match its
own claimed ~25 fps: it was off by 19% for p1 but matched to within 0.2% for
p2 and p3. This is the same "do not assume a fixed fps across subjects"
lesson already learned from UBFC (`DATA_FORMAT.md` Section 3), now shown to
apply at the level of individual recordings, not just across sources.

**Consequence for `loadVIPLVideo.m`:** when a `time.txt` exists next to
`video.avi` (source1, source3, source4), `frameRate` is computed from
`time.txt`'s own timestamps, not from `VideoReader.FrameRate`, with a
`disp()` warning printed whenever the two disagree by more than 5%. Trusting
`VideoReader.FrameRate` naively here would silently introduce an HR
estimation error of up to ~20% for affected recordings (a wrong fps shifts
every FFT bin's Hz-to-bpm mapping proportionally).

**Finding 2 (documented limitation, not fixable from this data):**
`source2` has no `time.txt` at all (Section 3), so there is no independent
way to verify its declared frame rate against real acquisition timing.
`loadVIPLVideo.m` falls back to `VideoReader.FrameRate` for source2 with
this limitation stated explicitly in its own header comment — unlike
source1/3/4, a bad rate here cannot be caught.

## 5. Ground truth file format — confirmed from real file content

Each `(subject, scenario, source)` folder ships **three separate files**,
each at its own native sampling rate — a different shape from UBFC
DATASET_1's single 4-column `gtdump.xmp` where every column shares one row
per oximeter sample.

### 5a. `gt_HR.csv` / `gt_SpO2.csv` — one value per elapsed second

Confirmed from `p1/v1/source1/gt_HR.csv` and `gt_SpO2.csv`:

- Plain CSV, comma-irrelevant (single column), **one header row** (`HR` or
  `SpO2` literally), then one integer value per row.
- **No timestamp column.** The ReadMe states these are "recorded every
  second," so row index directly implies elapsed whole seconds (row 1 =
  second 0, row 2 = second 1, ...).
- `gt_HR.csv` and `gt_SpO2.csv` always had the **same row count** in every
  file checked (e.g. both 36 data rows for p1/v1/source1).
- Real, physiologically plausible values confirmed (p1/v1/source1: HR
  62-67 bpm, SpO2 94-97%) — SpO2 **is present** for every video checked,
  unlike UBFC DATASET_2's confirmed total absence of an SpO2 column. This
  matches the ReadMe's claim; still verified directly rather than assumed,
  per this project's standing discipline.

### 5b. `wave.csv` — BVP waveform, ~60 Hz

Confirmed from `p1/v1/source1/wave.csv` (2084 data rows over the same clip
whose `gt_HR.csv` has 36 rows): one header row (`Wave`), then one raw BVP
amplitude sample roughly every 16-17 ms (~60 Hz — the same CONTEC CMS60C
sensor family already documented for UBFC DATASET_1's oximeter in
`DATA_FORMAT.md`). **Not** the same length or rate as `gt_HR.csv`/
`gt_SpO2.csv`, and not resampled to match them anywhere in the shipped data.

### 5c. Shared vs. independent recording sessions within one scenario

Confirmed for p1/v1: `source1`, `source3`, and `source4`'s `gt_HR.csv`/
`gt_SpO2.csv`/`wave.csv` all have **identical** row counts (36 / 36 / 2084)
because those three physical devices record the same session simultaneously.
`source2` (the phone) has **different, independent** row counts (45 / 45 /
2621) — it is captured as its own separate take, not the same physiological
recording re-packaged three ways. Any code that assumes one shared
ground-truth timeline per `(subject, scenario)` regardless of source would
be wrong for source2.

### 5d. Design decision: what `loadVIPLGroundTruth.m` returns

To keep `loadGroundTruth.m`'s existing UBFC consumers (e.g.
`scripts/run_segment5_dataset1_calibration_batch.m`'s
`gt.timestamp <= videoDurationSec` masking pattern) working unmodified,
`gt.timestamp`, `gt.hr`, and `gt.spo2` are returned as three parallel
vectors at `gt_HR.csv`/`gt_SpO2.csv`'s native 1-second granularity, with
`gt.timestamp` reconstructed as elapsed whole seconds (`0, 1, 2, ...`).
`gt.ppg` is returned separately, at `wave.csv`'s own native ~60 Hz rate, and
is deliberately **not** forced to the same length as `gt.timestamp` — no
existing Segment 4/5 batch script indexes `gt.ppg` against `gt.timestamp`
elementwise today, so no artificial resampling was introduced just to make
the four fields superficially uniform. See
`vipl_integration/VIPL_Integration_LineByLine_Explanation.md` Part 2 for the
full reasoning.

## 6. Missing and additional data

- **`Missing_data.txt`** (107 lines): real `(subject/scenario/source)`
  combinations that do not exist on disk despite the naming convention
  predicting them, e.g. `p1/v7/source1` — confirmed absent from the zip
  listing. Any loader/batch script must treat a missing file as an expected,
  loggable condition, not a bug.
- **`Additional_data.txt`** (27 lines): extra second-take folders named
  `vX-2` (e.g. `p16/v1-2/source1`), a second recording of the same nominal
  scenario. `loadVIPLVideo.m`'s `scenarioNum` parameter builds a plain `vN`
  folder name and has **no way to address these `vX-2` folders** — flagged
  here as a known gap, not silently ignored. None of the 3 validation
  subjects (p1, p2, p3) appear in this list, so it did not affect the
  small-scale validation in Section 7.
- **`NIR.txt`** (497 lines): out of scope, source4/NIR is not loaded by this
  integration (Section 3).

## 7. Segment 2-5 pipeline validation result on real VIPL-HR data

See `vipl_integration/VIPL_Integration_LineByLine_Explanation.md` and the
final report in the integration handoff for the actual HR/SpO2 numbers
produced by running the existing, unmodified `extractROISignals.m` ->
`bandpassClean.m` -> `chromCombine.m`/`posCombine.m` -> `fftHeartRate.m` ->
`ratioOfRatios.m` chain against `p1/v1/source1`, `p2/v1/source1`, and
`p3/v1/source1` via the new loaders. In short: `vision.CascadeObjectDetector()`
was tested directly against VIPL-HR's pre-cropped face frames (Section 3) to
confirm it still finds a face on an already-tight crop before any batch run
was attempted, per this segment's mandatory stop-if-the-detector-fails rule.
