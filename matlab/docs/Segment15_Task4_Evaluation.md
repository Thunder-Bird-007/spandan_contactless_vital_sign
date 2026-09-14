# Segment 15 Task 4 — Full Stage1+2+3 cPACE Evaluation

Run 2026-09-14, on the same real 100-subject pool (HR/waveform) and
20-subject VIPL v1/source1 multi-region pool (cross-ROI PLV) every
Segment 10-14 evaluation has used. Compares full Stage1+2+3 cPACE against
(a) current production (POS/CHROM, no cPACE) and (b) Stage-1-only cPACE
(Segment 11 Task 1, for reference).

**Headline: the full pipeline does not beat production on this project's
cohort, at any bw tested — a real, replicated regression, not a bug.**
Cross-ROI PLV improves slightly. **Kept gated/off-by-default**, consistent
with `cpaceProjection.m` and `harmonicFilterConfidenceGate.m`'s own
promotion discipline — this task's job is an honest result, not a
promotion.

---

## 1. Pooled HR accuracy (7 pipelines, n=100)

| Pipeline | MAE (BPM) | RMSE | Pearson r | median waveform corr | harmonic confusion |
|---|---|---|---|---|---|
| **POS** (production) | **7.87** | 16.35 | 0.311 | 0.452 | 0.0% |
| **CHROM** (production) | **7.86** | 16.74 | 0.365 | 0.445 | 0.0% |
| cPACE-Stage1+POS | 7.87 | 16.35 | 0.311 | 0.452 | 0.0% |
| cPACE-Stage1+CHROM | 8.72 | 19.05 | 0.275 | 0.417 | 0.0% |
| cPACE-Full, bw=0.15 | 8.66 | 13.42 | 0.499 | 0.484 | 0.0% |
| cPACE-Full, bw=0.30 (Table S2 default) | 10.12 | 14.66 | 0.461 | 0.390 | 1.0% |
| cPACE-Full, bw=0.50 | 12.38 | 17.10 | 0.448 | 0.311 | 3.0% |

`cPACE-Stage1+POS` reproduces Segment 11's own exact-no-op finding for
POS bit-for-bit (7.87 MAE, identical RMSE/r/corr) — expected, since
`cpaceProjection.m` was not touched. `cPACE-Stage1+CHROM`'s modest
regression (8.72 vs. 7.86) also reproduces Segment 11's own finding.

**None of the three full-pipeline bw variants beat production MAE**, even
though bw=0.15's Pearson r (0.499) and median waveform correlation
(0.484) are both the best of any pipeline tested, including production —
a genuinely interesting, mixed result: the full pipeline correlates
better with ground truth in shape/timing at bw=0.15 while still being
worse on raw peak-frequency (MAE) accuracy on average, pulled down by a
tail of badly-wrong subjects (§2).

## 2. Per-subject regressions — the real finding, not the pooled table

Full per-subject table:
`results/metrics/segment15_task4_vs_production_per_subject_regressions.csv`
(bw=0.30, Table S2's default, used as the "the full pipeline" reference
throughout this section — bw=0.15 is pooled-better but not swept for this
per-subject comparison; see `Segment15_Task3_Hyperparameter_Sweep.md`).

| Comparison (>1 BPM worse counts as regressing) | Subjects regressing | Rate |
|---|---|---|
| cPACE-Full (bw=0.30) vs. POS | 42 / 100 | 42% |
| cPACE-Full (bw=0.30) vs. CHROM | 40 / 100 | 40% |
| cPACE-Full (bw=0.30) vs. Stage1+POS | 42 / 100 | 42% |
| cPACE-Full (bw=0.30) vs. Stage1+CHROM | 42 / 100 | 42% |

**24 of those 100 subjects regress SEVERELY (>10 BPM worse) vs. POS** —
not a marginal effect for this group. A sample (full list in the CSV):

| Subject | absErr, POS | absErr, cPACE-Full bw=0.30 |
|---|---|---|
| VIPL_p10_v1_source1 | 39.17 | 55.20 |
| VIPL_p64_v1_source1 | 12.71 | 38.65 |
| VIPL_p24_v1_source1 | 17.31 | 31.28 |
| VIPL_p90_v1_source1 | 2.34 | 32.17 |
| VIPL_p51_v1_source1 | 14.64 | 27.36 |
| VIPL_p85_v1_source1 | 0.44 | 27.17 |

