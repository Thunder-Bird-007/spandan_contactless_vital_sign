# UBFC-rPPG Dataset — Data Format Notes

This document records exactly what was found by inspecting the downloaded
files at `H:\EEE 312 project\Contactless Vital Sign\UBFC dataset\` on
2026-07-26. Nothing here is guessed from general knowledge of the dataset —
every claim below was confirmed either by reading raw file contents, parsing
binary headers, or reading the official `readme.txt` bundled inside the
download itself. Where something is inferred rather than directly stated,
it is flagged as such.

## 0. What is actually on disk right now

The downloaded content is **messy and fragmented** — it is a Google-Drive
folder export split into many small zip parts, plus a few things someone
already extracted by hand. There are three overlapping sources:

1. **`ubfc-rppg-dataset.zip`** (top level) — a clean, complete, flat archive:
   `subjectN/ground_truth.txt` + `subjectN/vid.avi` for **42 subjects**
   (IDs: 1,3,4,5,8,9,10,11,12,13,14,15,16,17,18,20,22,23,24,25,26,27,30,31,
   32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49 — note the ID
   numbering is not contiguous; this is normal, it's how the dataset authors
   published it). This is **DATASET_2** and it is the complete, canonical
   42-subject set. **This is the recommended primary source.**

2. **~38 files named `UBFC_DATASET-<timestamp>-N.zip`** — fragments of a
   *different* Google Drive export that also contains a `DATASET_1/` folder.
   Each fragment zip holds only one or two files (e.g. just one subject's
   `vid.avi`, or just one subject's `ground_truth.txt`). Reconstructing the
   full set from these fragments gives:
   - `DATASET_2/`: only **38 of the 42 subjects** (missing subject22,
     subject24, subject37, subject45 relative to the complete zip above) —
     **redundant with and less complete than `ubfc-rppg-dataset.zip`,
     safe to ignore.**
   - `DATASET_1/`: 7 subject folders (`5-gt, 6-gt, 7-gt, 8-gt, 10-gt, 12-gt,
     after-exercise`), but `8-gt` only contains `vid.avi` (no ground truth)
     and `10-gt` only contains `gtdump.xmp` (no video). Only **5 subjects
     have both** video and ground truth: `5-gt, 6-gt, 7-gt, 12-gt,
     after-exercise`.
   - Also bundled: `readme.txt` (the official dataset readme — quoted
     below), `Agreement.xlsx`, and reference loader scripts
     `ubfcrppg_data_processor.py` / `.m`.

3. **Loose already-extracted folders** sitting next to the zips
   (`5-gt-...\5-gt\`, `6-gt-...\6-gt\`, `7-gt-...\7-gt\`,
   `12-gt-...\12-gt\`, `after-exercise-...\after-exercise\`,
   `DATASET_1\10-gt\`) — these are just unzipped copies of the DATASET_1
   fragments described in (2).

**DATASET_1 is important for this project**: unlike DATASET_2, it contains
**SpO2 ground truth** (see Section 2). But this download only has a partial
DATASET_1 (5 usable subjects, not the full DATASET_1 set), so it should be
treated as a small supplementary set for SpO2 calibration/validation, not
the main training corpus.

**Legal note from the official readme**, worth keeping in mind for any
report or presentation that shows face crops: *"DATASET_2: For subjects 21
and 27: Facial images must not be included in any publication, presentation,
or report."* (Subject 21 isn't even present in our download, but subject 27
is — don't show subject27's face in the report.)

## 1. Subject organization

**Folder-per-subject**, not flat-with-metadata-file. Confirmed from
`ubfc-rppg-dataset.zip`:

```
subject1/
  ground_truth.txt
  vid.avi
subject3/
  ground_truth.txt
  vid.avi
