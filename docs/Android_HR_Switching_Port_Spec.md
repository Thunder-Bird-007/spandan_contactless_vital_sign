# Android HR Switching Port Spec

**Purpose:** this document specifies a CHROM/POS switching rule for
picking the displayed heart-rate (HR) estimate in the Android app. It is
written to be usable by someone who has **not** read the MATLAB pipeline
source — every formula, number, and caveat needed to implement this on
Android is stated here in full, with no external lookups required.

**Origin:** this rule comes from a MATLAB-side, post-hoc analysis
(`spandan` project, Segment 6 "Task J", 2026-08-08) over already-computed
HR results. It does not change how CHROM or POS themselves are computed
— it only decides, per reading, which of the two already-computed values
to show the user.

---

## 1. Background: what CHROM and POS are, in this app's context

The app's rPPG pipeline already computes **two independent HR estimates**
from the same face-ROI signal for every window:

- **CHROM** — a chrominance-based combination of the R/G/B channel
  traces, currently the app's primary displayed value.
- **POS** — a plane-orthogonal-to-skin combination of the same R/G/B
  traces, currently computed alongside CHROM but only logged, not shown.

Both are run through the same bandpass filter and FFT-peak HR extraction
logic. Because they're two different linear combinations of the same
channels, they usually agree closely, but occasionally lock onto
different spectral peaks and disagree sharply.

## 2. The metric: relative disagreement

For a single reading with `HR_chrom` and `HR_pos` (both in bpm):

```
relative_disagreement = abs(HR_chrom - HR_pos) / mean(HR_chrom, HR_pos)
```

This is a **fraction** (0.0 to 1.0+), not a percentage. Multiply by 100
to get a percentage for display/logging purposes only.

Example: `HR_chrom = 127.20`, `HR_pos = 68.84`.
`mean = 98.02`. `abs(127.20 - 68.84) = 58.36`.
`relative_disagreement = 58.36 / 98.02 = 0.5954` (59.54%).

## 3. The threshold: 29.27% relative disagreement

**Value: `0.2927` (29.27%).**

**Where this number came from** (so it is not mistaken for an arbitrary
round number): it was derived on the MATLAB side ("Task I", the analysis
step immediately prior to this one) from the full pool of 112 subjects
across both datasets used in this project (UBFC-rPPG + VIPL-HR). Every
subject's `relative_disagreement` was computed and sorted. Two things
were found:

- 77 of 112 subjects (69%) have `relative_disagreement = 0` exactly
  (CHROM and POS bit-identical for that subject in this pipeline).
- Among the subjects with non-zero disagreement, the values climb fairly
  continuously from 0% up through the 20s%, then there is a **gap of
  9.69 percentage points with no subjects in it, sitting right above
  29.27%**. Below that gap: a dense, continuously-populated mass of
  values. Above it: 8 subjects isolated in a sparse tail running from
  38.96% up to 90.08%.

That gap is a genuine natural separator between "the two methods broadly
agree" and "the two methods have diverged onto different answers" — not
a value picked in advance and not a single-outlier artifact (a second,
larger gap exists but isolates only one subject by itself, which was
judged too thin a basis for a general rule). **29.27% is this gap's
lower boundary, taken directly from the data.** If the underlying pool
is ever re-analyzed with more/different subjects, this number could
shift — it is a measured property of this project's current dataset,
not a physical constant.

## 4. The decision rule

Per reading:

```
if relative_disagreement < 0.2927:
    HR_displayed = HR_chrom
else:
    HR_displayed = HR_pos
```

That is the entire rule. No other inputs, no smoothing across readings,
no hysteresis — this spec covers a single-reading decision only.

