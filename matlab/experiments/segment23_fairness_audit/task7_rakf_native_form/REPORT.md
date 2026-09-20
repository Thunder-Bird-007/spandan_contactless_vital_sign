# Segment 23 Task 7 — RAKF native-form retest (Debnath & Kim 2026, PLOS ONE 21(1):e0340097)

**Verdict: EVALUATED, NOT ADOPTED — unchanged, and now stronger.** Fixing the one documented bug (Eq. 12 exponent instead of division) does *not*
rescue RAKF; the exponent form is slightly **worse** than the original division form on every pool that matters. This fixes one specific,
documented bug — it is not a hyper-parameter fishing expedition.

**Scheduling classification: LIGHT (verified).** Reuses cached raw ROI-mean R/G/B → production chain → `windowedHeartRate.m` per-window sequence → RAKF.
No video decode, no ROI extraction.

## Method
* `src/residualAdaptiveKalmanHR_exp.m` = copy of `matlab/src/validation/residualAdaptiveKalmanHR.m` with **one** change: `Rk = R0*(1+|innovation|^beta)`
  (paper Eq. 12) instead of `R0*(1+|innovation|/beta)`. Window generation, random-walk state, init at window 1, quality weighting `R/max(SQ,1e-3)`,
  scalar update, final-state output are untouched. `opts.form='division'` reproduces production exactly (regression check below).
