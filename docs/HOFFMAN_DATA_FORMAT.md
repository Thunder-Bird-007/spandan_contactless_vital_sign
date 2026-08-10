# Hoffman Finger-Camera Oximetry Dataset — Data Format Notes

This document records exactly what was found by cloning and directly opening
the files in `https://github.com/ubicomplab/oximetry-phone-cam-data`
(commit dated 2025-02-13) on 2026-08-05, for use by
`matlab/scripts/run_segment5_hoffman_sanity_check.m`. Nothing here is taken
from the repo's `README.md` alone — every claim below was cross-checked
against the actual CSV files and the authors' own `examples/*.py`
preprocessing scripts, in the same spirit as `DATA_FORMAT.md`'s own history
in this project (a prior brief's paraphrase of a dataset readme turned out
to be wrong in places, which is why this project now insists on reading
real files directly).

## 0. What this dataset actually is

This is **not** a facial-video dataset. Subjects had one finger from each
hand placed directly on a smartphone camera lens with the camera flash on,
so the camera captured light transmitted/reflected through the fingertip
(contact reflectance photoplethysmography), not a face at a distance. It is
used in this project **only** as a code-correctness sanity check for
`ratioOfRatios.m`/`calibrateSpO2.m` against real data with a wide SpO2
range — it says nothing about facial-video SpO2 accuracy. See
`segment5_spo2/Segment5_LineByLine_Explanation.md` for why that distinction
matters.

Six subjects, numbered `100001`-`100006` (the repo's own `README.md` calls
them "10001-10006", but every actual file/folder name uses the 6-digit form
`100001`-`100006` — confirmed by directory listing, not the README text).

## 1. Repository layout (confirmed by cloning and listing)

```
data/
  ppg-csv/
    Left/100001.csv ... 100006.csv   - camera RGB traces, left hand
    Right/100001.csv ... 100006.csv  - camera RGB traces, right hand
  gt/
    100001.csv ... 100006.csv        - ground truth, one file per subject
    metadata.csv                     - column descriptions for gt/*.csv
  info/
    Left/100001-<timestamp>.info     - per-subject JSON (age, sex,
                                        ethnicity, skin tone)
    Right/...
  preprocessed/
    all_uw_data.h5                   - authors' own pre-built HDF5 tensor
                                        (not used here — we read the CSVs
                                        directly per the task brief)
  raw-videos/
    README-videos.md                 - raw .mp4 videos are NOT in the repo,
                                        only a Google Drive link; not needed
                                        for this sanity check since ppg-csv/
                                        already has the per-frame RGB means
examples/
  preprocess_data_spo2.py, process_data_spo2.py, header_data_spo2.py,
  visualization.ipynb                - the authors' own reference loaders,
                                        read directly to confirm the
                                        alignment assumption in Section 3
```

## 2. `data/ppg-csv/{Left,Right}/<subjectID>.csv` — camera RGB traces

Confirmed by opening the actual file content (`100001.csv`):

- Plain CSV, **comma-delimited, one header row**: `R,G,B`.
- One row per **camera frame**, 30 Hz (stated in the repo's `README.md`
  and consistent with row counts below).
- Values are floating-point averages of that frame's R/G/B pixel
  intensities — this is the exact same quantity as this project's own
  `roi/extractROISignals.m` output (a raw, unfiltered per-frame channel
  mean), just averaged over the whole fingertip contact patch instead of a
  forehead ROI.
- **No timestamp column** — row position is the only index.
- Left and right hand files for the same subject do **not** have identical
  row counts (subject `100001`: Left has 32728 data rows, Right has
  32714) — minor frame-count drift between the two camera streams. This
  sanity check uses the `Left` file only, per subject, to keep things
  simple and self-contained (documented as a simplification, not a bug).

## 3. `data/gt/<subjectID>.csv` — ground truth, 1 Hz, five pulse oximeters

Confirmed by opening the actual file content (`100001.csv`, 1092 lines):

- Plain CSV, comma-delimited, **one header row**, one row per second
  (`Time` column is a wall-clock `HH:MM:SS` string, not usable directly as
  a duration/offset).
