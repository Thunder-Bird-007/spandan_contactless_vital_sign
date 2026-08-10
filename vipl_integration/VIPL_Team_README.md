# VIPL-HR Integration — Team Instructions

This covers only the VIPL-HR I/O integration: two new loader functions
(`io/loadVIPLVideo.m`, `io/loadVIPLGroundTruth.m`) and one new batch script
(`scripts/run_vipl_integration_batch.m`) that feed VIPL-HR's real files
into the already-tested, unmodified Segment 2-5 pipeline. It does **not**
add or change any DSP algorithm, and it does **not** run Segment 6's formal
LOSO validation — `validation/runLOSO.m`, `validation/computeMetrics.m`, and
`validation/blandAltman.m` are still untouched stubs.

The actual code lives in the main scaffold, not in this folder:

- [`matlab/src/io/loadVIPLVideo.m`](../matlab/src/io/loadVIPLVideo.m)
- [`matlab/src/io/loadVIPLGroundTruth.m`](../matlab/src/io/loadVIPLGroundTruth.m)
- [`matlab/scripts/run_vipl_integration_batch.m`](../matlab/scripts/run_vipl_integration_batch.m)
- [`docs/VIPL_DATA_FORMAT.md`](../docs/VIPL_DATA_FORMAT.md) — the full,
  file-verified format writeup; read this before touching the loaders.

This `vipl_integration/` folder is docs only (no code):

- `VIPL_Integration_Guideline.pdf` — why this integration exists, why no
  algorithm code changed, and the one real format surprise (VIPL-HR's
  video frame rate) that shaped the loader design.
- `VIPL_Integration_LineByLine_Explanation.md` — a plain-language
  walkthrough of every block of both loader functions.
- This README.

## 1. VIPL-HR is not extracted on disk yet — extract only your own share

The full VIPL-HR download sits, still zipped, at
`H:\EEE 312 project\Contactless Vital Sign\VIPL-HR-V1\data\` — 21 archives
(`p1-5.zip`, `p6-10.zip`, ..., `p101-107.zip`), about **48.6 GB compressed
total**, covering all 107 subjects. **Do not run `Expand-Archive` (or any
whole-archive unzip) on one of these files** — a single archive can be over
2.5 GB, and unzipping several of them on a machine with limited free disk
space (this integration was built with only ~56 GB free) risks running the
drive out of space for everyone else's work too.

Instead, extract only the specific `(subject, scenario, source)` triples
you're assigned, using targeted per-entry extraction. A short PowerShell
snippet that does this (adjust `$targets` to your own assigned subjects):

```powershell
$destRoot = "H:\EEE 312 project\Contactless Vital Sign\spandan\data\raw\VIPL-HR"
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead("H:\EEE 312 project\Contactless Vital Sign\VIPL-HR-V1\data\p1-5.zip")
$targets = @("p1/v1/source1/", "p1/v1/source2/", "p1/v1/source3/")
foreach ($entry in $zip.Entries) {
  foreach ($t in $targets) {
    if ($entry.FullName.StartsWith($t) -and $entry.Name -ne "") {
      $outPath = Join-Path $destRoot $entry.FullName
      New-Item -ItemType Directory -Force -Path (Split-Path $outPath -Parent) | Out-Null
      [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $outPath, $true)
    }
  }
}
$zip.Dispose()
```

Each subject `pN` lives in the zip named for the 5-subject range containing
`N` (e.g. `p1`-`p5` are in `p1-5.zip`, `p6`-`p10` are in `p6-10.zip`, etc. —
see the file listing under `VIPL-HR-V1\data\`). Extracted files must land
under `spandan/data/raw/VIPL-HR/pXXX/vY/sourceN/` for the loaders to find
them — that path is built automatically by `loadVIPLVideo.m`/
`loadVIPLGroundTruth.m` from `data/raw/VIPL-HR` plus your subject/scenario/
source numbers, so don't rename or restructure anything after extraction.

Check `VIPL-HR-V1\Missing_data.txt` before assuming a triple exists — 107
real `(subject/scenario/source)` combinations are absent despite the naming
convention predicting them (e.g. `p1/v7/source1`). `run_vipl_integration_
batch.m` logs a missing file as a per-subject failure and continues rather
than halting, so this is safe to hit, just expected.

## 2. Only RGB sources are supported (source1, source2, source3)

`source4` is VIPL-HR's near-infrared camera, a different sensing modality
this pipeline was never built for — `loadVIPLVideo.m` rejects it outright
with a clear error. Stick to source1 (webcam), source2 (phone), or source3
(RealSense color) when picking triples to run.

## 3. Running the integration batch

1. Open MATLAB, `cd` into `spandan/matlab/`.
2. Run `startup` (adds `src/` to the path).
3. Open `scripts/run_vipl_integration_batch.m` and edit the
   `subjectTriples` matrix at the top to your own assigned
   `[subjectNum, scenarioNum, sourceNum]` rows (one row per video).
4. `addpath('scripts')` (or `cd scripts`), then run
   `run_vipl_integration_batch`.

For each triple it runs the full chain — ROI extraction, filtering,
CHROM/POS/green heart rate, ratio-of-ratios SpO2 — and saves everything
under `VIPL_p<N>_v<scenario>_source<S>` subject IDs, so nothing collides
with UBFC's `5-gt`/`subject5`-style IDs when pooled later. A subject that
fails (missing file, no detected face, etc.) is logged and skipped; the
rest of the batch continues.

Output, all with the `VIPL_` prefix:
- `data/processed/VIPL_..._rgb_traces.mat` / `..._filtered_traces.mat` /
  `..._hr_estimates.mat` — same shape as the UBFC equivalents.
- `results/figures/VIPL_..._roi_sanity.png` / `..._filtering_sanity.png` /
  `..._heartrate_sanity.png` — **look at these before trusting the
  numbers**, same discipline as every prior segment.
- `results/metrics/segment4_hr_summary_vipl.csv` — same column layout as
  Segment 4's `segment4_hr_summary.csv` plus an explicit `dataset` column.
  Written to its **own** file, not appended to the shared UBFC file — see
  the Line-by-Line doc Part 3 for why (the shared file's header is owned
  by `run_segment4_heartrate_batch.m`, out of scope for this integration).
- `results/metrics/segment5_vipl_calibration.csv` (only produced once at
  least 3 subjects succeed in one run — the leave-one-out loop needs that
  many) plus `results/figures/segment5_vipl_calibration_scatter.png`.

## 4. How this integration's outputs feed into Segment 6

`segment4_hr_summary_vipl.csv` and `segment5_vipl_calibration.csv` are raw
material for Segment 6, exactly the same relationship UBFC's own summary
CSVs already have to it — not a substitute for it. Segment 6 can pool
UBFC + VIPL results either by reading the explicit `dataset` column on the
VIPL files, or by concatenating both HR files directly and inferring
dataset from the `VIPL_` subjectID prefix on rows that lack the column.

**Segment 6 (formal leave-one-subject-out validation) is the next and final
validation segment for this project, and this integration is what unblocks
it from being limited to DATASET_1's 5 SpO2 subjects.** `validation/
runLOSO.m`, `validation/computeMetrics.m`, and `validation/blandAltman.m`
remain untouched stubs — proper MAE/RMSE/correlation/Bland-Altman reporting
across the full pooled UBFC + VIPL-HR subject pool is Segment 6's job, not
this one's. This integration's job was narrower: confirm VIPL-HR's real
files can be read correctly and fed through the existing pipeline without
touching any tested algorithm code, and be explicit about exactly how much
(or little) a 3-subject validation run can prove on its own.
