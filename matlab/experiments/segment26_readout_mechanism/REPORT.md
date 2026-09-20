# Segment 26 — What makes the windowed read-out work? (median-vs-mean isolation + quality-proxy check)

One-shot per `PREREGISTRATION_addendum.md` (commit `1bb7d0c`, before any computation). Zero new video decode: 730 cached clips × CHROM/POS = 1460 read-outs, 0 failures; parity gate: recomputed median read-out and baseline match the stored Segment 24/25 numbers to 5e-13 bpm. Only change to the read-out: `mean` instead of `median` over the per-window peaks (`src/lgiPaperReadoutMean.m`).

## Step 0 (done first)
The Segment 25 verdict wording was changed to "CANDIDATE, VALIDATED — degraded-signal conditions only (dark/low-fps/motion; not shown in normal-lighting or cross-device conditions)" in `SESSION_HANDOFF.md`, `Literature_Review_Master.md` §7 and (same wording, so also fixed) Segment 25's `REPORT.md`, old text struck through. **One factual correction recorded with it:** Segment 24's v4/v6 scenarios are *bright light* and *stable 1.5 m*, not motion (VIPL's motion scenarios are v2/v9, never part of Segments 24/25); "motion" in the requested wording is not something these clips demonstrate.

## Verdict (pre-declared rules)

**The median-rejection hypothesis is NOT supported, and the degraded-condition pattern does NOT track any cached quality proxy.** Step 1 outcome by the rules: **mixed** (R1 false for both combiners, R3 also false because only 2 of 6 (CHROM) / 3 of 6 (POS) classified strata have |gap| < 0.5 bpm); Step 2: **no correlation with any proxy.** Read together (as the addendum's rule for the "mean ≈ median / windowing does the work" and "no proxy" branches): **the windowing itself carries almost all of the gain; the mechanism behind *where* it helps is still unknown; the "principled, quality-gated robustness read-out" story is not established and should not be told.**

### Step 1 — median vs mean (14 paired Wilcoxon tests, one Holm)

MAE in bpm; gap = mean − median (positive = median better). Full table with RMSE, win counts: `results/s26_step1_mean_vs_median.csv`. Classes were fixed in advance.

| class | stratum | CHROM: fft → median / mean (gap, Holm p) | POS: fft → median / mean (gap, Holm p) |
|---|---|---|---|
| DEGRADED | v4 bright (96) | 8.38 → 4.48 / 5.34 (+0.86, 1.0) | 7.30 → 4.31 / 5.57 (+1.25, 0.66) |
| DEGRADED | v6 1.5 m (94) | 8.56 → 7.91 / 8.17 (+0.27, 1.0) | 9.73 → 7.59 / 8.01 (+0.43, 1.0) |
| DEGRADED | v5 dark (93) | 11.86 → 7.38 / **6.15** (**−1.23**, 0.078) | 11.98 → 8.39 / 7.86 (−0.53, 1.0) |
| CLEAN | MAIN_112 (112) | 7.83 → 6.73 / 7.52 (+0.80, 0.93) | 7.22 → 6.45 / 6.69 (+0.23, 1.0) |
| CLEAN | v3 talking (95) | 7.29 → 7.11 / 8.08 (+0.97, 0.93) | 8.87 → 6.81 / 7.64 (+0.83, 0.26) |
| CLEAN | C v1 source3 (107) | 6.90 → 6.79 / 7.26 (+0.47, 1.0) | 7.20 → 6.76 / 6.96 (+0.20, 1.0) |
| unclassified | v7 exercise (91) | 19.49 → 15.93 / 15.45 (−0.47, 1.0) | 18.85 → 14.68 / 14.97 (+0.29, 1.0) |

* **No mean-vs-median difference is significant after correction (all 14 Holm p ≥ 0.078).**
* **Prediction check.** The hypothesis predicted mean recovers much less of the gain on degraded sets and ties on clean ones. Observed: on the pooled degraded strata the mean recovers **101 % (CHROM) / 86 % (POS)** of the median's gain (pooled degraded gain: median 3.01 / 2.91 bpm, mean 3.04 / 2.51). If anything the median's small edge shows up on the *clean* strata (mean worse by 0.2–1.0 bpm in all six clean cells), the opposite of the prediction; on the dark set (v5) the mean is nominally *better* than the median for CHROM (raw p = 0.0056, Holm 0.078 — not significant, not claimed).
* Rule flags — CHROM: R1 false, R2 false (gaps 0.80/0.97 on MAIN_112/v3), R3 false; POS: R1 false, R2 true, R3 false.
* **Reading.** Per-window aggregation is not what drives the gain. Any aggregation of 90 %-overlapping 256-sample windows (≈ 8.5–16 s) does most of the work — consistent with the windowed estimate being an average/vote over many time-localised spectra instead of one whole-clip spectral maximum. The median adds a small, non-significant benefit in some clean strata; nothing here shows it acts by "rejecting corrupted windows" on degraded clips (where the mean does as well). Not tested (out of scope): a single window length, a smaller hop, and a whole-clip FFT restricted to the same band, which would separate "windowing" from "the read-out's own band-pass + zero-padding".

### Step 2 — does the per-clip gain track a cached quality proxy? (6 Spearman tests, pooled over all five sets, Holm)

Improvement = |error|(fftHeartRate) − |error|(median read-out), per clip. Pool: MAIN_112, Segment 24 PRIMARY (v7/v4/v6), Segment 25 B, Segment 25 C, UBFC-D2 = 730 clips.

| proxy (cached) | n | CHROM ρ (p raw / p Holm) | POS ρ (p raw / p Holm) | predicted | correlates? |
|---|---|---|---|---|---|
| P1 `fs` | 730 | +0.017 (0.64 / 0.64) | −0.053 (0.15 / 0.46) | ρ < 0 | no / no |
| P2 dropped-frame fraction | 688 | +0.089 (0.020 / 0.100) | +0.094 (0.013 / 0.079) | ρ > 0 | no / no |
| P3 mean raw ROI green | 730 | +0.083 (0.025 / 0.100) | +0.045 (0.22 / 0.46) | either | no / no |

No proxy reaches Holm p < 0.05, and the largest |ρ| is 0.094 (below the pre-declared 0.10 floor). P2 points in the predicted direction and is nominally significant before correction, but it is weak and does not survive Holm. **Result: no correlation with any proxy → the degraded-condition pattern may be tied to these specific scenarios rather than to a measurable, cached quality dimension** (as stated in the pre-declared verdict).

Why the proxies fail is visible in the stratum summary (`s26_proxy_summary_by_stratum.csv`): mean fs is 16.7 (v5, large gain), 23.3 (v4, large gain), 20.0 (v6, small gain), 20.1 (v3, none on CHROM), 20.8 (MAIN_112), 21.7 (C, none) — **frame rate does not order the gains**; v3 and v6 have the same fs and different gains, v4 and v5 sit at opposite ends of fs with similar large gains. Dropped-frame fractions are ~0–3 % everywhere. Mean raw ROI green is highest in v5 (178) and v4 (159) — two of the three large-gain scenarios — against 104–150 elsewhere (v7, also a large-gain scenario, is 138), so no monotone relation exists; a non-monotone one is not excluded, and Spearman by design does not capture it (pre-accepted; no shape fitting was done).

## Post-hoc, NOT pre-registered (interpretation only)

* Within-stratum Spearman (descriptive, uncorrected; `s26_step2_spearman_within_stratum.csv`): the only larger values are v4 CHROM with dropped-frame fraction (ρ = 0.35, p = 0.001) and v3 CHROM with brightness (ρ = −0.26); C, MAIN_112 show ρ ≈ 0.2 on one proxy each. With 3 proxies × 2 combiners × 9 strata = 54 uncorrected looks, a handful at p < 0.05 is what chance gives; **none is a finding**, and the direction is not consistent across strata (dropFrac ρ is −0.14 in v3 and +0.35 in v4).
* v7 (after exercise) and D2 (descriptive): the mean is as good as the median (v7 CHROM 15.45 vs 15.93; D2 5.78 vs 6.00) — same picture as v5.
* Since the fs proxy is confounded with scenario, an effect that is really "scenario-specific (dark, bright, exercise)" and one that is "degraded signal" cannot be separated with these clips.

## What this changes

* The Segment 25 claim stands as narrowed in Step 0 (validated only where the fixed thresholds were met: dark/low-fps pooled set; not shown in normal-lighting or cross-device conditions) — and this segment adds that **the gain is not explained by median-based window rejection, and cannot be predicted from fs, dropped frames or brightness.** A production gate "activate only when a live quality proxy is low" has **no support** from the proxies available today; that dedicated gating segment is *not* warranted on this evidence.
* Cheapest remaining mechanism tests (not started): windowing vs band-limit — whole-clip FFT with the same butter(0.7–4) band and zero-padding; window length (e.g. 128/512) and hop; a proxy that is actually a signal-quality measure (spectral SNR of the pulse, or cross-ROI PLV where multi-region caches exist).

## Caveats
Same people recur across the five sets, so pooled Spearman p-values are optimistic (which only strengthens the null); "degraded" vs "clean" is the brief's a-priori labelling, not an independent measurement; no set is subject-independent of MAIN_112; the median/mean aggregation is a single-line change tested on one window/hop configuration.

## Stored for reuse
`results/s26_per_clip.csv` (1460 rows: all three read-outs + fs, dropped fraction, mean ROI green for every clip × combiner), `s26_step1_*.csv`, `s26_step2_*.csv`, `s26_proxy_summary_by_stratum.csv`; scripts `s26_run.m`, `s26_analyze.m`; `src/lgiPaperReadoutMean.m`.

## Closeout
Protected production files verified byte-identical before/after (`results/protected_files_verification.txt`); only new files created.
