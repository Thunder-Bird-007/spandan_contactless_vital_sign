# Spandan Final Pipeline Report

This document describes the Spandan contactless vital-sign pipeline **as it
stands today**: the two-branch architecture, each branch's parameters, and
the final validated numbers already established elsewhere in this project.
It is a methods-and-results description of the current, adopted system, not
a chronological log of how each segment got here -- see the individual
`Segment*_*.md` documents alongside this one for that history.

## 1. Standing decisions

- **SpO2 is not approved for Android display.** No validated calibration
  exists that would justify shipping it in the app. The SpO2 numbers below
  are a MATLAB-side evaluation and documentation deliverable, not an app
  feature.
- **Heart rate (CHROM/POS) is the validated, reportable output.** Its
  accuracy is summarized in Section 3.
- **The production HR/SpO2 path and the waveform-morphology path are two
  separate branches off one shared ROI extraction, never one merged filter
  choice.** Section 2 explains why.

## 2. Architecture: two branches, one shared ROI extraction

Every stage of this pipeline starts the same way: `roi/extractROISignals.m`
detects the face (Viola-Jones) and averages the forehead ROI's pixels into
three raw color-channel traces, R(t)/G(t)/B(t), plus each frame's real
acquisition timestamp. That single extraction feeds two independent
branches, both implemented in `pipeline/estimateVitalsAndMorphology.m`:

- **Branch 1 (production HR/SpO2)** -- a narrow 0.7-4 Hz bandpass
  (`filtering/bandpassClean.m`), tuned for a clean FFT peak at the cardiac
  fundamental.
- **Branch 2 (waveform morphology)** -- a wide 0.5-8 Hz bandpass
  (`morphology/bandpassMorphology.m`) plus ~~a harmonic-comb filter
  (`morphology/adaptiveHarmonicFilter.m`)~~ **[2026-09-13] a confidence-gated
  choice between two harmonic filters** (`morphology/
  harmonicFilterConfidenceGate.m`, default as of Segment 14 Task 2): the
  harmonic-comb filter (`morphology/adaptiveHarmonicFilter.m`, ABPF) is kept
  wherever its own notch confidence already clears this project's 0.3 bar,
  and a Gaussian-tapered alternative (`morphology/
  harmonicSelectiveGaussianFilter.m`, alpha=0.15) is substituted only where
  it fails -- see Section 4.3.

These two filter choices are not interchangeable. The wide band and
harmonic comb that Branch 2 needs to see a notch at all measurably **hurt**
HR accuracy when tried on Branch 1's job: the harmonic comb locks onto a
harmonic of the true rate whenever its fundamental-frequency estimate is
even slightly off (one VIPL subject's CHROM estimate jumped from 69.4 bpm to
140.8 bpm under the wide+harmonic-comb filtering), and is a wash for SpO2.
Running both branches off one shared extraction, never merging them into a
single filter choice, is therefore a deliberate design constraint of this
pipeline, not an oversight.

`pipeline/estimateVitals.m` (the original top-level stub) remains an
unimplemented placeholder and is not used anywhere in the current system;
`pipeline/estimateVitalsAndMorphology.m` is the real orchestrator, called by
`scripts/run_spandan_full_demo.m` for the figures in Section 5.

## 3. Branch 1: production heart rate and SpO2

### 3.1 Method

**[2026-09-13] PROMOTED TO DEFAULT**: `filtering/waveletDenoise.m` (DWT
wavelet-shrinkage, db4, 3-level, Donoho-Johnstone universal soft-threshold)
now runs on each raw R(t)/G(t)/B(t) channel as step 0, immediately before
step 1 below -- see `docs/Segment8_Task4_Wavelet_Denoise_Ablation.md` for
the full-pool ablation that justified this (pooled CHROM MAE 9.10->7.83bpm,
POS MAE 8.68->7.22bpm, both Pearson r nearly doubling; updated table in
Section 3.2 below). ~~Previously documented as an "available additive
option", not yet the default~~ -- it is wired into
`scripts/run_segment3_filtering_batch.m` and
`scripts/run_vipl_integration_batch.m` behind a `useWaveletDenoise` toggle
(default `true`), so pre-wavelet numbers stay reproducible by flipping that
one flag rather than editing the pipeline. **Known caveat, kept on the
record, not "fixed" away**: 7 of 112 subjects regress by >10bpm on CHROM
even as the pool improves (worst: VIPL p85, 0.44->45.81bpm) -- see the
ablation doc for the full per-subject accounting. `pulseextraction/
chromCombine.m`, `pulseextraction/posCombine.m`, and
`heartrate/fftHeartRate.m` remain unmodified; only the pre-step changed.

