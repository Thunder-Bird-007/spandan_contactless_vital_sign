# Segment 26 — PREREGISTRATION ADDENDUM (committed BEFORE any Segment 26 computation)

Follows Segments 24/25 (same convention: preregister → commit → one-shot). Registered 2026-09-20. **Zero new video decode**: everything re-aggregates already-cached traces. No parameter of the read-out other than the single aggregation change below is touched.

Question 1: does the band-matched windowed read-out's gain come from windowing generally, or from the **median's rejection of corrupted / wrong-harmonic windows**? Question 2: does the per-clip gain track an objective signal-quality proxy the project already caches?

## 1. Step 1 — median vs mean aggregation

* **Median read-out (reference, unchanged):** `lgiPaperReadout(pulse, fs, [0.7 4.0])` (byte-identical to Segment 24/25's; per-clip HR = 60·median of per-window peaks).
* **Mean variant:** `src/lgiPaperReadoutMean.m` — the same file with the single aggregation line changed to `hrBpm = 60 * mean(pk);` (plus the function name and a header comment). Same 256-sample Hann windows, 90 % overlap, 4× zero-pad, Butterworth-2 and peak-pick, called with the same `[0.7 4.0]` band. (The copy has LF line endings, the original CRLF; compare with `diff --strip-trailing-cr`.)
* **Baseline (a):** production `fftHeartRate.m`, unchanged. Pulse signals: the production Branch-1 chain (`s23_chain`, wavelet default), CHROM and POS, exactly as Segments 24/25.
* **Clips:** all cached, no decode: MAIN_112 (112; loaded through Segment 23's loader) · Segment 24 PRIMARY strata v7, v4, v6 source1 (91 / 96 / 94) · Segment 25 B strata v3, v5 source1 (95 / 93) · Segment 25 C (v1 source3, 107) · **UBFC-D2 (42) reported descriptively only** (not held out; excluded from the tests and the rule below, included in the Step 2 pool as the fifth set). The 321 phone clips are not used (condition (c) was already seen there and fps is mislabelled).
* **Parity gate:** before anything else, the recomputed median read-out must equal the stored Segment 25 `HR_c` (A, B, C rows) and Segment 24 `HR_cW` (v7, v4, v6, D2 rows) for every clip/combiner to < 1e-4 bpm, and the recomputed baseline must equal the stored `HR_a` — else abort.
* **Strata (units):** MAIN_112, v7, v4, v6, v3, v5, C_v1_source3 = 7 strata; each holds at most one clip per person, so the unit is the clip/subject.
* **Test:** for each stratum × combiner, paired two-sided Wilcoxon signed-rank (`signrank`) on |error|(mean-aggregate) − |error|(median-aggregate). **14 tests, one Holm correction across all 14, α = 0.05** (this is the primary family). Also reported, descriptive (uncorrected): median vs (a) and mean vs (a) per stratum, and the "gain recovered by mean" = (MAE_a − MAE_mean) / (MAE_a − MAE_median) on the pooled degraded strata.
* **A-priori stratum classes (the brief's labels, fixed now):** DEGRADED = {v4, v6, v5}; CLEAN = {MAIN_112, v3, C_v1_source3}; v7 (after exercise) is **unclassified — reported, not in the rule**. Caveat stated in advance: v4 is bright-light and v6 is stable 1.5 m (not motion); "degraded" here is the brief's label for where Segments 24/25 saw the largest gains, not an independent measure of signal quality (Step 2 is the independent check).
* **Gap** = MAE(mean) − MAE(median), stratum-level, per combiner. Rules, evaluated separately for CHROM and POS:
  * **R1 — median clearly beats mean on degraded:** gap ≥ 0.5 bpm in ≥ 2 of the 3 DEGRADED strata **and** Holm p < 0.05 (mean worse) in ≥ 1 of them.
  * **R2 — roughly ties on clean:** |gap| < 0.5 bpm in ≥ 2 of the 3 CLEAN strata.
  * **R3 — mean ≈ median everywhere:** |gap| < 0.5 bpm in ≥ 5 of the 6 classified strata **and** no Holm-significant mean-vs-median difference among the 14 tests.
* **Step 1 outcome:** *median-rejection supported* if R1 and R2 hold for **both** combiners; *hypothesis wrong (mean ≈ median)* if R3 holds for both; otherwise *mixed*, reported with the per-combiner R1/R2/R3 flags as found.

## 2. Step 2 — does the gain track a quality proxy?

* **Outcome per clip:** improvement = |error|(fftHeartRate) − |error|(median read-out), bpm (positive = read-out better), per combiner. (The brief says MAE; per clip the MAE is the absolute error.)
* **Pool:** all clips of the five sets — MAIN_112, Segment 24 PRIMARY (v7/v4/v6), Segment 25 B (v3/v5), Segment 25 C, UBFC-D2. Pooled across all five.
* **Proxies — only what is already cached by the pipeline; nothing new is defined:**
  * **P1: `fs`** — cached sampling rate of the clip (time.txt-derived where the loader had it). Predicted direction: lower fs → larger gain (ρ < 0).
  * **P2: dropped-frame fraction** = `numDroppedFrames / numel(R)` from the ROI-extraction cache (frames where the face detector found nothing and the last box was reused = the pipeline's tracking-confidence signal). Predicted: ρ > 0. Clips whose cache does not store `numDroppedFrames` (e.g. UBFC-D2) are excluded from P2 only; n is reported.
  * **P3: mean raw ROI green level** = `mean(G)` of the cached ROI trace (the brightness statistic the ROI extraction already outputs). No direction predicted; note v4 (bright) and v5 (dark) both gained, so a non-monotone relation is possible and Spearman may miss it — that is accepted, no follow-up shape fitting.
  * Not used: cross-ROI PLV (needs the four-region caches that exist only for 20 subjects), notch confidence, any new SNR/quality metric.
* **Test:** ONE Spearman correlation per proxy per combiner = **6 tests, Holm across the 6, α = 0.05**. A proxy "correlates" if Holm p < 0.05 **and** |ρ| ≥ 0.10.
* **"Improvement correlates with a quality proxy"** = for **both** combiners, P1 (ρ < 0) or P2 (ρ > 0) correlates in its predicted direction, or P3 correlates (either sign).
* Descriptive, not part of the verdict: Spearman within each set (to expose set-composition confounding); disclosed limits — the same 107 people appear in several sets, so pooled clips are not independent (p-values optimistic), and every proxy is confounded with scenario/device.

## 3. Verdict rules (fixed now)

* Step 1 *median-rejection supported* **and** Step 2 correlates → **mechanism confirmed**: a principled, explainable robustness read-out; a dedicated later segment on production gating (activate only when a live quality proxy is low) is warranted (not started here).
* Step 1 *mean ≈ median* → the median-rejection hypothesis is wrong; something else about the windowing does the work; **mechanism still unknown**, reported as such (regardless of Step 2).
* Step 2 no correlation with any proxy → the degraded-condition pattern may be coincidental to this clip set rather than a real quality-dependent effect — stated plainly.
* Any other combination (e.g. Step 1 supported but Step 2 null; or *mixed*) is reported as found, with per-combiner flags; no stronger claim than the evidence.

## 4. One-shot rule

Once `scripts/s26_run.m` starts: no change to the aggregation, band, windows, strata, classes, thresholds, proxies, tests or definitions, regardless of outcome. Post-hoc analyses go in REPORT.md under an explicit "post-hoc, not pre-registered" heading.
