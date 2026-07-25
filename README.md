# Spandan

Spandan (Bengali: "heartbeat / pulsation") is a classical digital signal
processing (DSP) project for **EEE 312 (Digital Signal Processing I
Laboratory)**, Department of Electrical and Electronic Engineering, BUET.
Supervisor: Prof. Dr. Md. Kamrul Hasan.

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
8. **Android app** (later, separate phase) — port the same pipeline for
   real-time on-device HR/SpO2 display. Not started.

## Folder structure

```
spandan/
  matlab/
    src/
      io/              - loadUBFCVideo.m, loadGroundTruth.m
      roi/             - extractROISignals.m
      filtering/       - bandpassClean.m, detrendSignal.m
      pulseextraction/ - chromCombine.m, posCombine.m
      heartrate/       - fftHeartRate.m
      spo2/            - ratioOfRatios.m, calibrateSpO2.m
      validation/      - runLOSO.m, computeMetrics.m, blandAltman.m
      pipeline/        - estimateVitals.m (chains the whole pipeline)
    scripts/           - run_pipeline_demo.m, batch_process_dataset.m
    tests/             - sanity_test.m (placeholder)
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
  docs/                - DATA_FORMAT.md and other project documentation
  android/             - reserved for a future phase, not populated yet
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

**Scaffolding only.** Every function under `matlab/src/` is a stub (a
documented function header that immediately errors with "Not implemented
yet"). No face detection, filtering, CHROM/POS, FFT, or ratio-of-ratios
logic has been written. The dataset has been explored and documented
(`docs/DATA_FORMAT.md`), but not yet extracted into `data/raw/`.
