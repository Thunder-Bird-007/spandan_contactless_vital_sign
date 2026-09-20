# Segment 25 — Replication of the band-matched windowed read-out (Segment 24 condition c)

One-shot run per `PREREGISTRATION.md` (commit `aef3beb`, before any read-out ran). Candidate = `lgiPaperReadout(pulse, fs, [0.7 4.0])` (byte-identical to Segment 24's), baseline = production `fftHeartRate.m`, both on the production Branch-1 chain, CHROM and POS. 295 new clips decoded (0 failures), 814 read-out rows, 0 failures; parity gate 0.000039 bpm. No parameter or definition changed after the preregistration.

## Verdict

~~**CANDIDATE, VALIDATED (scenario-generalizing) — not ADOPTED.**~~ **CANDIDATE, VALIDATED — degraded-signal conditions only (dark/low-fps/motion; not shown in normal-lighting or cross-device conditions) — not ADOPTED.** *(Wording corrected 2026-09-20 in Segment 26 Step 0: the B replication is driven by v5 dark/low-fps; see the 'Honest reading' section, and the note in SESSION_HANDOFF.md.)* It holds on MAIN_112 (A) and replicates on the unseen-scenario set (B) for both combiners. It does **not** replicate on the device-shift set (C), so **no device-generalization claim is made.** Production integration (a full pipeline swap-in test) is a separate decision not made here.

Precise scope: the combiner is still production CHROM/POS; only the HR read-out stage (whole-clip FFT → 256-sample/90 %-overlap windowed peak, median over windows, same 0.7–4.0 Hz band) is new. "Validated" means held out **by video/scenario, not by subject** (all 107 VIPL people are in MAIN_112; no new-people set exists on disk).

## The six pre-declared tests (one Holm correction across all six)

Units: subject (A, 112), person mean over v3/v5 clips (B, 96 people), person (C, 107). Gain = baseline MAE − candidate MAE (bpm, unit-level mean); better/worse = number of units.

| Set | Combiner | MAE (a) → (c) | gain | better / worse | RMSE (a) → (c) | p raw | **p Holm (6)** | replicates | holds |
|---|---|---|---|---|---|---|---|---|---|
| A MAIN_112 | CHROM | 7.83 → 6.73 | 1.11 | 62 / 50 | 11.87 → 9.82 | 0.332 | 0.997 | no | **yes** |
| A MAIN_112 | POS | 7.22 → 6.45 | 0.77 | 66 / 46 | 10.85 → 9.35 | 0.130 | 0.522 | no | **yes** |
| B v3+v5 | CHROM | 9.43 → 7.12 | 2.31 | 57 / 39 | 13.95 → 10.63 | 0.0041 | **0.020** | **yes** | yes |
| B v3+v5 | POS | 10.27 → 7.49 | 2.77 | 65 / 31 | 15.53 → 11.20 | 0.00012 | **0.00073** | **yes** | yes |
| C v1 source3 | CHROM | 6.90 → 6.79 | 0.11 | 60 / 47 | 10.54 → 10.10 | 0.351 | 0.997 | no | yes |
| C v1 source3 | POS | 7.20 → 6.76 | 0.43 | 55 / 52 | 11.24 → 10.09 | 0.423 | 0.997 | no | yes |

("holds" = MAE(c) ≤ MAE(a) and not significantly worse; it is the regression rule for A. For B/C it is shown only for information.)

* **A (regression check): holds.** The baseline reproduces the project's known MAIN_112 numbers exactly (CHROM 7.83, POS 7.22). The candidate is lower on MAE, RMSE and severe-error count for both combiners, but the improvement is **not significant** here (Holm p 0.52–0.997): read "no regression, possible small gain", not "improvement".
* **B (scenario shift): replicates**, both combiners, significant after the joint correction.
* **C (device shift): does not replicate.** Direction is still favourable (both combiners lower MAE, 0.11 / 0.43 bpm) but well inside noise. Per the brief, C does not decide the verdict either way.

## Full per-pool tables (MAE / RMSE / r; severe >10 bpm), `(a) fftHeartRate → (c) windowed 0.7–4 Hz`

| Combiner | Pool (n, mean GT) | MAE | RMSE | r | severe |
|---|---|---|---|---|---|
| CHROM | A UBFC (5, 92.6) | 3.26 → 2.14 | 5.05 → 3.71 | 0.96 → 0.99 | 1 → 0 |
| CHROM | A VIPL v1 (107, 75.3) | 8.05 → 6.94 | 12.09 → 10.01 | 0.48 → 0.55 | 31 → 26 |
| CHROM | **A MAIN_112 (112, 76.1)** | 7.83 → 6.73 | 11.87 → 9.82 | 0.53 → 0.61 | 32 → 26 |
| CHROM | B v3 talking (95, 81.1) | 7.29 → 7.11 | 11.09 → 10.36 | 0.50 → 0.47 | 25 → 25 |
| CHROM | B v5 dark (93, 75.9) | 11.86 → 7.38 | 16.36 → 10.90 | 0.23 → 0.47 | 42 → 24 |
| CHROM | **B all (188)** | 9.55 → 7.24 | 13.95 → 10.63 | 0.41 → 0.51 | 67 → 49 |
| CHROM | **C v1 source3 (107, 75.2)** | 6.90 → 6.79 | 10.54 → 10.10 | 0.49 → 0.44 | 24 → 25 |
| POS | A UBFC (5) | 3.77 → 2.14 | 6.15 → 3.71 | 0.94 → 0.99 | 1 → 0 |
| POS | A VIPL v1 (107) | 7.38 → 6.66 | 11.02 → 9.53 | 0.58 → 0.56 | 29 → 27 |
| POS | **A MAIN_112 (112)** | 7.22 → 6.45 | 10.85 → 9.35 | 0.62 → 0.62 | 30 → 27 |
| POS | B v3 (95) | 8.87 → 6.81 | 14.64 → 10.39 | 0.31 → 0.45 | 28 → 21 |
| POS | B v5 (93) | 11.98 → 8.39 | 16.38 → 11.96 | 0.21 → 0.34 | 43 → 30 |
| POS | **B all (188)** | 10.41 → 7.59 | 15.53 → 11.20 | 0.32 → 0.44 | 71 → 51 |
| POS | **C v1 source3 (107)** | 7.20 → 6.76 | 11.24 → 10.09 | 0.42 → 0.42 | 27 → 27 |

## Honest reading (what the replication does and does not show)

* **The B result is concentrated in v5 (dark, mean true fs ≈ 16.7 fps).** Descriptive per-stratum Wilcoxon (uncorrected, `s25_descriptive_paired.csv`): v5 CHROM −4.48 bpm (p = 0.0001), POS −3.59 (p = 0.0016); v3 CHROM −0.18 (p = 0.89 — no effect), POS −2.07 (p = 0.030, would not survive correction). So "generalizes to new scenarios" is solid for dark/low-frame-rate video and **not shown for talking (v3) on CHROM.** The pre-declared verdict rule was met on the pooled B set, and that is what it is.
* **Disclosed Task N overlap does not drive B:** dropping the 20 v5 clips that Segment 6 Task N had scored with production HR (sensitivity, descriptive) leaves B significant — CHROM −2.56 bpm (p = 0.0035), POS −3.09 (p < 0.0001).
* **Consistent with Segment 24, in a different direction from Segment 23's narrow band:** on the same MAIN_112 the narrow-band windowed read-out gave CHROM 6.38 / POS 6.70 (Segment 23); the band-matched form gives 6.73 / 6.45 — similar magnitude, no band prior needed.
* **The gain is mostly variance/outlier reduction, not a systematic shift:** RMSE and severe-error counts fall more than MAE on B and A, while r moves little except on v5. A median over windows discards wrong-harmonic windows; that is the plausible mechanism (not isolated here — the "median aggregate" and "whole-clip FFT with the same band" controls remain untested).
* **Device shift (C): no evidence either way at N = 107** (favourable but not significant). The RealSense clips are already easy for the baseline (MAE 6.9 / 7.2), leaving little room; a null here is not a refutation.

## Caveats

* Held out by video/scenario, not by subject; all sets share people with MAIN_112.
* A's improvement is not significant on its own; the promotion rests on "no regression" (A) + significant replication (B).
* Six tests, Holm-adjusted jointly; the B/C definitions and thresholds were fixed before the run.
* Not tested: full-pipeline swap-in (Branch 1 → SpO2/quality gates, Android port); real-time/latency behaviour of a 256-sample windowed read-out (needs ≥ ~9–15 s of signal at the fs seen here — the whole-clip FFT has the same or longer requirement, but the app's ~25 s window has not been checked).

## Stored for reuse

`results/s25_set_manifest.csv` (814/2 = 407 clips: A 112, B 188, C 107), `results/s25_new_vipl_manifest.csv` (295 new clips: fs, frames, dropped, ground truth), 295 new caches `data/processed/VIPL_p*_v3_source1_*`, `..._v5_source1_rgb_traces.mat`, `..._v1_source3_rgb_traces.mat`; `s25_hr_per_video.csv`, `s25_metrics_by_stratum.csv`, `s25_verdict_tests_holm6.csv`, `s25_descriptive_paired.csv`. Raw videos remain in the scratch tree on `I:\...\seg24_scratch\VIPL-HR` (now ~7 GB; safe to delete, caches supersede them).

## Closeout

Protected production files verified byte-identical before/after (`results/protected_files_verification.txt`). No production file edited; only new files.
