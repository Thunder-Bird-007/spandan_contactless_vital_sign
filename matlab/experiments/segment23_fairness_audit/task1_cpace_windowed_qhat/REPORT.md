# Segment 23 Task 1 — cPACE with a sliding-window q̂ (not one global estimate)

**Verdict: EVALUATED, NOT ADOPTED — unchanged.** The suspected fairness gap was real (q̂ *was* a single global estimate) but closing it changes almost nothing:
on 112 subjects only 1–5 subjects move by more than 1 bpm, and cPACE (Stage 1 or Full) still loses to production CHROM/POS on every pool with a meaningful N.

**Opening paragraph — what was checked first, and what it needs (asked for explicitly).**
1. *Was q̂ estimated once or per window?* Read `matlab/src/pulseextraction/cpaceProjection.m`: `meanVec = [mean(R);mean(G);mean(B)]` over the **whole clip**, one q̂ for the entire recording. Segment 11's Stage 1 and Segment 15's Full Stage 1–3 both used it. The suspected gap is real.
2. *Light or heavy?* **LIGHT.** q̂ is the normalised temporal mean of the per-frame ROI-mean R/G/B, which the project already caches (`data/processed/<id>_rgb_traces.mat`; v2: `seg22cov_*.mat`). No per-pixel data and no video decode are needed.
3. **Correction to the brief's premise (important):** the brief says the *paper* specifies a windowed q̂. It does not. Kaur et al.'s Table S2 (Supplement 1, read directly) lists q̂ as a *per-ROI* "unit vector along temporal mean of (R,G,B)", and the supplement calls it "the (static) mean skin reflectance direction… less subject to per-recording variability". The 10 s / 1 s sliding window in Table S2 is the *HR-estimation* window. So a windowed q̂ is a **fairness hypothesis this segment tests, not a "native form" of the paper** — reported as such.

