# Segment 18 (MATLAB) — CIELab a\* and YCbCr Cb/Cr as Pulse-Extraction Channels

Run 2026-09-20. (Numbering note: `android/docs/Segment18_Camera_Throughput_And_Buffer_Window.md`
already uses "Segment 18" for an unrelated Android workstream; this is the MATLAB
colour-space segment. All file names here are `segment18_colorspace_*`.)

Tests whether a CIELab **a\*** channel, or YCbCr **Cb** / **Cr**, works as a
single-channel rPPG pulse source, against the existing green-channel baseline,
on the Segment 8 pool (5 UBFC-D1 + 107 VIPL v1) **plus a new 20-subject VIPL
v2 (large head motion) pool**, because the original pool has no deliberate head
motion. Diagnostic ablation only — `estimateVitalsAndMorphology.m`, CHROM and
POS untouched, nothing promoted.

## Headline

1. **a\* clearly beats green on HR** (pooled N=112: MAE **14.98 → 9.53 bpm**, r **0.09 → 0.43**;
   paired sign-rank p=0.0001, 71 subjects better / 28 worse by >1 bpm). Cb is
   indistinguishable from green (14.90 bpm, p=0.91). Cr is in between (11.92 bpm, p=0.019).
2. **But green is the weakest method in this project, not the bar to clear.**
   Production CHROM/POS (wavelet default) are 7.83 / 7.22 bpm, r 0.53 / 0.62 on the
   same 112 subjects (`segment6_hr_pooled_metrics.csv`). a\* does **not** reach them.
3. **PLV does not support a\* (or Cb/Cr) as more motion-robust.** Median cross-ROI PLV:
   green 0.310, a\* 0.275, Cb 0.231, Cr 0.271. Only in the v2 motion pool is a\*/Cr
   slightly above green (0.273/0.280 vs 0.258) — small, and on N=20. PLV also did
   not track HR error within a channel (Spearman(PLV, abs error) was *positive*, i.e. wrong
   direction, for a\*, Cb, Cr on the main pool), so it is weak evidence either way here.
4. **Recommendation: do NOT promote a\*/Cb/Cr into production Branch 1.** Reasons in §Recommendation.

## Method

New `matlab/src/roi/extractROISignalsLab.m`: face detection and ROI geometry duplicated
verbatim from `extractROISignals.m` (original untouched). Per frame, on each cropped
ROI patch (converted to double [0,1]), `rgb2lab` and `rgb2ycbcr` are applied **before**
spatial averaging (nonlinear, so averaging first would be different), then pooled
exactly as R/G/B are (bilateral regions pooled before averaging). It also returns all
four Task N regions (forehead/glabella/malar/cheek) from the same decode pass so
cross-ROI PLV needs no second read. **Parity check**: R/G/B from the new extractor are
bit-identical to `extractROISignals.m` (checked on 5-gt, 2409 frames).

