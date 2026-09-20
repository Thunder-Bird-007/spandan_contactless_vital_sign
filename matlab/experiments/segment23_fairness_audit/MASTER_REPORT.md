# Segment 23 — Fairness / native-form audit: MASTER REPORT

Question: is CHROM/POS's unbroken record (Segments 6, 7, 9, 18, 21, 22) **real robustness**, or an artefact of every challenger being tested in a simplified/partial form while CHROM/POS carries 8 segments of tuning?

## The direct answer

**Mostly real robustness, with a real but modest tuning/read-out asymmetry that does not change any ranking. It is not a fairness artefact of incomplete challenger implementations.**

* Every challenger that was re-run in its native or completed form (cPACE with windowed q̂ — T1; CIELab a* with the paper's ROI/KLT/transform — T2; 2SR with a real skin mask — T3; LGI with its own read-out and a state-space tracker — T4; RAKF with the Eq. 12 exponent — T7) **still loses**, and three of the five native forms are *worse* than the earlier simplified test (native a* 16.5 vs 9.5 bpm; RAKF 11.95 vs 10.73; masked-forehead 2SR 10.1 vs 9.5). Where a completion did help (2SR on the whole face instead of the forehead, on the motion pool: 21.3 → 15.4 bpm), it still trails CHROM (8.85) and POS (10.56) by 5–7 bpm. Supported by T1, T2, T3, T4, T7.
* The estimator-swap matrix (T5, 19 combiners × 6 read-outs, per pool) shows **no challenger beats production CHROM/POS under the same read-out** on MAIN_112 (the only nominal exceptions are same-family CHROM/POS variants, or read-outs — RAKF — that wreck everything). Read-outs move all rows together, so "the loss was a read-out artefact" is rejected.
* The tuning asymmetry is **real but small and not per-subject significant** (T6): stripping the wavelet stage alone costs CHROM/POS 1.3–1.5 bpm pooled MAE (roughly the size of their pooled-MAE margin over the challengers), fully native windowed forms cost 3–4 bpm pooled MAE — but paired per subject on MAIN_112 **no de-tuned variant is distinguishable from production (all p ≥ 0.08)** and a 0.7–2.5 Hz band restores or beats production. So CHROM/POS is configuration-sensitive in the pooled numbers and statistically robust per subject — "some of both", leaning robust.
* **How strong is the incumbents' lead, honestly?** On the main pool (MAIN_112), the closest challengers (a*, 2SR, LGI, masked 2SR) are 1.4–2.5 bpm behind on pooled MAE but **not significantly worse than CHROM per subject** (paired p = 0.07–0.36; still worse than POS at p ≈ 0.02–0.08 for a*/2SR/LGI); only cPACE Full and native a* are clearly worse (p ≤ 0.04). On the motion pool (N = 20) CHROM significantly beats 2SR (p = 0.010), LGI (p = 0.016) and cPACE Full bw 0.15 (p = 0.018). So the evidence for "CHROM/POS ≥ everything tested" is solid; the evidence for "CHROM/POS ≫ the best challengers on ordinary resting data" is weaker than the pooled-MAE column suggests.
* **The largest lever found in this segment is neither a combiner nor tuning of the combiner — it is the HR read-out** (T4/T5/T7): a windowed peak read-out (0.5–2 Hz, 256-sample/90 %) or a frequency-state tracker lowers MAIN_112 MAE of the *incumbents* by 1.1–1.5 bpm (CHROM 7.83 → 6.38 / 6.54, POS 7.22 → 6.70 / 6.29; RMSE 11.9 → 9.1 / 8.8). That is a **CANDIDATE** for held-out validation (UBFC-D2 is available), confounded by the band prior it carries; **nothing was promoted.**

## Master table — every combiner / method in the project's history (best-known configuration)

Cells: MAE (bpm) / RMSE (bpm) / Pearson r. MAIN_112 = the 5 UBFC + 107 VIPL v1 subjects; the per-pool columns are always shown next to it (never pooled only). The motion pool (VIPL v2, N = 20) is separate and smaller than the rest; UBFC (N = 5) is not evidence on its own. Severe-error counts, other read-outs and every cell of the full matrix: `task5_estimator_swap_audit/results/task5_matrix_long.csv`.

| method (best-known config) | re-tested native this segment? | verdict changed? | MAIN_112 (UBFC+VIPL v1) MAE / RMSE / r | UBFC (5) | VIPL v1 (107) | VIPL v2 motion (20) |
|---|---|---|---|---|---|---|
| CHROM (production, wavelet, whole-clip FFT) | no (reference; T6 de-tuned it) | unchanged | 7.83 / 11.87 / 0.53 | 3.26 / 5.05 / 0.96 | 8.05 / 12.09 / 0.48 | 8.85 / 12.64 / 0.54 |
| POS (production, wavelet, whole-clip FFT) | no (reference; T6 de-tuned it) | unchanged | 7.22 / 10.85 / 0.62 | 3.77 / 6.15 / 0.94 | 7.38 / 11.02 / 0.58 | 10.56 / 16.06 / 0.31 |
| CHROM, native windowed form (T6 L4) | YES (T6) | No — pooled MAE worse, per-subject n.s. | 10.88 / 21.78 / 0.19 | 3.16 / 4.84 / 0.97 | 11.24 / 22.26 / 0.15 | 9.17 / 14.85 / 0.42 |
| POS, native windowed Algorithm 1 (T6 L4) | YES (T6) | No — pooled MAE worse, per-subject n.s. | 11.45 / 24.85 / 0.08 | 3.16 / 4.84 / 0.97 | 11.84 / 25.41 / 0.01 | 15.42 / 21.40 / 0.16 |
| GREEN | no | unchanged | 14.98 / 19.49 / 0.09 | 12.56 / 18.88 / 0.29 | 15.10 / 19.52 / 0.03 | 21.80 / 24.97 / -0.21 |
| cPACE Stage 1 + CHROM (global q̂, no wavelet) | YES (T1: windowed q̂) | No — windowed q̂ ≈ null | 8.94 / 18.50 / 0.29 | 3.77 / 6.15 / 0.94 | 9.18 / 18.88 / 0.24 | 10.05 / 15.49 / 0.36 |
| cPACE Stage 1 + POS (exact no-op with global q̂) | YES (T1) | No | 8.68 / 16.45 / 0.28 | 3.77 / 6.15 / 0.94 | 8.91 / 16.78 / 0.22 | 9.04 / 14.86 / 0.41 |
| cPACE Full bw 0.30 (no wavelet) | YES (T1: windowed q̂) | No — still loses | 10.91 / 15.29 / 0.45 | 2.44 / 3.66 / 0.98 | 11.30 / 15.62 / 0.35 | 24.95 / 44.16 / -0.18 |
| cPACE Full bw 0.15 (no wavelet) | YES (T1: windowed q̂) | No — still loses | 9.69 / 14.40 / 0.46 | 3.18 / 4.50 / 0.99 | 9.99 / 14.70 / 0.38 | 16.61 / 22.19 / -0.05 |
| CIELab a* — as tested (Seg 18) | baseline for T2 | unchanged | 9.53 / 14.59 / 0.43 | 3.70 / 6.15 / 0.95 | 9.80 / 14.87 / 0.35 | 14.51 / 20.13 / 0.11 |
| YCbCr Cb — as tested | baseline for T2 | unchanged | 14.90 / 19.76 / 0.13 | 17.98 / 22.40 / 0.88 | 14.76 / 19.63 / 0.04 | 22.05 / 25.66 / -0.39 |
| YCbCr Cr — as tested | baseline for T2 | unchanged | 11.92 / 16.59 / 0.32 | 12.15 / 20.47 / 0.40 | 11.91 / 16.39 / 0.28 | 20.52 / 23.27 / -0.23 |
| CIELab a* — NATIVE pipeline (Yang 2016) | YES (T2) | No — worse than as-tested | 16.49 / 26.40 / 0.16 | 18.92 / 23.21 / 0.43 | 16.37 / 26.54 / 0.16 | 21.23 / 25.79 / -0.10 |
| YCbCr Cb — NATIVE | YES (T2) | No | 19.75 / 30.16 / 0.13 | 16.88 / 23.11 / 0.45 | 19.89 / 30.45 / 0.13 | 23.84 / 29.02 / -0.28 |
| YCbCr Cr — NATIVE | YES (T2) | No | 15.68 / 23.67 / 0.17 | 18.92 / 23.21 / 0.43 | 15.53 / 23.69 / 0.15 | 21.44 / 24.70 / 0.23 |
| 2SR — forehead box (Seg 22) | baseline for T3 | unchanged | 9.52 / 14.23 / 0.39 | 3.57 / 6.01 / 0.91 | 9.79 / 14.50 / 0.31 | 21.34 / 26.51 / -0.18 |
| 2SR — skin-masked forehead box | YES (T3) | No | 10.13 / 18.91 / 0.20 | 2.85 / 4.64 / 0.96 | 10.47 / 19.32 / 0.12 | 21.32 / 27.86 / 0.07 |
| 2SR — skin-masked whole face | YES (T3) | No — helps on motion, still loses | 10.34 / 18.32 / 0.31 | 13.80 / 17.17 / 0.59 | 10.18 / 18.37 / 0.24 | 15.39 / 22.12 / -0.10 |
| LGI projection + whole-clip FFT (Seg 22) | baseline for T4 | unchanged | 9.24 / 14.06 / 0.46 | 2.65 / 3.77 / 0.98 | 9.55 / 14.37 / 0.38 | 16.93 / 22.24 / -0.12 |
| LGI + paper read-out (256/90 %, 0.5–2 Hz) | YES (T4/T5) | No — CHROM/POS gain equally | 7.76 / 11.06 / 0.60 | 4.83 / 8.97 / 0.84 | 7.90 / 11.15 / 0.52 | 12.28 / 17.06 / 0.13 |
| LGI + state-space tracker | YES (T4/T5) | No — tracker does not help LGI | 9.48 / 15.62 / 0.38 | 3.77 / 5.72 / 0.94 | 9.74 / 15.93 / 0.30 | 21.57 / 32.62 / -0.06 |
| CHROM + paper windowed read-out | YES (T4/T5) | CANDIDATE read-out (not promoted) | 6.38 / 9.10 / 0.64 | 2.64 / 4.82 / 0.97 | 6.55 / 9.25 / 0.56 | 8.25 / 11.47 / 0.53 |
| POS + paper windowed read-out | YES (T4/T5) | CANDIDATE read-out (not promoted) | 6.70 / 9.34 / 0.63 | 2.48 / 4.45 / 0.98 | 6.89 / 9.51 / 0.54 | 9.50 / 12.64 / 0.50 |
| CHROM + state-space tracker | YES (T4/T5) | CANDIDATE read-out (not promoted) | 6.54 / 8.77 / 0.68 | 3.14 / 4.49 / 0.98 | 6.70 / 8.92 / 0.62 | 9.24 / 12.40 / 0.30 |
| POS + state-space tracker | YES (T4/T5) | CANDIDATE read-out (not promoted) | 6.29 / 8.41 / 0.69 | 2.84 / 4.44 / 0.97 | 6.45 / 8.55 / 0.62 | 9.30 / 14.91 / 0.28 |
| naive windowed HR, CHROM (no smoothing) | YES (T5/T7, wavelet chain) | Still not adopted (beats whole-clip on MAIN_112, not on v2) | 7.59 / 10.32 / 0.55 | 3.19 / 4.40 / 0.99 | 7.79 / 10.52 / 0.48 | 9.56 / 12.08 / 0.31 |
| naive windowed HR, POS | YES (T5/T7) | same | 7.31 / 10.09 / 0.55 | 2.76 / 4.09 / 0.99 | 7.52 / 10.29 / 0.47 | 10.74 / 13.84 / 0.36 |
| RAKF original (division), CHROM | baseline for T7 | unchanged | 10.73 / 17.14 / 0.34 | 9.82 / 14.73 / 0.50 | 10.77 / 17.25 / 0.34 | 10.33 / 15.06 / 0.20 |
| RAKF NATIVE (Eq. 12 exponent, β=1), CHROM | YES (T7) | No — slightly worse than division form | 11.95 / 19.28 / 0.28 | 17.00 / 25.55 / -0.05 | 11.71 / 18.94 / 0.32 | 10.64 / 16.04 / 0.19 |
| RAKF NATIVE, POS | YES (T7) | No | 10.49 / 14.76 / 0.31 | 21.52 / 28.10 / -0.12 | 9.97 / 13.83 / 0.37 | 17.12 / 22.94 / 0.05 |
| whole-clip CHROM, Seg 6 pre-wavelet data (reference for next 3 rows) | no (not part of this segment; VIPL-107 only, pre-wavelet) | unchanged | n/a | n/a | 9.35 / 18.37 / 0.28 | n/a |
| gating only (Seg 6 Task P, VIPL-107 only) | no (not part of this segment; VIPL-107 only, pre-wavelet) | unchanged | n/a | n/a | 10.38 / 15.66 / 0.32 | n/a |
| gating + window-1 continuity (Task P) | no (not part of this segment; VIPL-107 only, pre-wavelet) | unchanged | n/a | n/a | 12.47 / 21.58 / 0.24 | n/a |
| gating + anchored continuity (Task Q) | no (not part of this segment; VIPL-107 only, pre-wavelet) | unchanged | n/a | n/a | 10.62 / 19.42 / 0.21 | n/a |

"Best-known" = the configuration listed; for challengers the *as-tested and native* forms are on adjacent rows so the retest effect is visible. The last four rows (gating/continuity, Segment 6 Tasks P/Q) were **not** re-run — they exist only for VIPL-107 on the pre-wavelet chain; shown for completeness, not re-tested.

## Which task supports which conclusion

| conclusion | supported by | strength |
|---|---|---|
| Challengers do not lose because they were tested simplified: completed/native forms still lose | T1, T2, T3, T4, T7 (each with a regression check against the earlier result — all exact) | strong on MAIN_112 pooled MAE; weaker per subject vs CHROM (p 0.07–0.36) except cPACE Full / native a* |
| Losses are not read-out artefacts | T5 (19 × 6, per pool), T4 | strong: gaps keep sign under E1/E2/E5/E6 |
| De-tuning CHROM/POS moves pooled MAE by 1.3–4 bpm but not per subject | T6 | moderate; some T6 rungs were added after seeing the first result (exploratory) |
| RAKF's Eq. 12 bug was not why it lost | T7 | strong: exponent form is slightly worse (p < 0.0001 vs the division form, MAIN_112) |
| Read-out stage is a bigger lever than the combiner | T4, T5 (T7 corroborates: RAKF worst) | moderate; confounded by the 0.5–2 Hz band prior; no held-out check |
| Forehead-box "non-skin contamination" premise was mostly false here | T3 (median 97 % skin; masking does not help 2SR) | moderate (one colour rule, no visual audit) |

## Corrections to the Segment 23 brief found by reading the primary sources (recorded so they are not rediscovered)

1. **Yang et al. 2016:** cells are 20×20 px; 120×80 px is the *selected ROI* (T2).
2. **Kaur et al.:** the paper does **not** specify a sliding-window q̂ — q̂ is a static per-ROI mean-direction; windowed q̂ was tested as a fairness hypothesis, not a native form (T1).
3. **Pilz et al.:** the paper's own benchmark read-out is a 256-sample / 90 %-overlap FFT peak-pick, **not** the state-space tracker, which is the modelling framework with no numeric parameters given (T4).
4. **Debnath & Kim:** no numeric β is given anywhere; only R0 = 25 and Q = 2×10⁻⁴; the paper's RAKF also includes Eq. 14 and Eq. 15–17, which this project's port has never had (T7).
5. **de Haan & Jeanne (CHROM):** primary text unreadable from this environment (BLOCKED); "native CHROM" uses the McDuff iphys reference values as a secondary source (T6).
6. **Segment 22's 2SR used a forehead-only region**, unfairly small for 2SR on the motion pool; widening to the face closes part of the gap (T3) — a genuine fairness gap in the earlier record, still not enough to beat CHROM/POS.

## Honest limitations of this segment

* Pools: UBFC N = 5 and VIPL v2 N = 20 cannot carry claims alone; MAIN_112 is 95 % VIPL v1. Held-out data (UBFC-D2) was **not** used anywhere in this segment.
* Multiple comparisons: Tasks 5/6 report dozens of paired tests; read patterns, not single p-values.
* Not done: cumulative-loss reading of KLT pruning and any threshold sensitivity (T2 — pruning was inert under the per-frame reading); ROI overlays were not inspected (T2's explanation of the ROI loss is a hypothesis); one skin-mask rule, no HSV/learned variant (T3); tracker constants untuned by design (T4); the paper's full per-frame RAKF (T7); as-tested a* and 2SR were not re-run with production's wavelet stage except T2 A3w and T3 waveletOut (neither beat production); challengers were not re-tuned per method (that would be the fishing this segment forbids).
* T6's diagnostic rungs (L4b–L5) were added after L4's poor result; their apparent advantage is exploratory.
* No production file was modified: 18/18 protected production files byte-identical before vs after Segment 23 (SHA-256). (details: `common/protected_files_verification.txt`).

## Recommended follow-ups (not started)

1. Held-out validation (UBFC-D2, 33 valid subjects) of the windowed/tracked read-out for CHROM/POS — the only new candidate this segment produced.
2. If challengers keep being tested, use the motion pool with a larger N; MAIN_112 cannot separate the top group.
