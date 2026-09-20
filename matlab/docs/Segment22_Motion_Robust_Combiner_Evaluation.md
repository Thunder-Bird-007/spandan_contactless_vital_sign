# Segment 22 — 2SR and LGI-projection vs production CHROM/POS, stratified

Run 2026-09-20. Follows `Segment21_Motion_Robust_Combiner_Literature_Search.md` §6.
**Verdict: NO-GO for both 2SR and LGI-projection. Nothing promoted; CHROM/POS untouched.**
The state-space LGI tracker was not staged (see §4).

## 1. Tier 0 — production CHROM/POS on the VIPL v2 motion pool (first time measured)

Production chain = Segment 8's wavelet default. Re-derived chain reproduces
`segment8_task4_wavelet_ablation.csv` on the 112-subject pool with max diff 0.0000 bpm.

| Pool | CHROM MAE / r | POS MAE / r |
|---|---|---|
| v2 motion (N=20) | **8.85** / 0.54 | **10.57** / 0.31 |
| same 20 persons, v1 stable | 8.90 / 0.64 | 8.54 / 0.68 |

Production CHROM barely degrades under large head motion on this pool (POS degrades ~2 bpm).
Segment 18's "motion collapse" (green 21.8, a\* 14.5 bpm) was a **single-channel** effect;
the production bar on v2 is already ~8.9 bpm, which is what 2SR/LGI had to beat.

## 2. Method notes

- `roi/extractROICovariance.m` (new): same detector/geometry as `extractROISignals.m`, forehead ROI,
  additionally stores the per-frame 3×3 pixel correlation matrix. 132 videos re-decoded once.
  R/G/B are **bit-identical** to the cached production traces (0 parity mismatches, 0 failures).
- `pulseextraction/spatialSubspaceRotation.m` (new, additive): follows the authors' reference MATLAB
  (per-frame eig, rotation × scale terms, back-projection, windowed σ-tuning, overlap-add), with a
  configurable stride. One deviation: eigenvector sign of u1 is fixed (positive sum) since the
  reference leaves it arbitrary.
- `pulseextraction/lgiProjection.m` (new, additive): SVD first-singular-vector projection, green row
  (pyVHR-style). Run after the same wavelet pre-step as production.