1. `filtering/detrendSignal.m` (cubic detrend) on each of R(t)/G(t)/B(t).
2. `filtering/bandpassClean.m`, a 2nd-order Butterworth bandpass, 0.7-4.0 Hz
   (42-240 bpm), zero-phase (`filtfilt`).
3. `pulseextraction/chromCombine.m` (CHROM, de Haan & Jeanne 2013) and
   `pulseextraction/posCombine.m` (POS, Wang et al. 2017) each combine the
   three filtered channels, normalized against each channel's own raw
   (pre-filter) DC mean, into one pulse signal; the CHROM/POS pulse is then
   re-bandpassed with the same `bandpassClean.m` filter before the FFT step.
   A green-channel-only baseline (no combination) is also carried through
   as a lower bound.
4. `heartrate/fftHeartRate.m`: FFT magnitude peak inside the same 0.7-4 Hz
   band gives HR in bpm.
5. `spo2/ratioOfRatios.m`: AC (std of the filtered Red/Blue channels) over
   DC (mean of the raw Red/Blue channels), Blue substituting for the
   camera's missing infrared channel, gives the ratio-of-ratios value R.
6. `spo2/calibrateSpO2.m`: a linear fit SpO2 = A - B*R, fit on subjects
   other than the one being predicted (never on itself).

### 3.2 Results

**Heart rate**, pooled across all 112 available ground-truth subjects (5
UBFC DATASET_1 + 107 VIPL-HR v1), `results/metrics/segment6_hr_pooled_metrics.csv`:

**[2026-09-13] PROMOTED TO DEFAULT**: the table below is now WITH wavelet
denoising (the pipeline default as of Section 3.1 above). ~~The pre-wavelet
table previously here~~ is preserved verbatim in
`results/metrics/segment6_hr_pooled_metrics_prewavelet.csv` for direct
comparison (pre-wavelet: CHROM MAE 9.0969/RMSE 18.0047/r 0.31448, POS MAE
8.6795/RMSE 16.4537/r 0.28091, pooled N=112) -- not deleted, per this
project's own "mark superseded, don't delete" convention. Green-only is
UNCHANGED (Action 4's ablation never covered it -- it is a diagnostic
lower-bound method, never the shipped result, so there is no
wavelet-denoised number to promote for it; see
`scripts/run_segment8_action2_promote_wavelet_default.m`'s own header for
why).

| Method | Scope | N   | MAE    | RMSE    | Pearson r |
|--------|-------|-----|--------|---------|-----------|
| CHROM  | pooled| 112 | 7.8344 | 11.8676 | 0.53187   |
| CHROM  | UBFC  | 5   | 3.2622 | 5.0546  | 0.96398   |
| CHROM  | VIPL  | 107 | 8.0481 | 12.0925 | 0.47953   |
| POS    | pooled| 112 | 7.2217 | 10.8493 | 0.62341   |
| POS    | UBFC  | 5   | 3.7723 | 6.1541  | 0.94019   |
| POS    | VIPL  | 107 | 7.3829 | 11.0198 | 0.58425   |
| Green  | pooled| 112 | 14.9832| 19.4896 | 0.086979  |

CHROM and POS both clearly beat the uncombined green-channel baseline; POS
has a slightly lower pooled MAE/RMSE, CHROM a slightly higher pooled
Pearson r. Both are reported as this project's production HR estimators;
neither is dropped in favor of the other. Both improved substantially with
wavelet denoising promoted to default (RMSE down ~6bpm, r nearly doubling
for both) -- not uniformly across every subject: see
`docs/Segment8_Task4_Wavelet_Denoise_Ablation.md` for the 7-subject
CHROM regression caveat, which still applies to this now-default pipeline
and is not resolved by promoting it.

**SpO2**, Task H3 stratified (within-dataset-only) leave-one-subject-out
cross-validation, the trustworthy result identified in
`docs/SpO2_Final_Report_Section.md`:

| Scope | N   | MAE    | RMSE   | Pearson r | Reliability |
|-------|-----|--------|--------|-----------|-------------|
| UBFC  | 5   | 1.9683 | 2.1857 | -0.8415   | thin -- 4 training subjects/fold, directional only |
| VIPL  | 107 | 1.9078 | 5.4303 | -0.3333   | thin-data-safe -- ~106 training subjects/fold |

