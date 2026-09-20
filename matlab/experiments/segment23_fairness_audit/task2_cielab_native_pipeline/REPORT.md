# Segment 23 Task 2 — CIELab a* in its native pipeline (Yang et al., J. Biomed. Opt. 21(11):117001, 2016; PMC5995145)

**Verdict: EVALUATED, NOT ADOPTED — unchanged, and clearer.** Implementing the paper's three components does not make a* competitive: the native pipeline is **much worse** than the
Segment 18 fixed-box a* (MAIN_112 MAE 16.5 vs 9.5) and far behind production CHROM/POS (7.8 / 7.2). The only component that helps at all is the sum-normalised colour transform, by a margin inside noise.

**Scheduling: HEAVY (verified).** New ROI selection and KLT tracking need frame-level access → one video pass over 132 videos (5 UBFC + 107 VIPL v1 + 20 VIPL v2), 0 failures, forehead-box R/G/B bit-identical to the production cache on all 132 (parity check), run in parallel with Task 3's decode (capacity check: per-video times unchanged, 6 cores / 12 logical, ≈1.5 GB per MATLAB).

## What the paper actually says (fetched from PMC this session) — corrections to the brief
* **Grid/cell size:** "22×15 smaller areas … **20×20 pixels each**" (video 480×640, 30 fps); the **120×80-pixel region** is the *selected forehead ROI* (6×4 cells), not the cell size. The brief's "22×15 grid of 120×80 px cells" is a misreading (that grid would be 2640×1200 px). Implemented as: 22×15 cells laid over the detected face box, best 6×4-cell window (27 %×27 % of the face box, the same fraction as the paper's 120×80 of its 440×300 tiled area) in the top 6 cell-rows, scored by mean cell roughness r = μ/σ on luminance.
* **KLT:** Shi-Tomasi features, tracked frame by frame, **re-initialised every 900 frames**; "frames with loss over 30 % of the feature points are pruned". The paper does not say whether loss is per-frame or cumulative, nor how pruned frames are handled. Implemented: per-frame loss (>30 % of tracked points lost in that frame → pruned), ROI translated by the median feature displacement, our own safeguard re-init if < 10 points survive; pruned samples are linearly interpolated.
* **Colour transform (Eq. 2–5):** each channel divided by (R+G+B); `[X Y Z] = M·[Rn Gn Bn]`, M = [0.431 0.342 0.178; 0.222 0.707 0.071; 0.020 0.130 0.939]; standard CIELab f(). The paper gives no numeric (Xn,Yn,Zn) ("D65 white") and does not describe how a* becomes the pulse signal or how pruned frames are filled — Xn,Yn,Zn = row sums of M (the D65 white of that matrix) and the project's detrend → 0.7–4 Hz band-pass → `fftHeartRate` are used (same chain as Segment 18, so only the native components change). Cb/Cr: BT.601 chroma of the same sum-normalised RGB.

## Ablation (each rung adds one native component; all reported)
A0 = Segment 18 as tested (fixed forehead box, per-pixel rgb2lab, then mean) — **regression check: max |ΔHR| = 0.0000 bpm on 112 subjects for a*, Cb, Cr vs `segment18_colorspace_ablation.csv`** · A1 + the paper's sum-normalised transform · A2 + uniformity-ranked ROI with KLT translation · A3 + 30 %-loss pruning (= full native) · A3w = A3 with the project's wavelet pre-step · controls on the same native ROI: GREEN, production CHROM/POS.