`run_segment18_colorspace_ablation_batch.m` (same 5 UBFC + 107 VIPL subject list as
`run_segment8_task4_wavelet_ablation_batch.m`) runs, independently for G, a\*, Cb, Cr:
forehead `detrendSignal → bandpassClean → fftHeartRate`; and per region the same
detrend+bandpass followed by `computeCrossROIPLV` over the 4 regions. **Regression
check**: fresh G HR equals the existing `segment4_*` HR_green for 112/112 subjects
(max diff 0.000000). GT comes from those same baseline CSVs (0 NaN, 112/112 valid).
`run_segment18_colorspace_ablation_motion_batch.m` does the same for VIPL v2/source1
(20 subjects; GT from Task N's `segment6_task_n_region_hr_summary.csv`, `v2_motion`).
`run_segment18_colorspace_evaluation.m` computes the metrics (`computeMetrics`).

Deliberate choices: no wavelet pre-step (the requested chain, and what makes G identical
to the existing green baseline); PLV is computed on a single-channel trace per region
(no CHROM/POS combination exists for one chroma channel), so it is comparable across
the four channels here but **not** to Segment 10/11's post-CHROM/POS PLV values.

## Results — main pool (5 UBFC + 107 VIPL v1, N=112)

| Channel | Pooled MAE | RMSE | r | UBFC MAE (N=5) | VIPL MAE (N=107) | median PLV |
|---|---|---|---|---|---|---|
| green | 14.98 | 19.49 | 0.087 | 12.56 | 15.10 | **0.310** |
| a\* | **9.53** | **14.59** | **0.427** | **3.70** | **9.80** | 0.275 |
| Cb | 14.90 | 19.76 | 0.127 | 17.98 | 14.76 | 0.231 |
| Cr | 11.92 | 16.59 | 0.317 | 12.15 | 11.91 | 0.271 |
| *(ref) CHROM, wavelet* | *7.83* | *11.87* | *0.532* | *3.26* | *8.05* | — |
| *(ref) POS, wavelet* | *7.22* | *10.85* | *0.623* | — | — | — |

UBFC N=5 is far too small to conclude anything (Cb has r=0.88 there with MAE 18 bpm).

## Results — motion pool (VIPL v2, large head movement, N=20)

| Channel | MAE | RMSE | r | median PLV |
|---|---|---|---|---|
| green | 21.81 | 24.98 | -0.213 | 0.258 |
| a\* | **14.51** | **20.13** | **0.109** | 0.273 |
| Cb | 22.05 | 25.66 | -0.393 | 0.261 |
| Cr | 20.53 | 23.27 | -0.234 | **0.280** |

Under motion every single channel is poor (r near zero or negative). a\* is best on
HR error but still far off (Task N's forehead-region v2 MAE was 8.18 bpm; see
`Segment6_Task_N_Multi_Region_ROI.md`).

## Per-subject regressions (not just medians)

Change in abs HR error vs. green (main pool, N=112; regression = worse by >10 bpm):

| Channel | better >1 bpm | worse >1 bpm | severe worse | severe better | sign-rank p |
|---|---|---|---|---|---|
| a\* | 71 | 28 | **12** | 36 | 0.0001 |
| Cb | 39 | 34 | **18** | 21 | 0.91 |
| Cr | 52 | 29 | **15** | 29 | 0.019 |

Motion pool (N=20): a\* 11 better / 5 worse, 3 severe worse (p8, p11, p18) vs 10 severe better
(p=0.034); Cb 2 severe worse / 2 better; Cr 3 severe worse / 5 better.

The 12 a\* regressions on the main pool are: VIPL p7, p10, p22, p24, p26, p48, p54, p88, p90 (v1/source1)
and p97, p102, p104 (source2). **Pattern worth noting**: most of them land at ~43–56 bpm
while ground truth is 72–97 bpm (e.g. p24 GT 87.2, a\* 51.9; p54 GT 80.0, a\* 42.9) — i.e. the a\*
spectral peak sits near the low edge of the 0.7–4 Hz band (42 bpm), not on a harmonic (harmonic-lock
count for a\* is only 2/112). That suggests a slow, non-cardiac component (illumination/motion/respiration
leakage) dominating a\* for those subjects. This is a hypothesis from the numbers, not tested here.
Also, some subjects give the same HR for G/Cb/Cr (e.g. p21 v2: Cb=Cr=56.52), so Cb/Cr often collapse
onto the same spectral peak; the per-subject files hold every value.

## Limitations

- **This dataset only weakly tests the paper's core motion-robustness claim.** The main pool has no
  deliberate head motion (UBFC-D1 seated still; VIPL v1 stable). The 20-subject v2 pool is the only
  motion evidence and it is small, single-scenario, single-camera (source1, ~16 fps effective for several
  subjects), and PLV there separates channels by only ~0.01–0.02. A real motion validation needs
  more v2/v9 (phone motion, not extracted locally) and, ideally, the planned self-collected set.
- Green here is the no-wavelet baseline; a\* was not run with wavelet or as an input to CHROM/POS-style
  combination, so "a\* vs production" is only compared against the production numbers, not a matched ablation.
- Single-channel a\* has no chrominance projection; CHROM/POS gains come from combining channels, which is
  a different question from whether one chroma channel is a better *single* source.
- PLV is a weak proxy here (see Headline 3); it was validated on post-CHROM/POS traces (n=20), not on single channels.

## Recommendation

**Don't promote a\*, Cb or Cr into production Branch 1.** a\* is a real improvement over green
(the one clean, significant positive result), but green is not what ships; pooled and per-dataset a\* still
loses to CHROM/POS (9.53 vs 7.83/7.22 bpm), it has 12 severe per-subject regressions, and neither PLV
nor the motion pool shows the robustness advantage that would justify overriding that. Cb is a wash;
Cr is marginal. If a follow-on is wanted, the better-posed questions are (1) a\* as an *extra* input to a
region/estimator switch (it is right where green is wrong on 36 subjects), and (2) a\* with the
wavelet pre-step, each with an explicit go/no-go like cPACE got in Segment 11. Neither is started.

## Outputs

`matlab/src/roi/extractROISignalsLab.m`; `matlab/scripts/run_segment18_colorspace_ablation_batch.m`,
`..._motion_batch.m`, `run_segment18_colorspace_evaluation.m`;
`results/metrics/segment18_colorspace_ablation.csv`, `..._ablation_motion.csv`,
`segment18_colorspace_pooled_metrics.csv`, `..._pooled_metrics_motion.csv`,
`segment18_colorspace_per_subject_vs_green.csv`, `..._per_subject_vs_green_motion.csv`.