VIPL's N=107 number (MAE 1.908, r=-0.333) is the one worth citing as this
project's SpO2 accuracy. As already documented in
`docs/SpO2_Final_Report_Section.md`, this calibration does not beat a
trivial "predict the training-fold mean" baseline at this data scale --
stated plainly there and repeated here rather than re-derived, since that
finding is unchanged by anything in Segment 7. This is why SpO2 stays a
MATLAB-side reporting deliverable, not an app feature (Section 1).

## 4. Branch 2: waveform morphology and the dicrotic notch

### 4.1 Method

1. `filtering/detrendSignal.m` on each raw channel (same detrend as Branch
   1, shared before the branches diverge).
2. A single shared cardiac fundamental f0 is estimated once: each channel
   is bandpassed 0.5-8.0 Hz (`morphology/bandpassMorphology.m`, `'wide'`
   mode), CHROM-combined, and `heartrate/fftHeartRate.m` reads its peak
   frequency. All three channels are then filtered around this ONE shared
   f0 rather than three independently-noisy per-channel estimates.
3. ~~`morphology/adaptiveHarmonicFilter.m`: a harmonic-comb filter, keeping
   only narrow FFT bins around f0 and its next 5 harmonics (6 harmonics
   total) per channel, everything else zeroed.~~ **[2026-09-13, Segment 14
   Task 2]** `morphology/adaptiveHarmonicFilter.m` (the harmonic-comb
   filter above, still computed first, unchanged) is now followed by
   `morphology/harmonicFilterConfidenceGate.m`: if ABPF's own notch
   confidence already exceeds 0.3, its output is kept as-is; otherwise
   `morphology/harmonicSelectiveGaussianFilter.m` (a Gaussian-tapered
   comb, alpha=0.15, Dominguez-Hernandez/Paez/Padilla, *Sensors*
   26(12):3710, 2026) is computed and substituted. Gated behind
   `pipeline/estimateVitalsAndMorphology.m`'s `opts.useConfidenceGate`
   (default `true`; set `false` for the exact pre-promotion ABPF-only
   behavior).
4. `pulseextraction/chromCombine.m` combines the three harmonic-filtered
   channels into one pulse.
5. Polarity is anchored against the ground-truth contact PPG
   (`morphology/fixPolarityByGroundTruth.m`, cross-correlation-based) when
   ground truth is available, or the skewness heuristic
   (`morphology/fixPolarity.m`) as a fallback with no reference signal
   (e.g. a future Android deployment).
6. `morphology/resampleUniform.m` puts the polarity-fixed pulse onto a
   uniform 250 Hz grid using the ROI's real per-frame timestamps (not an
   assumed constant frame interval).
7. `morphology/ensembleAverageBeats.m` segments individual cardiac cycles,
   time-warps each to anchor its systolic peak at cycle-fraction 0.25,
   quality-gates by duration and cross-correlation to the rough template,
   and coherently averages the survivors into one prototype beat
   (trimmed mean across 256 samples/beat) plus a per-sample IQR band, the
   quantitative beat-to-beat stability measure.
8. `morphology/notchDetectIEM.m` (Iterative Envelope Mean method, Pal et
   al. 2024) locates the dicrotic notch on the prototype beat, at an
   effective sample rate derived from a third, independent
   `heartrate/fftHeartRate.m` call on the resampled signal (beatSamples *
   hrBpm/60).

### 4.2 Results (the original ABPF-only condition, `useConfidenceGate=false`)

Notch detection on all 5 UBFC DATASET_1 ground-truth subjects,
`results/metrics/segment7_task_b_notch_branch2.csv` ('adaptiveHarmonic'
rows -- byte-identical before and after the Section 4.3 promotion below,
since these 5 subjects are unaffected by it, see 4.3):

| Subject         | Notch detected | Position (cycle frac.) | Depth  | Confidence |
|-----------------|:---:|:---:|:---:|:---:|
| 5-gt            | yes | 0.5725 | 0.2629 | 0.7447 |
| 6-gt            | yes | 0.5137 | 0.1699 | 0.4120 |
| 7-gt            | yes | 0.4510 | 0.2431 | 0.6405 |
| 12-gt           | yes | 0.8039 | 0.3789 | 1.0000 (clipped -- true ratio exceeds 1) |
| after-exercise  | yes | 0.5882 | 0.2395 | 0.1582 |

