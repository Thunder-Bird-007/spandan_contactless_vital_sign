# Segment 23 Task 6 — CHROM/POS with the original papers' generic parameters (de-tuned)

**Verdict: production CHROM/POS UNCHANGED.** Pooled MAE degrades by 1.3–4.2 bpm when the project's accumulated tuning is stripped, *but* per subject **no de-tuned variant is
statistically distinguishable from production on MAIN_112** (every paired sign test p ≥ 0.08). The pooled shifts are driven by ≤ 10–13 severe-error subjects in both directions.
So: CHROM/POS is **not robust in the sense of being insensitive to configuration** (pooled MAE moves), but it is **also not propped up by a tuning advantage that shows up subject-by-subject**.
The mixed picture is reported as such — see "What this does and does not show".

**Light job (verified):** cached raw ROI-mean R/G/B, same fixed forehead-box ROI as production (this task deliberately does not reopen the ROI question), same whole-clip `fftHeartRate.m` read-out for every rung. No video decode.

## What "untuned" means here — and the honest limits of the parameter provenance
The brief asks for parameters "pulled from each paper directly". Access outcome, per this project's tagging discipline:
* **POS — VERIFIED-FULL (primary source).** Wang, den Brinker, Stuijk & de Haan, IEEE TBME 2017 (TUE preprint, read this session), Algorithm 1: `l = 32` frames @ 20 fps (= **1.6 s**, scaled to fs here), per-window temporal normalisation `C/μ(C)`, `S = [0 1 −1; −2 1 1]·Cn`, `h = S1 + σ(S1)/σ(S2)·S2`, zero-mean **overlap-add sliding one frame**; *"even the commonly used band-pass filtering is not used"*; no detrending; pulse-rate range **[40, 240] bpm**. `src/posNative.m` follows this exactly.
* **CHROM — BLOCKED (primary).** de Haan & Jeanne, IEEE TBME 2013 is paywalled and not readable from this environment (IEEE/TUE portal PDFs unavailable). What is used: the CHROM equations (`Xs=3Rn−2Gn`, `Ys=1.5Rn+Gn−1.5Bn`, `α=σ(Xf)/σ(Yf)`, `S=Xf−αYf`) as the POS paper describes/compares them; **1.6 s Hann-weighted windows, 50 % overlap-add, per-window Butterworth-3 band-pass on Xs/Ys** from the McDuff iphys-toolbox `CHROM_DEHAAN.m` (a **secondary** source, VERIFIED-INDEX quality; its comment says "40–240 BPM" but its code uses 0.7–2.5 Hz — internally inconsistent, so **both** are run). The paper's fixed skin-tone constants are not used; per-window mean normalisation stands in (the common white-balanced form). `src/chromNative.m`.
* Pre-declared primary native config (before any result): CHROM with the **40–240 bpm** band (the POS paper's stated generic range); POS exactly Algorithm 1. Everything else in the table is a labelled sensitivity/attribution variant.

## Ladder (each rung removes/replaces one more tuned element; all reported)
L0 production (wavelet, cubic detrend, 0.7–4 Hz band-pass pre+post, whole-clip combiner) · L1 −wavelet (= Segment 6's chain) · L2 −wavelet −detrend · L3 no filtering at all, whole-clip combiner on raw normalised traces · **L4 native windowed papers' forms (primary)** · L4b native CHROM with iphys' literal 0.7–2.5 Hz · *diagnostic attribution added after seeing L4 (declared, exploratory — see caveat):* L4c native + a post 0.7–2.5 Hz band-pass · L4d native + post 40–240 bpm band-pass · L5 production with a 0.7–2.5 Hz band instead of 0.7–4 Hz.

## Regression checks (passed): L0 = the current production numbers (CHROM 7.8344 / POS 7.2217 MAIN_112, `segment6_hr_pooled_metrics.csv`); L1 = Segment 6's pre-wavelet numbers (9.10 / 8.68).

## Results — MAE / RMSE / r / severe(>10 bpm)/n, per pool
| variant | UBFC (5) | VIPL v1 (107) | MAIN_112 | VIPL v2 motion (20) |
|---|---|---|---|---|
| CHROM L0 production | 3.26 / 5.05 / 0.96 / 1 | 8.05 / 12.09 / 0.48 / 31 | 7.83 / 11.87 / 0.53 / 32 | 8.85 / 12.64 / 0.54 / 7 |
| POS L0 production | 3.77 / 6.15 / 0.94 / 1 | 7.38 / 11.02 / 0.58 / 29 | 7.22 / 10.85 / 0.62 / 30 | 10.56 / 16.06 / 0.31 / 6 |
| CHROM L1 no wavelet (L2 identical) | 3.77 / 6.15 / 0.94 / 1 | 9.35 / 18.37 / 0.28 / 29 | 9.10 / 18.00 / 0.31 / 30 | 8.18 / 11.18 / 0.58 / 7 |
| POS L1 no wavelet (L2 identical) | 3.77 / 6.15 / 0.94 / 1 | 8.91 / 16.78 / 0.22 / 29 | 8.68 / 16.45 / 0.28 / 30 | 9.04 / 14.86 / 0.41 / 6 |
| CHROM L3 no filtering | 18.94 / 28.95 / −0.11 / 2 | 10.68 / 17.74 / 0.36 / 38 | 11.05 / 18.38 / 0.34 / 40 | 18.90 / 24.48 / 0.03 / 12 |
| POS L3 no filtering | 2.65 / 3.77 / 0.98 / 0 | 10.50 / 17.88 / 0.41 / 34 | 10.15 / 17.50 / 0.47 / 34 | 19.58 / 24.78 / 0.04 / 12 |
| **CHROM L4 native (primary)** | 3.16 / 4.84 / 0.97 / 1 | 11.24 / 22.26 / 0.15 / 31 | **10.88 / 21.78 / 0.19 / 32** | 9.17 / 14.85 / 0.42 / 6 |
| **POS L4 native (primary)** | 3.16 / 4.84 / 0.97 / 1 | 11.84 / 25.41 / 0.01 / 31 | **11.45 / 24.85 / 0.08 / 32** | 15.42 / 21.40 / 0.16 / 10 |
| CHROM L4b native, band 0.7–2.5 | 2.72 / 4.67 / 0.96 / 1 | 7.56 / 12.05 / 0.42 / 29 | 7.34 / 11.82 / 0.49 / 30 | 6.66 / 9.05 / 0.78 / 5 |
| CHROM L4c native + post 0.7–2.5 | 3.16 / 4.84 / 0.97 / 1 | 7.87 / 12.55 / 0.39 / 29 | 7.66 / 12.31 / 0.46 / 30 | 8.30 / 13.50 / 0.45 / 5 |
| POS L4c native + post 0.7–2.5 | 3.16 / 4.84 / 0.97 / 1 | 6.38 / 9.77 / 0.64 / 25 | 6.24 / 9.60 / 0.70 / 26 | 13.97 / 19.77 / 0.15 / 9 |
| CHROM L4d native + post 40–240 bpm | 3.16 / 4.84 / 0.97 / 1 | 11.24 / 22.26 / 0.15 / 31 | 10.88 / 21.78 / 0.19 / 32 | 9.17 / 14.85 / 0.42 / 6 |
| POS L4d native + post 40–240 bpm | 3.16 / 4.84 / 0.97 / 1 | 10.20 / 22.62 / 0.03 / 28 | 9.88 / 22.13 / 0.10 / 29 | 13.72 / 20.03 / 0.13 / 9 |
| CHROM L5 production, 0.7–2.5 Hz band | 3.77 / 6.15 / 0.94 / 1 | 7.30 / 10.52 / 0.52 / 29 | 7.14 / 10.36 / 0.59 / 30 | 8.62 / 12.40 / 0.66 / 6 |
| POS L5 production, 0.7–2.5 Hz band | 3.77 / 6.15 / 0.94 / 1 | 7.06 / 10.01 / 0.58 / 28 | 6.92 / 9.87 / 0.65 / 29 | 13.02 / 18.73 / 0.14 / 7 |

Paired per-subject vs production L0 on MAIN_112 (>1 bpm better/worse; severe-worse = >10 bpm worse; exact sign test):
CHROM L1 20 / 18, 8 severe (p=0.75) · L3 18 / 34, 19 (p=0.076) · **L4 18 / 25, 10 (p=0.45)** · L4b 23 / 19, 4 (p=0.45) · L5 8 / 7 (p=0.80).
POS L1 16 / 15, 9 (p=0.61) · L3 19 / 30, 19 (p=0.26) · **L4 18 / 23, 13 (p=0.76)** · L4c 22 / 14, 5 (p=0.11) · L5 5 / 5 (p=1.0).
On the v2 motion pool: only POS-L3 (no filtering) is significant (1 better / 9 worse, p=0.021); everything else p ≥ 0.25 (N=20).

## What this does and does not show
* **The tuning asymmetry is real in pooled-MAE terms and pooled-RMSE terms**: removing the wavelet stage alone costs +1.3 (CHROM) / +1.5 (POS) bpm MAE and roughly +6 bpm RMSE on MAIN_112 (RMSE 11.9 → 18.0; 10.8 → 16.5). Fully native windowed forms cost +3.0 / +4.2 bpm MAE (RMSE ≈ 21.8 / 24.9). At the L1 level (no wavelet) CHROM/POS pooled MAE (9.10 / 8.68) sits at the level of every challenger tested without wavelet denoising (a* 9.53, 2SR 9.52, LGI-with-wavelet 9.24) — i.e. **the pooled-MAE margin of the incumbents over the challengers is about the size of one tuning stage**. (The per-subject significance of the challenger gaps is Task 5's job.)
* **But per subject, none of the de-tuned variants is distinguishable from production** (all p ≥ 0.08 on MAIN_112): wavelet removal makes ~20 subjects better and ~18 worse; the pooled gap comes from the handful of severe-error subjects (harmonic locks), which is the pattern Segment 8 already documented for the wavelet stage. Pooled MAE/RMSE alone overstate how much the tuning "does".
* **The lever is largely the upper band edge, not the combiner form.** Native CHROM with 0.7–2.5 Hz (L4b) matches production (7.34 vs 7.83 MAIN_112; 6.66 vs 8.85 on v2), native POS + a 0.7–2.5 Hz band (L4c) beats production POS on MAIN_112 (6.24 vs 7.22, r 0.70 vs 0.62) but is much worse on motion (13.97 vs 10.56), and production with a 2.5 Hz band (L5) is slightly better than production on MAIN_112 for both. A 2.5 Hz cap is a ≤150 bpm physiological prior that removes 2nd-harmonic impostors; the sign of its effect flips between the mostly-resting pool and the motion pool. **Read L4b/L4c/L5 as exploratory: they were added after L4's poor result, so their apparent advantage is subject to a forking-paths discount and none is significant per subject.** Nothing here supports changing the production band (that would need held-out validation, per the project's rule).
* The de-tuned forms do **not** collapse to challenger-level failure per subject; they also do not beat production. **CHROM/POS is moderately configuration-sensitive in aggregate and statistically robust per subject** — evidence for "some of both" in the master question.
* Caveats: CHROM's primary paper text was unreadable (BLOCKED), so "native CHROM" carries a secondary-source band ambiguity that this task could only bracket, not resolve; results on N=5 (UBFC) / N=20 (v2) strata are not evidence.

**Verdict line: CHROM/POS (untuned/native forms) — no change of verdict; production pipeline stays. The asymmetry is measurable in pooled MAE/RMSE, not per subject.**

## Protected-files verification
See `../common/protected_files_verification.txt`: 18/18 protected production files byte-identical before vs after Segment 23 (SHA-256).

## Outputs
`src/posNative.m`, `src/chromNative.m`, `scripts/run_task6_untuned.m`, `results/task6_summary_by_pool.csv` (final, 9 rungs; `..._run1.csv` = first run with L0–L4b), `results/task6_per_subject.csv`.
