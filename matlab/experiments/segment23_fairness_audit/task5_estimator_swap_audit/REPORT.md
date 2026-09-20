# Segment 23 Task 5 — Estimator-swap audit (combiner × HR read-out)

**Verdict: the "earlier loss was a read-out artefact" hypothesis is REJECTED for every challenger combiner** (CIELab a*/Cb/Cr, 2SR, LGI, cPACE Full, GREEN, and the native/masked variants from Tasks 2–3).
Under the four sensible read-outs (whole-clip FFT, naive windowed, the LGI paper's windowed read-out, the state-space tracker) no challenger beats production CHROM/POS on MAIN_112 by MAE, and none is
significantly better per subject. The read-out **does** matter a great deal — it moves *every* combiner (incumbents included) by 1–3 bpm — but it moves them together, so ranks against CHROM/POS do not change.
**A separate, material finding about the existing record:** on MAIN_112 the windowed/tracked read-outs improve the incumbents themselves (CHROM 7.83 → 6.38/6.54, POS 7.22 → 6.70/6.29) — a CANDIDATE, not promoted (Task 4 explains the confounds).

**Scheduling: LIGHT (verified).** No ROI extraction or video I/O in this task; every trace is rebuilt from caches. The Task 2/3 byproducts (native a*, skin-masked 2SR) come from those tasks' own passes.

## Method
* **Combiners (19), each rebuilt "as originally tested" with its own original chain** (so a challenger is not silently given the incumbents' tuning): CHROM/POS (production wavelet chain, and the no-wavelet chain as an extra pair for parity with the untuned challengers); GREEN (detrend→band-pass, Segment 4/18 form); cPACE Stage 1 + CHROM/POS (global q̂, no wavelet, Segment 11 wiring), cPACE Full bw 0.30 / 0.15 (Segment 15, no wavelet); CIELab a* / YCbCr Cb / Cr (Segment 18 form, regenerated as a Task 2 byproduct — regression-checked exact); 2SR (Segment 22, forehead box, stride 2.0 s); LGI projection (Segment 22 chain, wavelet); plus this segment's native a*/Cb/Cr (Task 2) and skin-masked 2SR (forehead and face, Task 3).
* **Estimators (6):** E1 whole-clip `fftHeartRate.m` (production) · E2 naive `windowedHeartRate.m` (mean of per-window tallest peaks, 10 s/50 %) · E3 RAKF in the Task 7 native form (Eq. 12 exponent, β = 1, R0 = 25, Q = 0.03 — Task 7's implementation was already finished and reused) · extras: E4 RAKF original (division), E5 the LGI paper's own read-out (0.5–2.0 Hz, 256-sample/90 % FFT peak-pick, median over windows), E6 the Task 4 state-space tracker.
* **Reporting:** MAE (bpm) per pool for every cell (this report: all four pools). Full MAE/RMSE/r/severe-count table per cell in `results/task5_matrix_long.csv`; rank lines, gap-vs-CHROM/POS per estimator and paired sign-rank tests (MAIN_112 and v2, E1/E2/E3) in `results/task5_rank_analysis.txt`.

## Core deliverable — MAE (bpm) matrices, per pool
#### MAIN_112

| combiner (as originally tested) | E1 whole-clip FFT | E2 naive windowed | E3 RAKF native | E4 RAKF original | E5 LGI-paper read-out | E6 state-space tracker |
|---|---|---|---|---|---|---|
| CHROM (prod, wavelet) | 7.83 | 7.59 | 11.95 | 10.73 | 6.38 | 6.54 |
| POS (prod, wavelet) | 7.22 | 7.31 | 10.49 | 9.36 | 6.70 | 6.29 |
| CHROM (no wavelet) | 9.10 | 9.99 | 12.82 | 11.83 | 5.85 | 9.62 |
| POS (no wavelet) | 8.68 | 9.19 | 11.27 | 10.28 | 5.69 | 6.88 |
| GREEN (Seg4/18 form) | 14.98 | 11.94 | 18.75 | 17.08 | 11.37 | 16.58 |
| cPACE Stage1+CHROM (global q) | 8.94 | 9.28 | 12.97 | 11.84 | 5.80 | 10.41 |
| cPACE Stage1+POS (global q) | 8.68 | 9.19 | 11.27 | 10.28 | 5.69 | 6.88 |
| cPACE Full bw0.30 | 10.91 | 9.90 | 11.31 | 10.73 | 9.39 | 9.60 |
| cPACE Full bw0.15 | 9.69 | 9.66 | 10.30 | 10.02 | 9.44 | 9.46 |
| CIELab a* (orig, Seg18) | 9.53 | 9.17 | 13.28 | 12.04 | 7.60 | 13.24 |
| YCbCr Cb (orig, Seg18) | 14.90 | 13.01 | 20.98 | 19.10 | 12.94 | 19.52 |
| YCbCr Cr (orig, Seg18) | 11.92 | 9.32 | 15.94 | 14.32 | 9.74 | 15.06 |
| 2SR (Seg22, forehead box) | 9.52 | 12.38 | 15.70 | 14.46 | 7.86 | 13.39 |
| LGI projection (Seg22) | 9.24 | 8.24 | 11.48 | 10.36 | 7.76 | 9.48 |
| a* NATIVE (Task2) | 16.49 | 13.92 | 18.52 | 17.42 | 9.00 | 25.10 |
| Cb NATIVE (Task2) | 19.75 | 18.62 | 23.43 | 21.69 | 11.22 | 41.52 |
| Cr NATIVE (Task2) | 15.68 | 14.37 | 19.45 | 18.22 | 10.78 | 24.93 |
| 2SR skin-masked forehead (Task3) | 10.13 | 12.78 | 16.83 | 15.52 | 7.66 | 14.12 |
| 2SR skin-masked face (Task3) | 10.34 | 8.54 | 11.90 | 10.68 | 7.58 | 10.33 |

#### VIPL_v2_motion

| combiner (as originally tested) | E1 whole-clip FFT | E2 naive windowed | E3 RAKF native | E4 RAKF original | E5 LGI-paper read-out | E6 state-space tracker |
|---|---|---|---|---|---|---|
| CHROM (prod, wavelet) | 8.85 | 9.56 | 10.64 | 10.33 | 8.25 | 9.24 |
| POS (prod, wavelet) | 10.56 | 10.74 | 17.12 | 16.05 | 9.50 | 9.30 |
| CHROM (no wavelet) | 8.18 | 8.76 | 11.64 | 11.15 | 8.32 | 6.67 |
| POS (no wavelet) | 9.04 | 9.78 | 16.40 | 15.42 | 8.88 | 9.12 |
| GREEN (Seg4/18 form) | 21.80 | 14.95 | 21.35 | 20.03 | 18.37 | 19.41 |
| cPACE Stage1+CHROM (global q) | 10.05 | 7.79 | 11.21 | 10.73 | 8.69 | 12.94 |
| cPACE Stage1+POS (global q) | 9.04 | 9.78 | 16.40 | 15.42 | 8.88 | 9.12 |
| cPACE Full bw0.30 | 24.95 | 18.08 | 25.29 | 23.37 | 17.14 | 25.93 |
| cPACE Full bw0.15 | 16.61 | 15.98 | 15.65 | 15.76 | 16.15 | 16.51 |
| CIELab a* (orig, Seg18) | 14.51 | 13.84 | 20.00 | 18.90 | 11.54 | 18.50 |
| YCbCr Cb (orig, Seg18) | 22.05 | 17.47 | 22.13 | 21.46 | 17.78 | 20.83 |
| YCbCr Cr (orig, Seg18) | 20.52 | 18.98 | 24.23 | 23.51 | 18.83 | 19.08 |
| 2SR (Seg22, forehead box) | 21.34 | 14.66 | 18.25 | 17.19 | 15.23 | 22.79 |
| LGI projection (Seg22) | 16.93 | 13.92 | 18.84 | 17.96 | 12.28 | 21.57 |
| a* NATIVE (Task2) | 21.23 | 15.94 | 17.31 | 16.95 | 18.73 | 27.71 |
| Cb NATIVE (Task2) | 23.84 | 20.62 | 18.12 | 18.13 | 20.02 | 27.69 |
| Cr NATIVE (Task2) | 21.44 | 16.42 | 19.49 | 18.68 | 20.01 | 24.70 |
| 2SR skin-masked forehead (Task3) | 21.32 | 17.23 | 14.17 | 13.99 | 15.18 | 26.45 |
| 2SR skin-masked face (Task3) | 15.39 | 10.37 | 13.70 | 13.06 | 14.11 | 14.22 |

#### UBFC

| combiner (as originally tested) | E1 whole-clip FFT | E2 naive windowed | E3 RAKF native | E4 RAKF original | E5 LGI-paper read-out | E6 state-space tracker |
|---|---|---|---|---|---|---|
| CHROM (prod, wavelet) | 3.26 | 3.19 | 17.00 | 9.82 | 2.64 | 3.14 |
| POS (prod, wavelet) | 3.77 | 2.76 | 21.52 | 12.75 | 2.48 | 2.84 |
| CHROM (no wavelet) | 3.77 | 2.51 | 11.02 | 4.95 | 2.48 | 3.14 |
| POS (no wavelet) | 3.77 | 1.66 | 11.01 | 5.01 | 2.48 | 3.14 |
| GREEN (Seg4/18 form) | 12.56 | 11.23 | 40.68 | 32.22 | 15.34 | 7.93 |
| cPACE Stage1+CHROM (global q) | 3.77 | 1.84 | 10.96 | 5.48 | 2.48 | 2.54 |
| cPACE Stage1+POS (global q) | 3.77 | 1.66 | 11.01 | 5.01 | 2.48 | 3.14 |
| cPACE Full bw0.30 | 2.44 | 2.82 | 5.62 | 3.62 | 4.25 | 3.77 |
| cPACE Full bw0.15 | 3.18 | 2.93 | 2.76 | 3.03 | 2.81 | 2.87 |
| CIELab a* (orig, Seg18) | 3.70 | 3.38 | 20.69 | 12.84 | 2.81 | 2.84 |
| YCbCr Cb (orig, Seg18) | 17.98 | 6.54 | 36.66 | 26.85 | 11.82 | 7.40 |
| YCbCr Cr (orig, Seg18) | 12.15 | 6.05 | 27.08 | 19.37 | 8.18 | 3.47 |
| 2SR (Seg22, forehead box) | 3.57 | 4.12 | 11.48 | 5.90 | 3.01 | 3.13 |
| LGI projection (Seg22) | 2.65 | 6.04 | 17.39 | 12.03 | 4.83 | 3.77 |
| a* NATIVE (Task2) | 18.92 | 6.98 | 18.94 | 15.66 | 16.35 | 21.13 |
| Cb NATIVE (Task2) | 16.88 | 11.65 | 16.54 | 12.42 | 15.34 | 22.67 |
| Cr NATIVE (Task2) | 18.92 | 10.19 | 23.82 | 18.99 | 16.68 | 30.43 |
| 2SR skin-masked forehead (Task3) | 2.85 | 3.42 | 10.76 | 4.79 | 3.34 | 4.03 |
| 2SR skin-masked face (Task3) | 13.80 | 7.42 | 23.63 | 12.45 | 4.35 | 4.27 |

#### VIPL_v1

| combiner (as originally tested) | E1 whole-clip FFT | E2 naive windowed | E3 RAKF native | E4 RAKF original | E5 LGI-paper read-out | E6 state-space tracker |
|---|---|---|---|---|---|---|
| CHROM (prod, wavelet) | 8.05 | 7.79 | 11.71 | 10.77 | 6.55 | 6.70 |
| POS (prod, wavelet) | 7.38 | 7.52 | 9.97 | 9.20 | 6.89 | 6.45 |
| CHROM (no wavelet) | 9.35 | 10.34 | 12.90 | 12.15 | 6.01 | 9.93 |
| POS (no wavelet) | 8.91 | 9.54 | 11.28 | 10.53 | 5.84 | 7.06 |
| GREEN (Seg4/18 form) | 15.10 | 11.97 | 17.73 | 16.38 | 11.18 | 16.98 |
| cPACE Stage1+CHROM (global q) | 9.18 | 9.63 | 13.07 | 12.14 | 5.96 | 10.78 |
| cPACE Stage1+POS (global q) | 8.91 | 9.54 | 11.28 | 10.53 | 5.84 | 7.06 |
| cPACE Full bw0.30 | 11.30 | 10.24 | 11.57 | 11.06 | 9.63 | 9.87 |
| cPACE Full bw0.15 | 9.99 | 9.97 | 10.65 | 10.35 | 9.75 | 9.77 |
| CIELab a* (orig, Seg18) | 9.80 | 9.44 | 12.94 | 12.00 | 7.82 | 13.72 |
| YCbCr Cb (orig, Seg18) | 14.76 | 13.31 | 20.24 | 18.73 | 12.99 | 20.08 |
| YCbCr Cr (orig, Seg18) | 11.91 | 9.47 | 15.42 | 14.09 | 9.81 | 15.60 |
| 2SR (Seg22, forehead box) | 9.79 | 12.76 | 15.90 | 14.86 | 8.09 | 13.87 |
| LGI projection (Seg22) | 9.55 | 8.34 | 11.20 | 10.28 | 7.90 | 9.74 |
| a* NATIVE (Task2) | 16.37 | 14.25 | 18.50 | 17.50 | 8.66 | 25.28 |
| Cb NATIVE (Task2) | 19.89 | 18.94 | 23.75 | 22.12 | 11.02 | 42.41 |
| Cr NATIVE (Task2) | 15.53 | 14.57 | 19.25 | 18.19 | 10.51 | 24.67 |
| 2SR skin-masked forehead (Task3) | 10.47 | 13.22 | 17.12 | 16.02 | 7.87 | 14.59 |
| 2SR skin-masked face (Task3) | 10.18 | 8.59 | 11.35 | 10.60 | 7.73 | 10.61 |

## What the matrix shows
1. **No challenger beats production CHROM/POS under the same read-out on MAIN_112 in any way that matters.** Cells where a challenger's MAE is nominally below CHROM's *under the same read-out* are only: (a) **same-family variants** — CHROM/POS without wavelet, cPACE Stage 1 + POS (algebraically identical to POS no-wavelet) — under E5, e.g. CHROM no-wavelet 5.85 / POS no-wavelet 5.69 vs production 6.38 / 6.70; (b) the **RAKF columns (E3/E4)**, where CHROM itself is badly degraded (≥ 10 bpm) and a few challengers are 0.05–1.7 bpm "better": cPACE Full bw 0.15 10.30 vs 11.95 (paired 35 better / 33 worse, p = 0.48), LGI 11.48 vs 11.95 (16 / 23, p = 0.40), masked-face 2SR 11.90 vs 11.95 (43 / 27, p = 0.19). None is significant, and an estimator that makes *everything* worse than a whole-clip FFT is not evidence about signal quality.
2. **The read-out moves every row together.** E5 (0.5–2 Hz, windowed median) lowers MAE on MAIN_112 for almost every combiner (CHROM 7.83 → 6.38; a* orig 9.53 → 7.60; LGI 9.24 → 7.76; 2SR 9.52 → 7.86; native a* 16.49 → 9.00), and E3/E4 raise it for almost every combiner (the exception is cPACE Full bw 0.30 under E4, 10.91 → 10.73). The gap of each challenger to CHROM under the *same* read-out keeps its sign across E1, E2, E5, E6 on MAIN_112 (e.g. a* orig vs CHROM: +1.70 / +1.58 / +1.22 / +6.7; LGI: +1.40 / +0.65 / +1.39 / +2.94). The one place a challenger looks "competitive" is a **cross-read-out** comparison (a* under E5 = 7.60 vs CHROM under E1 = 7.83) — that compares different read-outs and is exactly the illusion this task exists to expose: under E5 CHROM is 6.38.
3. **Rank moves are within the incumbent family.** MAIN_112 rank 1 is production POS under E1, E4 and E6, POS no-wavelet under E5 (ranks 2–4 there: cPACE Stage 1 + POS, cPACE Stage 1 + CHROM, CHROM no-wavelet — all CHROM/POS-derived), and cPACE Full bw 0.15 under E3 (the read-out that degrades everything). The first non-CHROM/POS-derived combiner under E1 is LGI (rank 7 of 19) and under E5 it is the skin-masked-face 2SR (rank 7), then a* (rank 8).
4. **Motion pool (N = 20, weakest evidence).** CHROM no-wavelet under the tracker (E6) is the best cell (6.67), and cPACE Stage 1 + CHROM under E2 is 7.79 vs POS 10.74 (12 better / 3 worse, p = 0.044) — one nominally significant cell out of ~60 tests on N = 20, which a multiple-comparison correction would remove; it is CHROM with a projection, not a new combiner. Every distinct challenger (2SR, LGI, a*, cPACE Full) stays 5–15 bpm behind under all E1/E2/E5/E6 read-outs on v2 (e.g. native a* 15.9–27.7, 2SR 14.7–22.8, LGI 12.3–21.6 vs CHROM 8.3–9.6).
5. **UBFC (N = 5) is uninformative** (everything is 2.5–4 bpm except GREEN/Cb/Cr/native a*); the VIPL-v1 matrix is nearly the MAIN_112 one (107 of the 112 subjects).
6. **RAKF (E3, native form) is the worst read-out for essentially every combiner** (CHROM 11.95, POS 10.49) — Task 7's finding re-confirmed across 19 different pulse signals, not just CHROM.

## Caveats
* Read-outs E5/E6 were not designed for these signals — E5's 0.5–2.0 Hz cap is a ≤ 120 bpm prior (which flatters resting-heart-rate pools, and hurts the UBFC after-exercise clip), E6's constants are a-priori, untuned settings — so the matrix answers "does the read-out change the *rank*?", not "which read-out is best". The E5/E6 gains for the incumbents are a candidate for held-out validation, not a result to promote.
* Several combiners' cells are near-duplicates by construction (cPACE Stage 1 + POS ≡ POS no-wavelet); they are listed for completeness and should not be counted as independent evidence.
* Paired tests are exploratory (≈ 19 combiners × 3 estimators × 2 pools × 2 references); only the pattern, not any single p-value, is being read.

**Verdict line: Estimator-swap audit — earlier challenger "losses" are NOT read-out artefacts; no verdict changes. Read-out-stage improvement for CHROM/POS recorded as a CANDIDATE.**

## Protected-files verification
See `../common/protected_files_verification.txt`: 18/18 protected production files byte-identical before vs after Segment 23 (SHA-256).

## Outputs
`scripts/run_task5_estimator_swap.m`, `results/task5_matrix_long.csv`, `results/task5_MAE_matrix_{MAIN_112,UBFC,VIPL_v1,VIPL_v2_motion}.csv`, `results/task5_rank_analysis.txt`, `results/task5_HR_cube.mat`.
