# Segment 23 Task 3 — 2SR with a real skin mask (Wang, Stuijk & de Haan, IEEE TBME 63(9):1974, 2016)

**Verdict: EVALUATED, NOT ADOPTED — unchanged.** With a real per-pixel skin/non-skin decision the premise behind the brief ("a fixed box over a moving face includes lots of hair/background")
turns out to be **mostly false for this dataset**, and masking does not rescue 2SR: on MAIN_112 it is not better, on the motion pool it is better only when the region is widened to the whole face, and
even then still far behind production CHROM/POS.

**Scheduling: HEAVY (verified)** — per-frame pixel masking needs frame-level access. One video pass over all 132 videos (5 UBFC + 107 VIPL v1 + 20 VIPL v2), 0 failures, 0 parity mismatches (unmasked forehead-box mean RGB and 3×3 correlation matrices are identical to Segment 22's `seg22cov` cache on all 132 subjects). Run concurrently with Task 2's decode after checking capacity (per-video times unchanged, RAM headroom ≥ 4 GB) — the brief permitted this only if neither job starved.

## Method
* `src/skinMaskExtract.m`: per frame, a genuine pixel-level skin rule — **Chai & Ngan YCbCr rule (full-range: 77 ≤ Cb ≤ 127, 133 ≤ Cr ≤ 173) plus 30 ≤ Y ≤ 245** — fixed a priori, never tuned. Four pixel sets, each reduced per frame to mean RGB and the 3×3 uncentered correlation matrix (all 2SR consumes): `fbMask` (production forehead box ∩ skin), `fbUnmask` (Segment 22's set), `faceMask` (whole face box ∩ skin — the 2SR paper's own "skin pixels" setting), `faceUnmask` (isolates region size from masking). A frame keeping < 50 skin pixels falls back to that region's unmasked pixels and is counted (`fallback`).
* 2SR = the existing `spatialSubspaceRotation.m` (unchanged). **Primary stride = Segment 22's dev-set selection (2.0 s)**, so only the pixel set changes; the whole stride grid is also reported but nothing is selected on it. Same-pixel CHROM/POS (production wavelet chain) on each set's mean RGB are reported too, so any effect of masking on the incumbents is visible.
* **Regression check (passed, exact): `fbUnmask` 2SR @ 2.0 s reproduces Segment 22's `HR_2sr_sel` — max |ΔHR| = 0.0000 bpm, n=132.**

## How contaminated was the fixed box, really? (tests the brief's premise)
Skin fraction inside the production forehead box (fraction of pixels the mask keeps): **median 0.97, IQR [0.88, 1.00]; only 14 / 132 subjects had > 30 % non-skin** (the 2SR paper's stated degradation zone is 10–30 %). Face-box median 0.69. Spearman(non-skin fraction in the box, 2SR improvement from masking) = 0.072 (p = 0.45): the subjects with the dirtiest boxes are *not* the ones masking helps. Caveat: this is a colour-threshold mask; a colour rule can call hair/shadow "skin" and can call a yellow-cast forehead "non-skin" (one UBFC clip kept only 6 % of its box, with fallback on 10 frames), so 0.97 is a *lower bound on contamination detectability*, not a proof of purity.

## Results — MAE / RMSE / r / severe(>10 bpm)/n, per pool (2SR at the primary 2.0 s stride unless stated)
| pixel set / method | UBFC (5) | VIPL v1 (107) | MAIN_112 | VIPL v2 motion (20) |
|---|---|---|---|---|
| 2SR fbUnmask (Segment 22) | 3.57 / 6.01 / 0.91 / 1 | 9.79 / 14.50 / 0.31 / 37 | 9.52 / 14.23 / 0.39 / 38 | 21.34 / 26.51 / −0.18 / 14 |
| **2SR fbMask** | 2.85 / 4.64 / 0.96 / 1 | 10.47 / 19.32 / 0.12 / 36 | **10.13 / 18.91 / 0.20 / 37** | 21.32 / 27.86 / 0.07 / 13 |
| 2SR faceUnmask | 7.44 / 9.05 / 0.77 / 2 | 11.09 / 16.40 / 0.22 / 42 | 10.92 / 16.14 / 0.30 / 44 | 14.91 / 19.07 / 0.18 / 10 |
| **2SR faceMask** | 13.80 / 17.17 / 0.59 / 3 | 10.18 / 18.37 / 0.24 / 35 | **10.34 / 18.32 / 0.31 / 38** | **15.39 / 22.12 / −0.10 / 10** |
| CHROM (fbUnmask = production) | 3.26 / 5.05 / 0.96 / 1 | 8.05 / 12.09 / 0.48 / 31 | 7.83 / 11.87 / 0.53 / 32 | 8.85 / 12.64 / 0.54 / 7 |
| POS (fbUnmask = production) | 3.77 / 6.15 / 0.94 / 1 | 7.38 / 11.02 / 0.58 / 29 | 7.22 / 10.85 / 0.62 / 30 | 10.56 / 16.06 / 0.31 / 6 |
| CHROM on fbMask / faceMask | 4.06 / 6.23 / 0.98 / 1 ; 6.35 / 8.13 / 0.86 / 2 | 8.79 / 14.36 / 0.30 / 35 ; 9.21 / 13.36 / 0.43 / 34 | 8.57 / 14.10 / 0.38 / 36 ; 9.08 / 13.17 / 0.53 / 36 | 9.09 / 12.92 / 0.55 / 7 ; 8.18 / 11.86 / 0.56 / 5 |
| POS on fbMask / faceMask | 6.14 / 8.09 / 0.90 / 2 ; 8.20 / 11.24 / 0.81 / 2 | 9.83 / 15.48 / 0.24 / 39 ; 8.98 / 12.71 / 0.53 / 36 | 9.66 / 15.23 / 0.32 / 41 ; 8.94 / 12.65 / 0.59 / 38 | 10.96 / 16.08 / 0.39 / 8 ; 8.63 / 15.23 / 0.43 / 4 |

Stride grid, **not selected on** (MAIN_112 / v2 MAE): fbMask 0.5 s 8.71 / 13.90, 1.0 s 14.83 / 17.50, 1-frame 35.90 / 28.95; fbUnmask 0.5 s 9.80 / 16.53; faceMask 0.5 s 9.20 / 12.57, 1.0 s 9.72 / 11.36. (2SR is very stride-sensitive; the best cell, fbMask @ 0.5 s = 8.71 on MAIN_112, still trails CHROM 7.83 / POS 7.22 and was not chosen in advance.)

Paired per-subject vs Segment 22's 2SR (2.0 s; >1 bpm better/worse; sign-rank): fbMask — MAIN_112 10 / 6, 4 severe-worse (p=0.44); v2 4 / 7 (p=0.90). faceMask — MAIN_112 24 / 23, 11 severe (p=0.95); **v2 13 / 3, 2 severe (p=0.062)**. faceUnmask — MAIN_112 27 / 37, 18 severe (p=0.17); v2 13 / 4 (p=0.062).

## Interpretation
* **Masking alone does not help 2SR** (forehead box: MAIN_112 9.52 → 10.13, not significant, and RMSE worse: 14.2 → 18.9). The masked forehead box also hurts CHROM/POS (7.83 → 8.57; 7.22 → 9.66), i.e. removing pixels lowers spatial averaging and adds noise even where the pixels were "non-skin".
* **On the motion pool the face-wide region is what helps 2SR** (21.3 → 14.9 unmasked / 15.4 masked; 13 better vs 3–4 worse, p=0.062 — borderline, N=20), with masking itself adding nothing over the wider box. That matches the 2SR paper's own preference for whole-face skin pixels, and shows Segment 22's forehead-only box was an unfairly small region for 2SR on the motion pool — **a genuine fairness gap, now closed, and 2SR still loses**: 15.4 vs CHROM 8.85 / POS 10.56 on v2, and 10.3 vs 7.83 / 7.22 on MAIN_112.
* On the face-wide region the *incumbents* are not hurt on v2 (CHROM 8.18 face vs 8.85 box), but are clearly hurt on MAIN_112 (CHROM faceUnmask 11.45): the box that is best for CHROM/POS is not the box that is best for 2SR, which supports region choice being a per-method design parameter rather than an incumbent-favouring accident.
* Caveats: the mask is one fixed colour rule (no HSV/learned variant, no sensitivity sweep), stride selection came from Segment 22's dev set for a forehead-box pixel set (it may not be optimal for face-wide sets — see the un-selected grid), v2 N=20, and per-video mask quality was not visually audited.

**Verdict line: 2SR with a real skin mask — EVALUATED, NOT ADOPTED. Fairness gap (forehead-only region on the motion pool) found and closed; verdict unchanged.**

## Protected-files verification
See `../common/protected_files_verification.txt`: 18/18 protected production files byte-identical before vs after Segment 23 (SHA-256).

## Outputs
`src/skinMaskExtract.m`, `scripts/run_task3_extract.m` (cache `data/processed/seg23t3_<id>.mat`, 132 files), `scripts/run_task3_eval.m`, `results/task3_summary_by_pool.csv`, `results/task3_per_subject.csv`.