Several of these (e.g. `VIPL_p90`, `VIPL_p85`, `VIPL_p50`, `VIPL_p8`) were
already-accurate subjects under POS (sub-3 BPM error) that the full cPACE
pipeline makes badly wrong — the opposite of what adopting it would need
to show. This matches this project's own recurring pattern (Segment 11's
CHROM regression, Segment 12's 17-subject Gaussian-filter regression):
**a pooled-average comparison alone would understate the size and
one-sidedness of this effect.**

## 3. Cross-ROI PLV (n=20, VIPL v1/source1 multi-region pool)

| Pipeline | mean PLV | median PLV |
|---|---|---|
| POS | 0.271 | 0.256 |
| CHROM | 0.254 | 0.249 |
| cPACE-Stage1+POS | 0.271 | 0.256 |
| cPACE-Stage1+CHROM | 0.241 | 0.226 |
| cPACE-Full, bw=0.15 | 0.294 | 0.290 |
| **cPACE-Full, bw=0.30** | **0.295** | 0.266 |
| cPACE-Full, bw=0.50 | 0.282 | 0.247 |

**The full pipeline does genuinely improve cross-ROI phase coherence**
over both production combiners, at every bw tested — a real, if modest,
result in the direction the paper's own central claim predicts (cleaner
per-ROI cardiac-direction estimation → more phase-locked signals across
regions sharing an arterial supply). This is measured on only 20 subjects
(the same pool `computeCrossROIPLV.m` has always used), so treat the
exact magnitude as indicative, not definitive.

**This is the mixed result worth remembering**: full cPACE trades HR-MAE
accuracy for phase coherence on this cohort. Table S2/Section 4's
described method is fundamentally about phase fidelity (that's what
"phase-aware" in the method's own name refers to) — this project's
PLV-vs-MAE split is consistent with that design intent even where the
net HR-accuracy outcome is a regression here.

## 4. Numerical health check

Eigenvalue ratio (λ1/λ2) at bw=0.30, across the 100-subject pool: median
4.81, mean 18.70 (min 1.20, max 315.96); 12/100 subjects have λ1/λ2 < 2 —
a genuinely weak/ambiguous cardiac direction for those subjects. This is
lower than the paper's own single reported example (~392, a favorable
dark-skinned subject) — consistent with Segment 11's own finding that
this project's cohort sits in the paper's least-favorable (low
skin-colour-angle) regime for cPACE's underlying mechanism.

## 5. Why this cohort, specifically

This project's evaluation pool (UBFC-D1 + VIPL v1/source1) is
light-skinned and low-motion (Segment 11's own median skin-colour angle:
8.61°) — squarely the regime the paper's own Supplement 1 identifies as
giving cPACE its smallest predicted gains (isochromatic leakage is small
when POS/CHROM's fixed bases are already near-orthogonal to q̂). Neither
this result nor Segment 11's Stage-1-only result contradicts the paper's
own reported gains on darker-skinned cohorts (CMU-rPPG India/Sierra
Leone) — this project has never had a comparable cohort to test that
regime on. **This remains an open item for any future darker-skinned
cohort this project acquires** (e.g. the previously-flagged Bangladeshi
self-collected set), carried forward from Segment 11's own doc.

## 6. Recommendation

**Not adopted. Kept gated/off-by-default**, exactly like `cpaceProjection.m`
(Segment 11) and `harmonicFilterConfidenceGate.m`'s multi-candidate mode
(Segment 13) — this task's job was to produce an honest, real-data result,
not to promote anything to production. `cpaceEigenExtract.m` and
`cpaceHomodyneNormalize.m` remain available, off by default, for future
experimentation (e.g. once a higher-θ cohort exists, or if an adaptive/
windowed seed-tracking refinement is attempted per the paper's own §S.4
caution about fixed heart-rate-range cohorts).

## Files

- `matlab/scripts/run_segment15_task3_task4_cpace_full_evaluation.m`
- `results/metrics/segment15_cpace_full_per_subject_hr.csv`
- `results/metrics/segment15_cpace_full_summary_hr.csv`
- `results/metrics/segment15_cpace_full_per_subject_plv.csv`
- `results/metrics/segment15_cpace_full_summary_plv.csv`
- `results/metrics/segment15_task4_vs_production_per_subject_regressions.csv`
- `results/figures/segment15_hr_mae_by_pipeline.png`
- `results/figures/segment15_plv_by_pipeline.png`