## Results — MAE / RMSE / r / severe(>10 bpm)/n, per pool
| arm | UBFC (5) | VIPL v1 (107) | MAIN_112 | VIPL v2 motion (20) |
|---|---|---|---|---|
| A0 a* (Seg 18) | 3.70 / 6.15 / 0.95 / 1 | 9.80 / 14.87 / 0.35 / 35 | 9.53 / 14.59 / 0.43 / 36 | 14.51 / 20.13 / 0.11 / 11 |
| A1 a* (+ sum-norm Lab) | 2.65 / 3.77 / 0.98 / 0 | 9.62 / 14.68 / 0.36 / 37 | 9.31 / 14.37 / 0.45 / 37 | 14.83 / 20.69 / 0.20 / 9 |
| A2 a* (+ uniform ROI + KLT) | 18.92 / 23.21 / 0.43 / 3 | 16.37 / 26.54 / 0.16 / 45 | 16.49 / 26.40 / 0.16 / 48 | 21.23 / 25.79 / −0.10 / 16 |
| **A3 a* (FULL native)** | 18.92 / 23.21 / 0.43 / 3 | 16.37 / 26.54 / 0.16 / 45 | **16.49 / 26.40 / 0.16 / 48** | 21.23 / 25.79 / −0.10 / 16 |
| A3w a* (native + wavelet) | 17.35 / 21.72 / 0.37 / 3 | 12.56 / 17.02 / 0.25 / 50 | 12.78 / 17.26 / 0.32 / 53 | 21.89 / 26.00 / −0.05 / 17 |
| A0 Cb / Cr (Seg 18) | 17.98 / 22.40 / 0.88 / 3 ; 12.15 / 20.47 / 0.40 / 2 | 14.76 / 19.63 / 0.04 / 61 ; 11.91 / 16.39 / 0.28 / 46 | 14.90 / 19.76 / 0.13 / 64 ; 11.92 / 16.59 / 0.32 / 48 | 22.05 / 25.66 / −0.39 / 17 ; 20.52 / 23.27 / −0.23 / 18 |
| A3 Cb / Cr (FULL native) | 16.88 / 23.11 / 0.45 / 3 ; 18.92 / 23.21 / 0.43 / 3 | 19.89 / 30.45 / 0.13 / 57 ; 15.53 / 23.69 / 0.15 / 51 | 19.75 / 30.16 / 0.13 / 60 ; 15.68 / 23.67 / 0.17 / 54 | 23.84 / 29.02 / −0.28 / 16 ; 21.44 / 24.70 / 0.23 / 17 |
| GREEN, fixed box | 12.56 / 18.88 / 0.29 / 2 | 15.10 / 19.52 / 0.03 / 61 | 14.98 / 19.49 / 0.09 / 63 | 21.80 / 24.97 / −0.21 / 18 |
| GREEN, native ROI | 21.13 / 29.12 / 0.00 / 3 | 11.50 / 16.02 / 0.35 / 46 | 11.93 / 16.82 / 0.35 / 49 | 20.96 / 23.86 / 0.16 / 18 |
| **CHROM production (fixed box)** | 3.26 / 5.05 / 0.96 / 1 | 8.05 / 12.09 / 0.48 / 31 | **7.83 / 11.87 / 0.53 / 32** | 8.85 / 12.64 / 0.54 / 7 |
| **POS production (fixed box)** | 3.77 / 6.15 / 0.94 / 1 | 7.38 / 11.02 / 0.58 / 29 | **7.22 / 10.85 / 0.62 / 30** | 10.56 / 16.06 / 0.31 / 6 |
| CHROM on the native ROI | 13.74 / 15.99 / 0.54 / 3 | 9.88 / 13.69 / 0.26 / 40 | 10.05 / 13.80 / 0.38 / 43 | 12.17 / 17.00 / 0.21 / 8 |
| POS on the native ROI | 11.30 / 13.77 / 0.87 / 3 | 8.66 / 11.68 / 0.44 / 37 | 8.78 / 11.78 / 0.54 / 40 | 13.46 / 17.93 / 0.18 / 11 |

Paired per-subject (MAIN_112, >1 bpm; sign-rank): a* A0 vs CHROM 24 better / 31 worse, 18 severe-worse (p=0.12); vs POS 20 / 31, 17 (p=0.027). **a* A3 (native) vs CHROM 27 / 44, 28 severe-worse (p=0.0007); vs POS 25 / 46, 30 (p=0.0001).**

## Interpretation
* **Component attribution.** (iii) the paper's sum-normalised Lab transform: neutral-to-slightly-helpful for a* (9.53 → 9.31; 25 % of the UBFC error, but N=5), harmful for Cb (14.9 → 20.5). (i) the uniformity-ranked ROI + (ii) KLT: **the harmful step** (a* 9.31 → 16.49, MAIN_112). It hurts every colour signal and also *production CHROM/POS* (7.83 → 10.05, 7.22 → 8.78 when moved to the native ROI) — so the loss is the ROI, not the colour space. Green improves on the native ROI in VIPL v1 (15.1 → 11.5) but not on UBFC/v2.
* **KLT frame pruning was inert here**: 0 of 132 subjects had any frame pruned (median pruned fraction 0.000), so A2 ≡ A3. Under the per-frame reading of the paper's rule, tracked motion in these clips never loses > 30 % of features in a single frame. Not tested: the cumulative-loss reading (would prune later frames and can only remove data), and any sensitivity to the 30 % threshold — so this task cannot say pruning would help under a different reading. The motion-robustness *mechanism* the paper credits to KLT is therefore untested by this data, not refuted.
* *Likely (unverified) cause of the ROI loss:* r = μ/σ rewards bright, smooth patches; on a top-of-face band that can select hairline/skin-highlight or non-forehead areas, and the ROI is fixed at initialisation and only translated (paper design) — no ROI diagnostics (overlay images) were inspected, so this is a hypothesis, not a finding. The uniformity criterion may also be tuned to the paper's own 480×640 setup; the face-box-proportional adaptation here is ours.
* **Motion pool:** native a* 21.2 bpm vs A0 14.5 and CHROM 8.85; per-pool N=20.
* Fairness reading: the incumbents were not given this ROI advantage/disadvantage (production keeps the box); the paper's *colour* claim (a* suppresses intensity noise) is supported only weakly (A1 vs A0, 0.2 bpm, not significant), and it does not survive against CHROM/POS.

**Verdict line: CIELab a* (native pipeline) — EVALUATED, NOT ADOPTED. Native form is worse than the Segment 18 form; verdict unchanged.**

## Protected-files verification
See `../common/protected_files_verification.txt`: 18/18 protected production files byte-identical before vs after Segment 23 (SHA-256).

## Outputs
`src/cielabNativeExtract.m`, `src/labFromSumNorm.m`, `scripts/run_task2_extract.m` (cache `data/processed/seg23t2_<id>.mat`, 132 files), `scripts/run_task2_eval.m`, `results/task2_summary_by_pool.csv`, `results/task2_per_subject.csv`, `results/task2_pulses_for_task5.mat`.
