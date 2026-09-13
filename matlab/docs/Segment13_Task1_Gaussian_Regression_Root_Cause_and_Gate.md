# Segment 13 — Gaussian-Filter Regression Root Cause, and a Confidence-Gated Fix

Run 2026-09-13. Closes the open thread from
`docs/Segment12_Task2_Harmonic_Selective_Gaussian_Filter.md`: at alpha=0.15,
`morphology/harmonicSelectiveGaussianFilter.m` beats the current ABPF comb
on pass rate (31% vs. 24%), median waveform correlation (0.523 vs.
**0.519** — the doc's exact ABPF baseline, confirmed), and harmonic
confusion (3% vs. 5%), but 17/100 subjects showed a severe notch-confidence
regression. Neither the win nor the regression had been explained
mechanistically before this task — only measured.

**Headline results**:

- **Action 1 — root cause found, clean.** Every one of the 17 severely-
  regressing subjects was a subject the current ABPF comb ALREADY PASSED
  (notch confidence > 0.3) before any Gaussian filter was applied at all.
  Conditional regression rate: **17/24 (71%)** of ABPF-passing subjects
  regress severely under Gaussian(0.15); **0/76 (0%)** of ABPF-failing
  subjects do. Four other hypotheses (dataset, device/source, heart-rate
  range, skin-colour angle) were checked and explicitly ruled out or found
  inapplicable — reported below, not hidden.
- **Action 2 — a simple gating rule built on that factor gives a strictly
  non-regressive, genuinely better result than either method alone.** New
  `morphology/harmonicFilterConfidenceGate.m`: keep ABPF wherever it
  already passes; substitute Gaussian(0.15) only where ABPF fails. Result:
  pass rate **47%** (vs. ABPF's 24%, plain Gaussian(0.15)'s 31%), median
  notch confidence **0.235**, median waveform corr **0.522**, harmonic
  confusion **3%**, and **zero severe regressions, by construction**. A
  supplementary multi-candidate variant (pick whichever of several
  Gaussian alphas self-reports the highest confidence) pushes pass rate to
  64% but its median corr (0.508) is the WORST of every method compared —
  a clear, deliberately-surfaced selection-bias warning, not a better
  result. **Neither gate is wired into production** — both stay gated,
  off-by-default, per the brief.

Do-not-touch files (`chromCombine.m`, `posCombine.m`, `fftHeartRate.m`,
`adaptiveHarmonicFilter.m`, `bandpassMorphology.m`'s `'wide'` default,
`waveletDenoise.m`, `bandpassClean.m`, `extractROISignals.m`,
`estimateVitalsAndMorphology.m`) and the three previously-adopted files
named in the brief (`cpaceProjection.m`, `computeCrossROIPLV.m`,
`residualAdaptiveKalmanHR.m`) are untouched — confirmed via `git status`.

---

## Action 1 — Root cause

### Method

`matlab/scripts/run_segment13_task1_regression_root_cause.m` — read-only,
no video reprocessed. Pulls and joins per-subject results already on disk
from four prior sessions' own validated outputs (the same style of
investigation Segment 8 Task 3's source2-regression hunt used): Segment 10
Task 1's `frameRate`/`source`, Segment 11 Task 1's skin-colour angle
(computed for the **full 100-subject pool** by `cpaceProjection.m` — a
different, larger set than Segment 10 Task 3 Action 4's 25-subject cardiac-
angle cohort, not to be confused with it), Segment 12 Task 2's freshly-
recomputed ABPF branch (already regression-checked 100/100 against Task
1's own cache in that task), and Segment 12 Task 2b's alpha=0.15 Gaussian
branch. Severe regression defined exactly as Task 2's own doc did: a
notch-confidence drop greater than 0.3.

### The five hypotheses, all reported (per the brief: "whichever you check
and rule out, not just the one that sticks")

| # | Hypothesis | Pool | Regressors (n=17) | Verdict |
|---|---|---|---|---|
| H1 | Dataset | UBFC-D1=5, VIPL=95 | UBFC-D1=2/5 (40%), VIPL=15/95 (16%) | **Not a clean separator** — UBFC's share is higher but n=5 is too small to be a stable signal |
| H2 | Device/source | all webcam (UBFC webcam or VIPL v1/source1) | — | **Inapplicable** — no variation exists in this pool to test |
| H3 | Heart rate (sharedF0Hz×60) | median 72.2, IQR [64.1, 77.6] | median 76.8, IQR [72.7, 87.7] | **Not a clean separator** — regressor range overlaps the pool's own IQR substantially |
| H4 | Skin-colour angle | n=100, median 8.61°, IQR [5.64°, 10.09°] | n=17, median 7.80°, range [1.70°, 13.00°] | **Ruled out** — regressor median sits inside the pool's own IQR |
| H5 | Baseline ABPF pass/fail | pass=24, fail=76 | **17/17 (100%) were ABPF-pass**, 0/17 were ABPF-fail | **Clean separator** |

Full per-subject table:
`results/metrics/segment13_task1_regression_root_cause.csv`. Figure:
`results/figures/segment13_task1_regression_vs_baseline.png` — plots
Δnotch-confidence against baseline ABPF confidence directly; every severe
regression sits to the right of the 0.3 pass bar, and the scatter shows a
visible downward trend (higher baseline confidence → larger drop), a
ceiling-style pattern consistent with `notchDetectIEM.m`'s own documented
`min(1, ...)` confidence clip (its header already states values above 1
all read as an identical 1.0000 — several of the 17 regressors sit exactly
at that clipped ceiling, e.g. `12-gt`, `VIPL_p50`, `VIPL_p85`, `VIPL_p29`,
`VIPL_p52`, `VIPL_p80`, `VIPL_p79` are all at 1.000 before the Gaussian
filter is applied).

### Why this makes mechanistic sense

A subject already at or near ABPF's confidence ceiling has, by
construction, far more room to fall than to rise — any change to the
underlying beat shape (whether from ABPF to Gaussian, or from any other
perturbation) is far more likely to *reduce* an already-maximal IEM
residual score than to improve it further. A subject ABPF already fails
has the opposite asymmetry: it has more room to rise than to fall further
into an already-low score. This is not a claim that Gaussian(0.15) is
"worse" in some general sense — it is a claim that swapping filters
pool-wide inevitably perturbs every subject's beat shape somewhat, and
that perturbation reads as a "regression" only where there was a fragile,
possibly-clipped high score to lose in the first place. Waveform
correlation (a continuous, non-clipped metric) does NOT show the same
one-sided pattern for these same 17 subjects — several have corr roughly
unchanged or even improved (e.g. `7-gt` 0.240→0.509, `VIPL_p19`
0.573→0.622) even as notch confidence collapses — reinforcing that this is
specifically about `notchDetectIEM.m`'s own brittleness at high scores,
not a general fidelity loss for these subjects.

---

## Action 2 — A confidence-gated selection rule

### Method

New `matlab/src/morphology/harmonicFilterConfidenceGate.m` — generic,
reusable, NOT wired into `pipeline/estimateVitalsAndMorphology.m` or any
other production call site. Takes a primary signal + its own notch
confidence, and one or more fallback candidates + their own confidences;
keeps the primary if its confidence already clears the 0.3 bar, otherwise
substitutes whichever fallback (or, with a single fallback, that one)
scores highest. Evaluated on real, freshly recomputed signals — not just
arithmetic on cached CSV numbers — via
`matlab/scripts/run_segment13_task2_gated_selection_evaluation.m`, which
recomputes ABPF and three Gaussian alphas (0.10, 0.15, 0.20) per subject
from `_rgb_traces.mat` directly, then calls the new gate function on the
real signal vectors it produces.

### Result

| Condition | n | pass rate | median notch conf | median waveform corr | harmonic confusion | severe regressions vs. ABPF |
|---|---|---|---|---|---|---|
| ABPF (current) | 100 | 24% | 0.058 | 0.519 | 5% | — |
| Gaussian, alpha=0.15 alone | 100 | 31% | 0.090 | 0.523 | 3% | 17 |
| **Safe gate** (ABPF, single 0.15 fallback) | 100 | **47%** | **0.235** | **0.522** | **3%** | **0** |
| Multi-candidate gate (ABPF + 0.10/0.15/0.20, best-wins) | 100 | 64% | 0.482 | 0.508 | 3% | 0 |

Full table: `results/metrics/segment13_task2_gated_evaluation.csv`.
Figures: `results/figures/segment13_task2_summary_bars.png`,
`results/figures/segment13_task2_safegate_paired.png`.

**The safe gate substitutes 76 of 100 subjects** (every subject ABPF
already failed) and **has zero severe regressions by construction** — it
literally cannot turn an ABPF-passing subject into a failing one, since it
never touches those subjects at all. Pass rate very nearly doubles (24%→
47%) and median waveform correlation and harmonic confusion both improve
slightly too, as a genuine (not circular) consequence: the gating decision
uses only the ABPF confidence signal, never corr, so the corr improvement
is a real side effect, not an artifact of the selection rule.

**Honest cost, stated plainly**: among the 76 substituted subjects,
waveform correlation improves for 45 and regresses for 31 (not shown as
severe by the notch-confidence measure, since none of these subjects were
passing to begin with — but a real, smaller-magnitude trade nonetheless,
not a free lunch even in the safe configuration).

### The warning the multi-candidate variant demonstrates on real data

Extending the same fallback slot to three Gaussian alphas (pick whichever
self-reports the highest confidence) pushes pass rate to 64% and median
notch confidence to 0.482 — both look spectacular — but **median waveform
correlation (0.508) is the WORST of every method compared, including plain
ABPF (0.519)**. Because `notchConfidence` is computed without any ground
truth, this selection rule is fully causal and deployable (not circular in
the GT-leakage sense) — but repeatedly picking whichever of several noisy
candidates happens to score highest inflates that very score without a
corresponding real fidelity gain, exactly the kind of "different metrics
disagree, don't cherry-pick the flattering one" caution this project's
evaluation discipline exists to catch. `harmonicFilterConfidenceGate.m`'s
own header states this warning explicitly so a future session does not
have to rediscover it.

---

## Recommendation

**The safe gate (`harmonicFilterConfidenceGate.m`, ABPF primary + single
alpha=0.15 fallback) is the most well-supported single result across
Segments 11-13's entire cPACE/mid-band/Gaussian-filter investigation
line** — it beats both of its own ingredients on pass rate and ties or
beats them on median correlation and harmonic confusion, with a
zero-severe-regression guarantee that is structural, not empirical. **It
is nonetheless NOT adopted or wired into production**, per the brief's own
instruction and this project's standing "no adoption without a full
ablation, small-scale-first" discipline — it stays a new, gated,
off-by-default utility function, exercised end-to-end in this task's own
evaluation script but not called from `pipeline/
estimateVitalsAndMorphology.m` or anywhere else.

**The multi-candidate variant should NOT be used** in its tested form —
its own evaluation demonstrates why. A future session interested in
pushing further should look at genuinely independent signals for the
selection decision (e.g. cross-ROI PLV, which needs no ground truth either
but is a different, less brittle metric than `notchConfidence` alone) not
at adding more self-scored candidates to choose from.

## Files

- `matlab/src/morphology/harmonicFilterConfidenceGate.m`
- `matlab/scripts/run_segment13_task1_regression_root_cause.m`
- `matlab/scripts/run_segment13_task2_gated_selection_evaluation.m`
- `results/metrics/segment13_task1_regression_root_cause.csv`
- `results/metrics/segment13_task2_gated_evaluation.csv`
- `results/figures/segment13_task1_regression_vs_baseline.png`
- `results/figures/segment13_task2_summary_bars.png`
- `results/figures/segment13_task2_safegate_paired.png`