## Method
* `src/cpaceProjectionWindowed.m` (own copy; production untouched): q̂ re-estimated per **10 s window, 5 s hop** (`windowedHeartRate.m`'s convention); each window projected with `P_w = I − q_w q_wᵀ`; overlapping windows cross-faded with a sin² weight normalised by the weight sum → one continuous corrected trace.
* Arms: production | Stage 1 global q̂ (Segment 11) | **Stage 1 windowed q̂** | Full Stage 1–3 global q̂, bw 0.30 (Segment 15) | **Full windowed q̂, bw 0.30** | **Full windowed q̂, bw 0.15** (Segment 15's pooled-best bw). CHROM and POS wired exactly as `run_segment11_task1_cpace_and_plv.m`.
* Two chains: **noWavelet** (Segment 11/15's own chain — used for the regression check; the primary comparison) and **wavelet** (current production default; note cPACE was never previously combined with it, so those rows are a new configuration).
* Pools: UBFC 5, VIPL v1 107, MAIN_112, and the 20-subject VIPL v2 motion pool (cPACE's first-ever motion-pool test, queued in the Literature Review §1).

## Regression check (passed — exact)
Global-q̂ arms, noWavelet chain, the 100 subjects of Segment 15's pool: cPACE-Full-bw0.30, CHROM, POS, Stage1+CHROM — **max |ΔHR| = 0.0000 bpm** vs `segment15_cpace_full_per_subject_hr.csv`.

## Results — MAE / RMSE / r / severe(>10 bpm)/n, per pool
### noWavelet chain (Segment 11/15's chain)
| arm | UBFC (5) | VIPL v1 (107) | MAIN_112 | VIPL v2 motion (20) |
|---|---|---|---|---|
| CHROM production | 3.77 / 6.15 / 0.94 / 1 | 9.35 / 18.37 / 0.28 / 29 | 9.10 / 18.00 / 0.31 / 30 | 8.18 / 11.18 / 0.58 / 7 |
| CHROM + Stage 1, global q̂ | 3.77 / 6.15 / 0.94 / 1 | 9.18 / 18.88 / 0.24 / 24 | 8.94 / 18.50 / 0.29 / 25 | 10.05 / 15.49 / 0.36 / 7 |
| CHROM + Stage 1, **windowed q̂** | 3.77 / 6.15 / 0.94 / 1 | 9.23 / 18.92 / 0.23 / 25 | 8.99 / 18.54 / 0.28 / 26 | 10.35 / 15.56 / 0.34 / 7 |
| POS production (= POS + Stage 1 global, exact no-op) | 3.77 / 6.15 / 0.94 / 1 | 8.91 / 16.78 / 0.22 / 29 | 8.68 / 16.45 / 0.28 / 30 | 9.04 / 14.86 / 0.41 / 6 |
| POS + Stage 1, **windowed q̂** | 3.16 / 4.84 / 0.97 / 1 | 8.58 / 16.46 / 0.24 / 28 | 8.34 / 16.12 / 0.30 / 29 | 9.13 / 14.86 / 0.41 / 6 |
| cPACE Full, global q̂, bw 0.30 | 2.44 / 3.66 / 0.98 / 0 | 11.30 / 15.62 / 0.35 / 47 | 10.91 / 15.29 / 0.45 / 47 | 24.95 / 44.16 / −0.18 / 13 |
| cPACE Full, **windowed q̂**, bw 0.30 | 2.44 / 3.66 / 0.98 / 0 | 11.17 / 15.54 / 0.34 / 47 | 10.78 / 15.21 / 0.44 / 47 | 16.77 / 21.20 / 0.09 / 12 |
| cPACE Full, **windowed q̂**, bw 0.15 | 3.18 / 4.50 / 0.99 / 0 | 10.08 / 14.84 / 0.38 / 38 | 9.77 / 14.53 / 0.46 / 38 | 17.00 / 22.93 / −0.11 / 10 |

### wavelet chain (current production default; new configuration for cPACE)
| arm | UBFC (5) | VIPL v1 (107) | MAIN_112 | VIPL v2 motion (20) |
|---|---|---|---|---|
| CHROM production | 3.26 / 5.05 / 0.96 / 1 | 8.05 / 12.09 / 0.48 / 31 | 7.83 / 11.87 / 0.53 / 32 | 8.85 / 12.64 / 0.54 / 7 |
| CHROM + Stage 1 global / windowed q̂ | 3.77 / 6.15 / 0.94 / 1 (both) | 7.64 / 11.03 / 0.48 / 30 ; 7.78 / 11.25 / 0.46 / 30 | 7.47 / 10.86 / 0.56 / 31 ; 7.60 / 11.07 / 0.54 / 31 | 10.76 / 15.87 / 0.29 / 7 ; 10.16 / 15.66 / 0.30 / 6 |
| POS production | 3.77 / 6.15 / 0.94 / 1 | 7.38 / 11.02 / 0.58 / 29 | 7.22 / 10.85 / 0.62 / 30 | 10.56 / 16.06 / 0.31 / 6 |
| POS + Stage 1 **windowed q̂** | 3.16 / 4.84 / 0.97 / 1 | 7.81 / 11.66 / 0.55 / 31 | 7.60 / 11.44 / 0.59 / 32 | 12.22 / 20.05 / 0.23 / 6 |
| cPACE Full global q̂ bw0.30 | 35.91 / 70.75 / −0.31 / 2 | 12.45 / 16.15 / 0.41 / 53 | 13.49 / 21.74 / 0.36 / 55 | 17.70 / 21.91 / 0.10 / 13 |
| cPACE Full **windowed q̂** bw0.30 | 35.91 / 70.75 / −0.31 / 2 | 12.26 / 16.07 / 0.41 / 53 | 13.31 / 21.68 / 0.36 / 55 | 17.70 / 21.91 / 0.10 / 13 |
| cPACE Full **windowed q̂** bw0.15 | 3.18 / 4.50 / 0.99 / 0 | 10.71 / 15.10 / 0.39 / 41 | 10.38 / 14.79 / 0.48 / 41 | 16.03 / 21.34 / −0.03 / 10 |

## Per-subject paired evidence (|error| difference; ">1 bpm" = better/worse; exact sign test)
* **windowed vs global q̂, Full bw0.30 (noWavelet), MAIN_112:** 3 better / 0 worse (p=0.25). v2: 1 better / 0 worse. Stage 1 CHROM: 1 better / 2 worse (p=1.0). **q̂ windowing is essentially a null intervention.**
  (The v2 MAE drop 24.95 → 16.77 for Full bw0.30 comes from *one* subject leaving a ~160 bpm error — not a systematic effect.)
* **Best windowed cPACE vs production CHROM (noWavelet, MAIN_112):** bw0.30 22 better / 45 worse, 25 severe-worse (p=0.0035); bw0.15 24 / 39, 17 (p=0.021). vs POS: 21 / 37, 15 severe (p=0.030).
* **v2 motion:** Full windowed vs CHROM production: bw0.30 2 better / 14 worse, 8 severe (p=0.004); bw0.15 2 / 13, 6 (p=0.004).
* Stage 1 windowed vs production: CHROM 11 better / 15 worse (p=0.44); POS 4 better / 0 worse on noWavelet (p=0.125) but 1 / 3 on wavelet. No consistent direction.

## Interpretation
* The global-q̂ gap was **not** why cPACE lost. Stage 1 (either q̂) is a wash for CHROM (+/− < 0.5 bpm MAE on MAIN_112) and — with a global q̂ — an exact no-op for POS; Full Stage 1–3 stays 1–5 bpm behind production on MAIN_112 in every configuration and is far behind on the motion pool (16–25 vs 8.2–9.0 bpm), with p<0.05 paired against CHROM.
* The one place windowed-q̂ POS looks better (UBFC 3.77 → 3.16, MAIN_112 noWavelet 8.68 → 8.34) is 3–4 subjects; on the production wavelet chain it reverses (7.22 → 7.60). Not a finding.
* The `wavelet + cPACE Full` combination is markedly worse on UBFC (35.9 bpm; the 5 clips lock onto a wrong seed) — a configuration never previously tested; reported, not investigated (Segment 15's noWavelet chain is the meaningful cPACE comparison).
* Caveats: N=5 (UBFC) and N=20 (v2) strata are too small for any claim; cross-ROI PLV was not re-run (the 4-region cache covers only 20 VIPL subjects; windowed q̂ changes Stage 1 HR so little that a PLV gain is not expected, but that is an expectation, not a measurement). The lightly-pigmented cohort caveat from Segment 11 still applies: nothing here says cPACE fails on darker skin.

**Verdict line: cPACE (windowed q̂, Stage 1 and Full) — EVALUATED, NOT ADOPTED. The "global q̂" fairness gap is closed and does not explain the earlier loss.**

## Protected-files verification
See `../common/protected_files_verification.txt`: 18/18 protected production files byte-identical before vs after Segment 23 (SHA-256).

## Outputs
`src/cpaceProjectionWindowed.m`, `scripts/run_task1_cpace_windowed.m`, `results/task1_summary_by_pool.csv`, `results/task1_per_subject_{noWavelet,wavelet}.csv`.