A notch is detected on all 5 of 5 subjects; 4 of 5 clear the >= 0.3
confidence threshold this project has used elsewhere as the "confident
detection" bar (`after-exercise`, elevated heart rate after physical
exertion, is the one exception, at 0.1582). This is a small, UBFC-only
pool (n=5) -- the same "thin data" caveat that applies to every UBFC-only
number in this project applies here too; it is reported as this project's
morphology-branch result, not claimed as a general-population notch-
detection rate.

### 4.3 Confidence-gated default (Segment 14 Task 2, 2026-09-13)

`morphology/harmonicFilterConfidenceGate.m` is now the production default
(Section 2). It was derived and validated on a much larger scale than
Section 4.2's 5-subject pool: Segment 10 Task 1's 100-subject audit pool
(5 UBFC-D1 + 95 VIPL v1/source1) and, for a genuinely held-out check,
UBFC DATASET_2 (33 of 42 subjects scored -- see
`docs/Segment14_Task1_UBFC_D2_Held_Out_Validation.md` for the 9 excluded
and why).

| Pool | n | ABPF pass rate | **Gate pass rate** | ABPF median corr | **Gate median corr** | Severe regressions (gate) |
|---|---|---|---|---|---|---|
| Segment 10 Task 1 audit pool | 100 | 24% | **47%** | 0.519 | **0.522** | **0** |
| Segment 14 Task 1 held-out (UBFC-D2) | 33 | 45% | **58%** | 0.364 | **0.520** | **0** |

The gate's defining property -- it never turns an already-passing subject
into a failing one -- held on every one of 133 subjects checked across
both pools. **On this section's own 5-subject legacy pool specifically,
the gate makes no difference** (still 4/5 pass; the one eligible subject,
`after-exercise`, is substituted but not rescued, 0.1582 -> 0.0011) --
N=5 with only one eligible subject is too small to show the effect seen at
scale, stated plainly rather than implied to have improved. Full detail:
`docs/Segment13_Task1_Gaussian_Regression_Root_Cause_and_Gate.md`,
`docs/Segment14_Task1_UBFC_D2_Held_Out_Validation.md`,
`docs/Segment14_Task2_Confidence_Gate_Production_Promotion.md`.

## 5. Orchestrator and demo

`pipeline/estimateVitalsAndMorphology.m` is the single entry point that
runs both branches off one ROI extraction and returns one result struct:
`hrBpm` (chrom/pos/green), `spo2Pct`, `prototype` + `iqrBand` (the
morphology waveform and its stability band), and `notch`
(detected/position/depth/confidence), plus full per-branch detail
(`branch1`, `branch2`) for callers that need it.

`scripts/run_spandan_full_demo.m` runs it on all 5 UBFC DATASET_1
ground-truth subjects and renders one combined 4-panel figure per subject
to `results/figures/spandan_demo_<subjectID>.png`: (i) the raw ROI trace,
(ii) the production CHROM pulse with HR annotated, (iii) the morphology
ensemble-averaged waveform with its IQR stability band shaded and the
detected notch position marked, and (iv) a text summary (HR for all three
methods, leave-one-out-calibrated SpO2, and notch confidence). SpO2 in
these figures is calibrated by the same 5-subject leave-one-out loop
`scripts/run_segment5_dataset1_calibration_batch.m` already uses (never
fit and predicted on the same subject).

## 6. Validation

`tests/segment7_task_f_regression_test.m` confirms
`pipeline/estimateVitalsAndMorphology.m`'s wiring reproduces every number
this report cites, computed independently by earlier segments' own
scripts, before this file existed:

- **Branch 1 HR** (subject 5-gt): HR_chrom/HR_pos/HR_green match
  `data/processed/5-gt_hr_estimates.mat` bit-for-bit (`isequal`).
- **Branch 1 SpO2 path** (all 5 UBFC subjects): the ratio-of-ratios R value
  matches `results/metrics/segment5_dataset1_calibration.csv`'s saved R,
  and the resulting leave-one-out calibrated SpO2 matches that CSV's saved
  prediction for every subject.
- **Branch 2 notch** (all 5 UBFC subjects): notch
  detected/position/depth/confidence match
  `results/metrics/segment7_task_b_notch_branch2.csv`'s 'adaptiveHarmonic'
  row for every subject. **[2026-09-13, Segment 14 Task 2]** This part now
  explicitly calls `estimateVitalsAndMorphology.m` with
  `'useConfidenceGate', false`, since it is testing the ABPF-only
  `'adaptiveHarmonic'` condition BY NAME -- independent of
  `opts.useConfidenceGate`'s own default, which is now `true` (Section
  4.3). Re-run this session after that default changed: still passes.

All three parts passed on the run this report is based on.