* Paper constants (re-read from the paper's PDF in `Research Paper/journal.pone.0340097.pdf`): **R0 = 25 bpm², Q = 2×10⁻⁴ per frame**. Q time-scaled the way
  Segment 9 Task 2 derived: 2e-4 × 150 frames (5 s hop @30 fps) = **0.03**. Not re-derived.
* **β — checked directly in the paper: it gives NO numeric β** ("β>0 is the sensitivity parameter"; the sensitivity study says β and T_out change results by
  "< 0.3 bpm", figure only). So the exponent-form β and the division-form β (this project's data-derived `max(std,1)`) are *not* interchangeable and there
  is nothing in the paper to copy. **Pre-declared before any run**: primary β = **1.0** (top-of-script constant `BETA_PRIMARY`); a declared sensitivity
  β ∈ {0.5, 1.0, 1.5, 2.0} is reported in full and was **not** used to choose anything.
* Chains: `prewavelet` = the exact Segment 6/9 chain (regression check) and `wavelet` = current production default. Combiners: CHROM (as originally tested) and POS.
* Pools: UBFC (5), VIPL v1 (107), MAIN_112 (their union), and — beyond the brief's 112 — the 20-subject VIPL v2 motion pool, reported separately.
* Gaps between this implementation and the paper, **documented and deliberately not fixed** (out of the one-variable scope): Eq. 14 outlier replacement
  (`z_k ← median of N previous` when `|z−z̄|>T_out`) and Eq. 15–17 update `x = x⁻ + K·w·(z−x⁻)`, `w=max(α,SQ)` are not implemented; this port folds quality
  into R (`R/SQ`) instead. The paper's SQ index (SPR/SNR/peak-stability) is also not what `windowedHeartRate.qualityScore` computes.

## Regression check (passed — exact)
Prewavelet CHROM, VIPL-107: whole-clip 9.3458/18.372/0.2776, naive windowed 10.338/15.643/0.3157, **RAKF original 12.148/22.040/0.2038** — all identical to
`segment6_task5_rakf_vipl107_metrics.csv` / Segment 9. (`results/task7_summary_by_pool.csv`)

## Results — MAE / RMSE / Pearson r / #subjects with error >10 bpm, per pool
### Production chain (wavelet ON), CHROM
| method | UBFC (5) | VIPL v1 (107) | MAIN_112 | VIPL v2 motion (20) |
|---|---|---|---|---|
| whole-clip fft (production read-out) | 3.26 / 5.05 / 0.96 / 1 | 8.05 / 12.09 / 0.48 / 31 | 7.83 / 11.87 / 0.53 / 32 | 8.85 / 12.64 / 0.54 / 7 |
| naive windowed (no smoothing) | 3.19 / 4.40 / 0.99 / 0 | 7.79 / 10.52 / 0.48 / 36 | 7.59 / 10.32 / 0.55 / 36 | 9.56 / 12.08 / 0.31 / 7 |
| RAKF original (division, data-derived) | 9.82 / 14.73 / 0.50 / 2 | 10.77 / 17.25 / 0.34 / 44 | 10.73 / 17.14 / 0.34 / 46 | 10.33 / 15.06 / 0.20 / 8 |
| RAKF division + paper R0/Q | 10.31 / 15.13 / 0.49 / 2 | 10.79 / 17.26 / 0.34 / 44 | 10.77 / 17.17 / 0.34 / 46 | 10.32 / 15.06 / 0.20 / 8 |
| **RAKF NATIVE exponent β=1.0 [PRIMARY]** | 17.00 / 25.55 / −0.05 / 2 | 11.71 / 18.94 / 0.32 / 45 | **11.95 / 19.28 / 0.28 / 47** | 10.64 / 16.04 / 0.19 / 7 |
| RAKF native β=0.5 (sensitivity) | 13.09 / 19.46 / 0.21 / 2 | 11.32 / 18.32 / 0.32 / 45 | 11.40 / 18.37 / 0.31 / 47 | 10.51 / 15.63 / 0.19 / 7 |
| RAKF native β=1.5 (sensitivity) | 18.12 / 27.07 / −0.09 / 2 | 11.83 / 19.07 / 0.32 / 46 | 12.11 / 19.50 / 0.27 / 48 | 10.66 / 16.13 / 0.19 / 7 |
| RAKF native β=2.0 (sensitivity) | 18.38 / 27.35 / −0.09 / 2 | 11.86 / 19.10 / 0.31 / 46 | 12.15 / 19.54 / 0.27 / 48 | 10.66 / 16.14 / 0.19 / 7 |

### Historical chain (wavelet OFF = Segment 6/9's own), CHROM
| method | UBFC (5) | VIPL v1 (107) | MAIN_112 | VIPL v2 motion (20) |
|---|---|---|---|---|
| whole-clip fft | 3.77 / 6.15 / 0.94 / 1 | 9.35 / 18.37 / 0.28 / 29 | 9.10 / 18.00 / 0.31 / 30 | 8.18 / 11.18 / 0.58 / 7 |
| naive windowed | 2.51 / 3.28 / 0.99 / 0 | 10.34 / 15.64 / 0.32 / 39 | 9.99 / 15.31 / 0.37 / 39 | 8.76 / 11.34 / 0.46 / 9 |
| RAKF original (division) | 4.95 / 6.86 / 0.95 / 1 | 12.15 / 22.04 / 0.20 / 35 | 11.83 / 21.59 / 0.25 / 36 | 11.15 / 16.03 / 0.37 / 8 |
| **RAKF NATIVE β=1.0 [PRIMARY]** | 11.02 / 15.07 / 0.91 / 2 | 12.90 / 23.78 / 0.19 / 37 | 12.82 / 23.46 / 0.25 / 39 | 11.64 / 17.07 / 0.36 / 8 |

### Production chain, POS (extra)
| method | UBFC (5) | VIPL v1 (107) | MAIN_112 | VIPL v2 motion (20) |
|---|---|---|---|---|
| whole-clip fft | 3.77 / 6.15 / 0.94 / 1 | 7.38 / 11.02 / 0.58 / 29 | 7.22 / 10.85 / 0.62 / 30 | 10.56 / 16.06 / 0.31 / 6 |
| naive windowed | 2.76 / 4.09 / 0.99 / 0 | 7.52 / 10.29 / 0.47 / 32 | 7.31 / 10.09 / 0.55 / 32 | 10.74 / 13.84 / 0.36 / 8 |
| RAKF original (division) | 12.75 / 16.47 / 0.52 / 3 | 9.20 / 12.67 / 0.40 / 42 | 9.36 / 12.86 / 0.41 / 45 | 16.05 / 20.99 / 0.07 / 12 |
| **RAKF NATIVE β=1.0 [PRIMARY]** | 21.52 / 28.10 / −0.12 / 3 | 9.97 / 13.83 / 0.37 / 44 | 10.49 / 14.76 / 0.31 / 47 | 17.12 / 22.94 / 0.05 / 12 |

## Paired per-subject comparison (native β=1 vs each baseline; |error| difference, >1 bpm = "better/worse"; exact two-sided sign test)
| chain/combiner, pool | vs whole-clip | vs naive windowed | vs original (division) RAKF |
|---|---|---|---|
| wavelet/CHROM, MAIN_112 | 33 better / 59 worse, 19 severe-worse, p=0.029 | 37 / 56, 23, p=0.035 | 6 / 41, 2, p<0.0001 |
| wavelet/CHROM, v2 motion | 8 / 6, 4, p=1.0 | 11 / 4, 3, p=0.33 | 2 / 3, 0, p=0.63 |
| prewavelet/CHROM, MAIN_112 | 34 / 52, 15, p=0.072 | 36 / 52, 20, p=0.13 | 10 / 34, 3, p<0.0001 |
| wavelet/POS, MAIN_112 | 28 / 64, 18, p=0.0002 | 26 / 59, 21, p=0.005 | 8 / 39, 2, p<0.0001 |

## Interpretation (what is and is not established)
* **The Eq. 12 fix makes RAKF worse, not better** (MAIN_112 CHROM 10.73 → 11.95 MAE; RMSE 17.1 → 19.3), consistently across both chains, both combiners, and every β tried.
  The worst damage is on UBFC (3.3 → 17.0 bpm): the 5 long clips have many windows, and the exponent form drives R_k so high for any innovation above ~1 bpm that the
  filter stops updating.
* *Likely mechanism (inference, not verified here):* with `x` initialised at window 1's own measurement and only the final state returned, a large `|innovation|^β` freezes the
  state on the first window's value — the same "a bad first choice propagates" failure Tasks P/Q already found for continuity methods.
* On the v2 motion pool nothing separates from noise (N=20; every sign test p>0.05). **This is not evidence RAKF works under motion** — it also does not beat plain whole-clip there.
* **A side observation that is a material fact about the existing record, not about RAKF:** under the *production* (wavelet) chain, the plain windowed read-out with no smoothing
  (MAIN_112 CHROM 7.59 MAE / 10.32 RMSE / 0.55 r) beats the production whole-clip FFT (7.83 / 11.87 / 0.53) on all three metrics; on v2 motion it is worse (9.56 vs 8.85 MAE).
  Task 5 and Task 4 return to this.
* **Caveat, stated plainly:** the paper's own sensitivity study claims RAKF is insensitive to β; the paper's RAKF is embedded in a per-*frame* 30 fps tracker with Eq. 14 and Eq. 15–17
  additions this port does not have. This task retests *the project's window-level port with the Eq. 12 formula corrected*, not the paper's complete filter. A full paper-native
  per-frame RAKF was not built (out of scope for the one-variable fix the brief asked for).

**Verdict line: RAKF — EVALUATED, NOT ADOPTED (retest in native Eq. 12 form: still loses, marginally worse than the division form). No change to production; no promotion.**

## Protected-files verification
See `../common/protected_files_verification.txt` (SHA-256 of 18 production files hashed before any work and re-hashed at close): 18/18 protected production files byte-identical before vs after Segment 23 (SHA-256).

## Outputs
`src/residualAdaptiveKalmanHR_exp.m`, `scripts/run_task7_rakf_native.m`, `results/task7_summary_by_pool.csv`, `results/task7_per_subject_{prewavelet,wavelet}_{chrom,pos}.csv`.