- Relevant columns (full list in `data/gt/metadata.csv`, also mirrored in
  the repo's own `README.md` table — this part of the README was verified
  correct against the actual header row): `SpO2 1` through `SpO2 5`, one
  per physical pulse-oximeter device. Per `metadata.csv`, the five devices
  are: `SpO2 1` (Masimo 3900P TT+), `SpO2 2` (Nellcor N-600X), `SpO2 3`
  ("Unfilled signal from pulse ox 3" — literally documented as unfilled by
  the dataset authors themselves), `SpO2 4` (a second Nellcor N-600X),
  `SpO2 5` (Masimo Radical 7 Rainbow II).
- **Confirmed by directly scanning every value in every subject's file**:
  `SpO2 3` is exactly `0` for every row, in every one of the 6 subjects —
  not occasionally missing, always zero. This column must be excluded
  entirely, not just treated as occasionally-noisy. This sanity check uses
  `SpO2 2` (Nellcor N-600X) as the reference device — a real clinical
  pulse oximeter reading, not a placeholder/zero column.
- **Confirmed wide dynamic range** (min/max of `SpO2 2` scanned per
  subject, zero/blank rows excluded):

  | Subject | SpO2 2 min | SpO2 2 max |
  |---|---|---|
  | 100001 | 70 | 100 |
  | 100002 | 72 | 100 |
  | 100003 | 67 | 100 |
  | 100004 | 77 | 100 |
  | 100005 | 68 | 100 |
  | 100006 | 66 | 100 |

  This is the wide range (down to the 60s/70s%) that DATASET_1's narrow
  95-99% range cannot offer — the whole reason this dataset is used for
  the sanity check.
- **The last data row of every subject's file is a sentinel, not a real
  sample**: `100001.csv`'s final line is literally
  `Collection Halted,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,`
  — an end-of-recording marker with an empty value in every column. The
  dataset authors' own `examples/preprocess_data_spo2.py` explicitly slices
  `datContent[1:-1]` (drop the header row AND the last row) for exactly
  this reason. Any loader that doesn't drop this row will either error on
  the non-numeric `Time` value or silently ingest a garbage all-zero row.

## 4. Camera-frame-to-GT-second alignment (confirmed from the authors' own code, not assumed)

`data/ppg-csv/*.csv` has no timestamp column, only frame order. `data/gt/
*.csv` has one row per second. The repo's `README.md` states plainly:
*"Recording was started and stopped on the camera and the pulse oximeters
at the same time."* This project's own house rule is not to trust a
README description alone — so this was cross-checked against the authors'
own `examples/preprocess_data_spo2.py`, which implements exactly this
assumption in code (`build_data_and_groundtruth()`): it treats camera frame
index `i` as belonging to GT second `floor(i / 30)`, i.e. **the first 30
camera rows correspond to GT row 1, the next 30 to GT row 2, and so on**,
with no timestamp reconciliation beyond that fixed 30-frames-per-second
grouping and a shared t=0 start. `run_segment5_hoffman_sanity_check.m`
uses this exact same index-based grouping (not a naive whole-file 1:1
mapping, and not a clock-based alignment — there is no shared clock to
align to in the CSVs as shipped).

## 5. `data/info/{Left,Right}/<subjectID>-<timestamp>.info` — subject metadata

Confirmed by opening `100001-1487003054311.info`: a single-line JSON object,
e.g. `{"subject_info":{"packet":"subject_info","ethnicity":"White","age":
"31","sex":"Male","sphb":"","spo2":"","perfusion":"","skintone":"#FAF3EB"}}`,
followed by a literal `null` on a second line. Not used by
`run_segment5_hoffman_sanity_check.m` — noted here for completeness only.

## 6. What this sanity-check script does and does not need

Not used, and not needed, for this segment's sanity check:
- `data/raw-videos/` — raw `.mp4` files aren't even included in the repo
  (Google Drive link only); `data/ppg-csv/` already has the per-frame
  channel means this script needs.
- `data/preprocessed/all_uw_data.h5` — the authors' own pre-built tensor;
  this project reads the source CSVs directly instead, per the task brief
  ("computes AC/DC and R directly from that dataset's own raw signal
  format").
- `data/info/` — subject demographics, not needed for an AC/DC/ratio
  sanity check.