... (42 subjects total)
```

DATASET_1 fragments use a different naming pattern per folder
(`<id>-gt/gtdump.xmp` + a video file whose name is **inconsistent across
subjects**: `vid_5gt.avi`, `vid-001.avi`, `vid-002.avi`, `vid-004.avi`,
`vid-001 (1).avi`). Any DATASET_1 loader must not assume a fixed video
filename — it should just glob for the single `.avi` file in the subject
folder.

## 2. Ground truth file format (confirmed from official `readme.txt`)

The bundled `readme.txt` states directly:

> The ground truth extracted from the pulse oximeter is formatted as follows:
>
> **Dataset1**: Ground truth is stored in `gtdump.xmp` files:
> - Column 1: Timestep (ms)
> - Column 2: Heart rate (HR)
> - Column 3: SpO2
> - Column 4: PPG signal
>
> **Dataset2**: Ground truth is stored in `ground_truth.txt` files:
> - Line 1: PPG signal
> - Line 2: Heart rate (HR)
> - Line 3: Timestep (seconds, scientific notation)
>
> Please note that heart rate values provided by the sensor were not used
> for evaluating our heart rate estimation method. Instead, our evaluation
> compared heart rate estimations derived from the remote PPG signal with
> estimations calculated from the contact PPG signal.

### 2a. DATASET_1 — `gtdump.xmp`

Verified by reading actual file content (e.g.
`5-gt-...\5-gt\gtdump.xmp`, 5223 rows):

- Plain CSV, **comma-delimited, no header row**.
- 4 columns per row, one row per pulse-oximeter sample:
  `timestamp_ms, HR_bpm, SpO2_pct, PPG_raw`
- Example rows (subject 5):
  ```
  11,68,99,20
  27,68,99,20
  43,68,99,20
  ...
  ```
- Sample spacing is ~16 ms → **oximeter sampling rate ≈ 62 Hz**, independent
  of and asynchronous with the video frame rate. Column 1 (timestamp) must
  be used to align GT samples to video frames — do not assume a 1:1
  index correspondence between GT rows and video frames.
- Column 3 (SpO2) is confirmed present and is typically near-constant or
  slowly varying within a recording (observed values: 99, 96, 97 across the
  5 usable subjects) — physiologically plausible resting SpO2.
- Column 2 (HR) visibly tracks physiology: e.g. the `after-exercise` subject
  has HR values around 148 bpm (elevated, consistent with the folder name),
  while resting subjects sit in the 65–100 bpm range.
- Last timestamp in subject 5's file is 84001 ms; the paired video
  (`vid_5gt.avi`) has a reported duration of 1:24 (84 s) — timestamps and
  video duration are consistent.

### 2b. DATASET_2 — `ground_truth.txt`

Verified by reading actual file content (subject9, via
`np.loadtxt`-compatible parsing):

- Plain text, **whitespace-delimited** (multiple spaces), **3 lines**, no
  header.
- All 3 lines have equal length (subject9: 2016 values per line — one value
  per video frame).
- Line 1: PPG signal, floating point, scientific notation, e.g.
  `1.0053278e+00  3.7601301e-01  -2.0251413e-01 ...` (already looks
  roughly zero-mean, arbitrary units — not a physical PPG unit).
- Line 2: HR in bpm, e.g. `1.0700000e+02 1.0700000e+02 ... 1.0640000e+02`
  (near-constant within short spans, changes slowly).
- Line 3: Timestep in seconds, scientific notation, starting at
  `0.0000000e+00` and incrementing by roughly 0.03–0.034 s per sample —
  i.e. this line is **already resampled to one value per video frame**
  (~29–30 Hz), unlike DATASET_1 which keeps the oximeter's native ~62 Hz
  and needs explicit timestamp alignment.
- **No SpO2 column in DATASET_2.** This is an open question flagged by the
  project brief — confirmed: DATASET_2 ground truth has no SpO2 field at
  all. SpO2 calibration/validation must rely on the DATASET_1 subset (or
  the self-collected pulse-oximeter test set planned for later).

## 3. Video file format

Confirmed by parsing the AVI headers directly (both from an extracted
DATASET_1 file via Windows Shell metadata, and from a DATASET_2 file's
`strf`/`strh` RIFF chunks parsed byte-for-byte):

| Property | DATASET_1 (subject 5) | DATASET_2 (subject 41) |
|---|---|---|
| Container | AVI | AVI |
| Resolution | 640 × 480 | 640 × 480 |
| Bit depth | — | 24-bit RGB |
| Codec | uncompressed (raw DIB) | `DIB ` (uncompressed RGB) |
| Reported frame rate | ~28.67 fps | ~29.76 fps |
| Frame count | not read | 2037 frames |
| Duration | 1:24 (84 s) | ~68.4 s |

Both are **uncompressed RGB AVI**, 640×480, and frame rate is **not exactly
30 fps and appears to vary slightly per subject** — do not hardcode fps
anywhere; always read it from `VideoReader.FrameRate` in MATLAB (or derive
timing from the GT timestamps for DATASET_1). File sizes are large
(subject 41's video alone is ~1.9 GB uncompressed), which is why
`data/raw/` is git-ignored.

## 4. What to actually extract, and where

Given the mess in Section 0, the recommended action (not yet done — this
is documentation, not an extraction step) is:

1. Extract `ubfc-rppg-dataset.zip` → `spandan/data/raw/UBFC-rPPG/DATASET_2/`
   for the full 42-subject DATASET_2 set (video + PPG + HR, no SpO2).
2. Copy the 5 complete DATASET_1 folders (`5-gt, 6-gt, 7-gt, 12-gt,
   after-exercise`) → `spandan/data/raw/UBFC-rPPG/DATASET_1/` for the
   SpO2-bearing subset.
3. Leave the 38 fragment zips and the incomplete `8-gt`/`10-gt` folders
   alone — they add nothing not already covered by (1) and (2).

This will need tens of GB of free disk space; do it deliberately, not as
part of routine scaffolding.

## 5. Open questions for the project (not resolved by this document)

- SpO2 ground truth exists only for 5 DATASET_1 subjects in this download.
  Calibrating `spo2/calibrateSpO2.m` on 5 subjects with LOSO cross-validation
  is thin — worth requesting more DATASET_1 subjects or leaning more on the
  self-collected test set for SpO2 specifically.
- DATASET_1's PPG signal (column 4) and DATASET_2's PPG signal (line 1) are
  in different, unspecified arbitrary units — they should not be mixed
  without checking whether normalization is needed before any cross-dataset
  comparison.