- **ROI caveat (paper's own):** 2SR wants a skin mask; the forehead box is a fixed crop. Same pixels as
  CHROM/POS on purpose, so this is a like-for-like test, but 2SR may be handicapped vs. a masked ROI.
- **Held-out design:** 2SR stride selected on a dev set = main-pool subjects whose person is not in the
  v2 pool (N=92). Held-out = the 20 v2 rows + those persons' v1 rows (N=40). LGI has no tunable.
- **Disclosed deviation:** stride grid was {0.5, 1, 2 s} on the first run; after seeing a comb-filter
  failure at 1 s (dev MAE 15.8 vs ~9.1) the reference's own 1-frame stride was added. It scored 35.6 bpm
  (adjacent-frame differencing amplifies noise). Selection still uses dev only; selected stride = 2.0 s.
  Frame-pair differencing acts as a comb filter (nulls at multiples of 1/stride), a structural weakness.

## 3. Results (MAE bpm; full tables in `results/metrics/segment22_stratified_summary.csv`)

| Stratum | N | CHROM | POS | 2SR (2 s) | LGI-proj |
|---|---|---|---|---|---|
| Main pool (5 UBFC + 107 VIPL v1) | 112 | 7.83 | **7.22** | 9.52 | 9.24 |
| **Motion pool v2** | 20 | **8.85** | 10.57 | 21.34 (r −0.18) | 16.93 (r −0.12) |
| Held-out (v2 + their v1) | 40 | **8.87** | 9.55 | 16.47 | 11.94 |
| UBFC | 5 | 3.26 | 3.77 | 3.57 | 2.65 |
| VIPL v1 stable | 107 | 8.05 | **7.38** | 9.79 | 9.55 |
| VIPL phone (source2) | 12 | 15.47 | **13.39** | 24.27 | 17.01 |
| θ low (<7.3°) / mid / high (≥10.1°) | 40/43/49 | 9.0/5.1/9.7 | 7.3/6.5/9.2 | 8.6/9.4/15.2 | 11.4/8.0/11.7 |
| fps ≥22 (v1 / v2) | 45 / 15 | 9.2 / 7.8 | 8.6 / 10.8 | 12.8 / 24.8 | 10.0 / 17.2 |
| fps <22 (v1 / v2) | 62 / 5 | 7.2 / 12.0 | 6.5 / 9.7 | 7.6 / 11.0 | 9.2 / 16.2 |

Per-subject regressions vs production (worse/better by >1 bpm; severe = >10 bpm; sign-rank p on paired abs-error):

| Comparison | Pool | better | worse | severe worse | severe better | p |
|---|---|---|---|---|---|---|
| 2SR vs POS | v2 (20) | 3 | 15 | 10 | 2 | 0.011 |
| 2SR vs CHROM | v2 (20) | 4 | 14 | 12 | 2 | 0.010 |
| 2SR vs POS | v1 (107) | 24 | 44 | 20 | 5 | 0.018 |
| 2SR vs CHROM | v1 (107) | 27 | 42 | 20 | 7 | 0.070 |
| LGI vs POS | v2 (20) | 2 | 7 | 5 | 0 | 0.020 |
| LGI vs CHROM | v2 (20) | 1 | 11 | 7 | 1 | 0.016 |
| LGI vs POS | v1 (107) | 13 | 21 | 15 | 5 | 0.022 |
| LGI vs CHROM | v1 (107) | 21 | 22 | 16 | 10 | 0.192 |

Per-subject rows: `results/metrics/segment22_per_subject.csv`.

## 4. Go / no-go

- **2SR: NO-GO.** Worse than both production combiners on the motion pool (21.3 vs 8.9 bpm; 10–12
  severe regressions of 20, p≈0.01), and worse on the main pool (9.5 vs 7.2/7.8). Its only competitive
  strata are UBFC (N=5, uninformative) and low-fps v1 (7.6 vs 6.5–7.2, still not better). The paper's
  motion-robustness gain did not transfer to VIPL v2 with this ROI.
- **LGI projection: NO-GO.** Worse on the motion pool (16.9 vs 8.9) and the main pool; it is
  effectively cPACE Stage 1 plus a green row (both already evaluated, not adopted, Segments 11/15).
  Its one good number (6.94 on the 20 v2-persons' v1 rows) is a single unreplicated N=20 stratum, not
  evidence of a win, and is not a held-out confirmation of anything. The state-space tracker was **not**
  built: the projection it would sit on regresses badly, a tracker cannot recover a wrong spectrum, and
  the closest prior tracker (`residualAdaptiveKalmanHR`) was already rejected (Segment 13).
- No candidate cleared the bar every adopted result cleared (held-out win with no severe regressions),
  so nothing is promoted and production stays CHROM/POS with the wavelet default.

## 5. Limitations

v2 pool N=20 (strata as small as 3 and 5); single scenario, mostly single camera; θ terciles are from
this pool's own distribution; 2SR without a skin mask; stride grid extended once post hoc (disclosed);
LGI is the pyVHR-style formulation, not a line-for-line port of the authors' code; UBFC N=5.
The only thing this segment establishes positively is the **Tier 0 baseline**: production CHROM is
already reasonably motion-tolerant on VIPL v2 (8.85 bpm), so the remaining gap is not obviously a combiner problem.

## Files

`src/roi/extractROICovariance.m`, `src/pulseextraction/spatialSubspaceRotation.m`,
`src/pulseextraction/lgiProjection.m`, `scripts/run_segment22_extract_covariance_batch.m`,
`scripts/run_segment22_2sr_evaluation.m`; `results/metrics/segment22_{per_subject,stratified_summary,stride_selection}.csv`;
cache `data/processed/seg22cov_<id>.mat`; logs `results/logs/segment22_*.log`.