**Android implementation note:** the app already computes both values in
the same place (`RealHeartRateEstimator.kt`'s `Estimate(chromBpm,
posBpm)` result, currently only `chromBpm` is returned/displayed while
`posBpm` is logged alongside it). Implementing this rule means computing
`relative_disagreement` from that existing pair and returning
`chromBpm` or `posBpm` accordingly, instead of always returning
`chromBpm`. No new signal processing is required — both inputs already
exist at the point this decision needs to be made.

## 5. Validation: full-pool comparison (with an honest caveat)

**Caveat, stated plainly:** the numbers below were computed on the
**same 112-subject pool that the 29.27% threshold itself was derived
from** (Section 3). This is **not** a clean out-of-sample validation —
the threshold was tuned to a gap found in this exact data, so some
degree of the improvement below could be specific to this pool rather
than a guaranteed generalizable gain. Report these numbers as "measured
on this pool," never as a guarantee of the same improvement on new,
unseen subjects (e.g. once a live oximeter/PPG reference is added, or
when a different dataset is used).

With that caveat, applying the switching rule to all 112 subjects:

| Method | N | MAE (bpm) | RMSE (bpm) | Pearson r |
|---|---|---|---|---|
| CHROM alone | 112 | 9.0969 | 18.0047 | 0.3145 |
| POS alone | 112 | 8.6795 | 16.4537 | 0.2809 |
| **Switched (this rule)** | 112 | **8.2658** | **16.0007** | **0.3246** |

The switched estimator beats both individual methods on every metric at
this pool: MAE drops 9.2% versus CHROM alone (9.10 → 8.27 bpm) and 4.8%
versus POS alone (8.68 → 8.27 bpm); RMSE and Pearson r move the same
direction. The switch fired (selected POS over CHROM) for **8 of 112
subjects (7.14%)** — a small fraction of readings, consistent with 69%
of the pool having zero disagreement at all.

## 6. Known structural blind spot

This rule can only catch the failure mode where CHROM and POS
**disagree** with each other. It is structurally blind to the failure
mode where **both methods lock onto the same wrong answer** — if CHROM
and POS agree, `relative_disagreement` is low (or zero) regardless of
whether that agreed-upon value is actually correct.

This is not a hypothetical concern: in this project's worst-5 HR-error
subjects (identified in an earlier diagnostic pass, "Task H1"), exactly
**2 of the 5** (`p22` and `p35`) show this pattern — CHROM and POS both
converge on the same spectral peak that turns out to be wrong (`p22`:
both ~112.5 bpm against a 47 bpm true rate; `p35`: both ~133.5 bpm
against a 77.68 bpm true rate). Neither of those two subjects would be
flagged or corrected by this rule, at any threshold, because there is no
disagreement between the two methods to detect. **This rule should be
communicated as one useful signal among several needed for a complete
confidence indicator, not as a complete solution to bad readings.**

## 7. Failure-mode check: does switching ever pick the worse estimate?

Even restricted to the 8 subjects where the switch actually fired
(Section 5), switching to POS is not a guaranteed improvement for that
specific subject — it is a rule that is usually right, not always right:

| Outcome (of the 8 switched subjects) | Count |
|---|---|
| Switch **helped** (POS error < CHROM error for that subject) | 5 |
| Switch **hurt** (POS error > CHROM error for that subject) | 3 |
| Tied | 0 |

So among the subjects where CHROM/POS disagreement crossed the
threshold, switching to POS was the right call **5 times out of 8
(62.5%)** and the wrong call **3 times out of 8 (37.5%)** — it made that
specific subject's error larger, not smaller, in those 3 cases. The
aggregate pool-level improvement in Section 5 is real and net-positive,
but it is an average outcome, not a per-subject guarantee: "the methods
disagree, so use POS" is reliably the better *average* choice at this
pool size, not a rule that is individually correct every time it fires.
Any UI built on this rule should reflect that framing (e.g. a
lower-confidence indicator on switched readings, not a claim that the
switched value is definitely more accurate than CHROM would have been
for that specific reading).

## 8. Summary for implementers

1. Compute `HR_chrom` and `HR_pos` as already done (no change).
2. Compute `relative_disagreement = abs(HR_chrom - HR_pos) / mean(HR_chrom, HR_pos)`.
3. If `relative_disagreement < 0.2927`, display `HR_chrom`. Otherwise, display `HR_pos`.
4. Optionally surface `relative_disagreement >= 0.2927` as a
   lower-confidence indicator in the UI, since it also flags exactly this
   condition.
5. Do **not** present this as a complete accuracy fix — it addresses one
   specific, disagreement-based failure mode (Section 5's ~9% MAE gain
   on this pool) and is blind by construction to the same-wrong-peak
   failure mode (Section 6), and even within its own scope it is right
   about 5 times out of every 8 it fires, not 8 out of 8 (Section 7).
