# Spandan

Spandan (Bengali: "heartbeat / pulsation") is a classical digital signal
processing (DSP) project for **EEE 312 (Digital Signal Processing I
Laboratory)**, Department of Electrical and Electronic Engineering, BUET.
Supervisor: Prof. Dr. Md. Kamrul Hasan.

**Status: MATLAB pipeline validated, Android app defense-ready.** This
top section was stale for most of the project's history (see
[Current status](#current-status) below, which the rest of this file left
unchanged until now) -- it described the repo as empty scaffolding with
every function stubbed out. That was true only for the very first commit.
Since then: the full HR pipeline (face detection → ROI → filtering →
CHROM/POS → FFT) has been implemented and LOSO-validated (r=0.957, MAE
~3.8bpm, pooled UBFC+VIPL), SpO2 has a finalized calibration (validated
but weak -- see caveat below), and the Android app
(`android/`) ships a real, on-device HR + SpO2 pipeline, verified on
physical hardware. See
[`android/docs/Defense_Readiness_Checklist.md`](android/docs/Defense_Readiness_Checklist.md)
for the current defense-readiness snapshot.

## Download & Install (Android app)

Want to try the Android app without building it? Grab the latest debug APK
from the
[Releases page](https://github.com/Thunder-Bird-007/spandan_contactless_vital_sign/releases/latest)
(always points to the newest build) and sideload it on an Android 7.0+
phone -- allow "install from unknown sources" if prompted, install, then
grant the camera permission on first launch. See
[`android/README.md`](android/README.md#download--install) for full steps
and what's validated vs. not before trusting an on-screen reading.

## Goal

Estimate heart rate (HR) and blood oxygen saturation (SpO2) from ordinary
facial video, with no contact sensor, using classical (non-deep-learning)
DSP methods in MATLAB.

## Pipeline stages

1. **Face detection + ROI extraction** — detect the face per frame, crop a
   forehead/cheek region of interest (ROI), spatially average pixel
   intensities per color channel to get three 1-D signals R(t), G(t), B(t).
2. **Detrend + bandpass filter** — clean each channel signal, restricting
   to the 0.7-4 Hz physiological HR band.
3. **CHROM / POS combination** — combine the filtered channels using the
   published CHROM and POS algorithms (motion-robust pulse extraction),
   instead of naive single-channel averaging.
4. **FFT -> heart rate** — FFT the combined pulse signal, find the
   dominant frequency, convert to HR in bpm.
5. **SpO2 estimation** — extract AC (pulsatile) and DC (baseline)
   components per channel, compute a Red/Blue ratio-of-ratios, and map it
   to SpO2% via a linear calibration fitted against ground-truth SpO2
   labels. (The camera has no infrared channel, so Blue substitutes for
   Infrared — a known, published approximation, not something invented
   for this project.)
6. **Validation** — leave-one-subject-out (LOSO) cross-validation, so the
   same subject never appears in both calibration and test data. Reports
   MAE, RMSE, Pearson correlation, and Bland-Altman plots.
7. **Self-collected test set** (later phase) — classmates on video with
   simultaneous ground truth from a real pulse oximeter, held out
   separately from the public training data, used purely for final
   accuracy reporting.
8. **Android app** — real-time on-device HR/SpO2 display, ported from the
   validated MATLAB pipeline. **Implemented**, not just planned: see
   `android/` (Kotlin source) and
   [`android/README.md`](android/README.md) for the full port history,
   what's a faithful port vs. still an open accuracy caveat, and on-device
   verification results.

## Folder structure

```
spandan/
  matlab/
    src/
      io/              - loadUBFCVideo.m, loadGroundTruth.m
      roi/             - extractROISignals.m (multi-region as of Task N;
                         Android uses only its default forehead mode)
      filtering/       - bandpassClean.m, detrendSignal.m, plus later
                         Segment 6 refinement scripts (not ported to
                         Android -- see android/docs/Defense_Readiness_
                         Checklist.md's standing decision on Tasks L/N/O/P)
      pulseextraction/ - chromCombine.m, posCombine.m
      heartrate/       - fftHeartRate.m, windowedHeartRate.m (Task P)
      spo2/            - ratioOfRatios.m, calibrateSpO2.m -- ported live
                         to Android, see android/docs/
                         SpO2_Live_Implementation.md
      validation/      - runLOSO.m, computeMetrics.m, blandAltman.m,
                         plus later Segment 6 region-agreement/
                         harmonic-consistency scripts
      pipeline/        - estimateVitals.m (chains the whole pipeline)
    scripts/           - run_pipeline_demo.m, batch_process_dataset.m,
                         plus per-Task Segment 6 batch/eval scripts
    docs/              - Segment 6 Task-by-task investigation write-ups
                         (K/L/N/O/P/Q/R) and the final SpO2 calibration
                         spec/report -- most of these are MATLAB-side
                         findings deliberately NOT ported to Android; see
                         each doc and android/docs/Defense_Readiness_
                         Checklist.md for which and why
    tests/             - sanity_test.m
    startup.m          - adds all src/ subfolders to the MATLAB path
  data/
    raw/
      UBFC-rPPG/       - place the extracted UBFC-rPPG dataset here
                         (see docs/DATA_FORMAT.md for exactly what to
                         extract from the messy source download)
      PURE/            - empty, reserved (access request pending)
      VIPL-HR/         - empty, reserved (access request pending)
    processed/         - cached intermediate .mat files (generated, not
                         committed)
    self_collected/    - reserved for the classmate test set (later phase)
  results/
    figures/           - generated plots (Bland-Altman, spectra, etc.)
    metrics/           - generated metric tables (MAE/RMSE/correlation)
    logs/               - generated run logs
  docs/                - DATA_FORMAT.md, VIPL/Hoffman data-format notes,
                         the Android HR-switching port spec, and other
                         cross-cutting project documentation
  android/             - the Android app (Kotlin/CameraX/ML Kit), fully
                         implemented: real on-device HR + SpO2 pipeline,
                         verified on physical hardware. See
                         android/README.md and android/docs/ for the full
                         history, verification results, and defense-
                         readiness checklist.
```

`data/raw/`, `data/processed/`, `data/self_collected/`, and `results/` are
git-ignored (see `.gitignore`) — this is an academic repo and should not
carry gigabytes of video/dataset content in its history.

## Getting started

1. Open MATLAB R2024b.
2. `cd` into `spandan/matlab/`.
3. Run `startup.m` to add all `src/` subfolders to the path.
4. See `docs/DATA_FORMAT.md` for what's actually in the downloaded
   UBFC-rPPG data and where to extract it before running anything under
   `scripts/`.

## Current status

**Superseded -- this section described the project's very first commit and
was never updated as work progressed.** Kept here (marked, not deleted,
per this project's own documentation convention -- see `android/README.md`
for other examples) so the project's actual history is visible rather than
silently rewritten.

> ~~**Scaffolding only.** Every function under `matlab/src/` is a stub (a
> documented function header that immediately errors with "Not implemented
> yet"). No face detection, filtering, CHROM/POS, FFT, or ratio-of-ratios
> logic has been written. The dataset has been explored and documented
> (`docs/DATA_FORMAT.md`), but not yet extracted into `data/raw/`.~~

**Actual current status:**

- **MATLAB pipeline (Segments 2-6): implemented and validated.** Face
  detection/ROI, detrend+bandpass filtering, CHROM/POS pulse extraction,
  FFT heart rate, and SpO2 ratio-of-ratios + linear calibration are all
  real, working code (`matlab/src/`), not stubs. HR is validated via
  stratified LOSO at **r=0.957, MAE ~3.8bpm** (pooled UBFC+VIPL). SpO2's
  calibration is finalized but weak -- stratified LOSO MAE 1.908 (VIPL),
  which does **not** beat a trivial "guess the training mean" baseline
  within the narrow observed SpO2 range (see
  `matlab/docs/SpO2_Final_Report_Section.md` for the full, honest
  breakdown -- this is reported plainly, not hidden).
- **Segment 6 investigated several further refinements** (device-
  stratified evaluation, multi-region ROI, detrend/adaptive-bandpass
  tuning, windowed harmonic continuity, phone-camera SpO2 centering --
  Tasks L/N/O/P/Q/R, `matlab/docs/`). Some were adopted (e.g. Task R's
  finding that phone-camera SpO2 needs no device-specific centering, now
  live in the Android app); most were deliberately **not** ported into the
  Android app this close to defense (regression risk vs. available
  runway) -- see `android/docs/Defense_Readiness_Checklist.md`'s standing
  decision for exactly which and why.
- **Android app: implemented and verified on physical hardware**, not a
  future phase. Real, on-device HR (CHROM/POS+FFT) and SpO2
  (ratio-of-ratios + calibration) both run live from the phone camera.
  Multiple defense-readiness passes (permission-handling fix, ROI-geometry
  reconciliation against MATLAB, a 16+ minute continuous crash-free
  stability run, UI cleanup) are documented in `android/README.md` and
  `android/docs/`. **Known, honestly-reported limitation:** the Android
  build's on-device HR accuracy has not been shown to match MATLAB's
  validated r=0.957 result -- see `android/README.md`'s own verification
  sections for why (shorter live buffer window vs. MATLAB's ~80s clips)
  before treating an on-screen bpm reading as validated-accurate.
- **Self-collected test set** (pipeline stage 7): not yet started.
