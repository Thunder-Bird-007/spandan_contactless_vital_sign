# Segment 15 Task 3 — Eigen-Window Half-Width (bw) Sweep

Run 2026-09-14, on Spandan's real 100-subject pool (5 UBFC-D1 + 95 VIPL
v1/source1 — the same pool every Segment 10-14 evaluation has used; no
cached/synthetic subset). Not a pooled-medians-only report — per-subject
results below, per this project's standing evaluation-honesty discipline.

**Headline: bw is confirmed the sensitive parameter the paper's own
Supplement flags it as — but the swing on this project's real data is far
larger than the paper's own reported 0.99–2.88 BPM, and it is driven by a
small number of subjects swinging catastrophically, not a uniform shift.**
`fenv` and κ were NOT swept, per the brief — the paper's own sensitivity
analysis found both negligible (see `Segment15_Task2_cPACE_Homodyne.md`).

---

## 1. Pooled numbers (orientation only — see §2/§3 for the real finding)

| bw (Hz) | Pooled HR MAE (n=100) | UBFC-D1 subset (n=5) | VIPL subset (n=95) |
|---|---|---|---|
| 0.15 | 8.66 | 3.18 | 8.95 |
| 0.30 (Table S2 default) | 10.12 | 2.44 | 10.53 |
| 0.50 | 12.38 | **14.91** | 12.25 |

The UBFC-D1 subset's bw=0.50 number (14.91) looks like a uniform
degradation from a pooled table alone. **It is not** — see §2.

## 2. Per-subject regressions vs. bw=0.30 (>1 BPM worse)

Using bw=0.30 (Table S2's default) as the reference, per-subject absolute
HR error at bw=0.15 and bw=0.50:

| Comparison | Subjects regressing >1 BPM | Rate |
|---|---|---|
| bw=0.15 vs. bw=0.30 | 9 / 100 | 9% |
| bw=0.50 vs. bw=0.30 | 25 / 100 | 25% |

Full per-subject table:
`results/metrics/segment15_task3_bw_sweep_per_subject_regressions.csv`.
Figure: `results/figures/segment15_bw_sweep_per_subject.png` (per-subject
lines in grey, median in red).

**The two subjects behind the UBFC-D1 bw=0.50 pooled number** (`5-gt`,
`6-gt` — both from the tiny 5-subject legacy UBFC-D1 pool):

| Subject | absErr @ bw=0.30 | absErr @ bw=0.50 | Δ |
|---|---|---|---|
| `5-gt` | 0.91 BPM | 23.76 BPM | **+22.85** |
| `6-gt` | 0.45 BPM | 39.98 BPM | **+39.54** |

These two subjects alone account for essentially all of the UBFC-D1
pooled MAE jump from 2.44 to 14.91 — the other 3 UBFC-D1 subjects are
comparatively stable. This is exactly the failure mode Segment 12's
17-subject Gaussian-filter regression already taught this project to
check for: a pooled number that looks like a uniform effect can be a
small number of subjects swinging catastrophically. **A pooled MAE swing
alone would have badly understated how bad bw=0.50 can get for an
individual subject** — the paper's own reported 0.99–2.88 BPM pooled
swing (Supplement 1 §S.6, on CMU cohorts) is not visible at the
per-subject level on this project's data; per-subject swings up to
~40 BPM occur.

On the VIPL side, the largest individual bw=0.50-vs-0.30 regressions
include `6-gt`-scale subjects too — see the CSV for the full list; the
worst VIPL regressions in this sweep exceed 10 BPM for several subjects
(e.g. `VIPL_p3_v1_source1`: 11.0 → 24.9 BPM).

## 3. Direction of the effect

Narrower (bw=0.15) is better than the paper's own default (bw=0.30) on
this project's pooled numbers (8.66 vs. 10.12 BPM), and bw=0.30 is better
than bw=0.50 (10.12 vs. 12.38 BPM) — narrower is monotonically better in
the pooled sense on this cohort, consistent with the paper's own caution
(Supplement 1 §S.6): *"this cohort has a limited heart-rate range...
narrower eigen-windows happen to fit this range well... a method intended
for deployment on populations with substantial heart-rate variability...
would benefit from a wider eigen-window or an adaptive seed-tracking
mechanism."* This project's own cohort (UBFC-D1 + VIPL v1/source1, mostly
resting subjects) is exactly this narrow-HR-range regime, so this
direction is expected, not a contradiction of the paper.

**This does not change the recommendation.** Even at its best pooled bw
(0.15), the full Stage1+2+3 pipeline (MAE 8.66) does not beat production
POS/CHROM (MAE 7.86–7.87) on this pool — see
`Segment15_Task4_Evaluation.md`. The bw sweep changes how bad the
regression is, not whether there is one.

## Files

- `results/metrics/segment15_task3_bw_sweep_per_subject_regressions.csv`
- `results/figures/segment15_bw_sweep_per_subject.png`
- Produced by `matlab/scripts/run_segment15_task3_task4_cpace_full_evaluation.m`
