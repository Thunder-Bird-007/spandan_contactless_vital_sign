# Segment 14 Task 2 — Confidence Gate Promoted to Branch 2's Production Default

Run 2026-09-13. Promotes `morphology/harmonicFilterConfidenceGate.m`
(built and evaluated in Segment 13) from an off-by-default utility to
Branch 2's production default, replacing plain
`morphology/adaptiveHarmonicFilter.m` (ABPF) wherever Branch 2's
orchestrator runs — gated behind a named toggle, exactly the pattern
Segment 8 Action 7 used to promote wavelet denoising. Held-out validation
(Segment 14 Task 1, UBFC DATASET_2, n=33 valid subjects) is now part of
the evidence base, not just the original 100-subject audit pool.

**The gate's logic itself is unchanged from Segment 13 and was not
re-derived here**: keep `adaptiveHarmonicFilter.m`'s ABPF output wherever
its own notch confidence already clears this project's 0.3 bar; substitute
`morphology/harmonicSelectiveGaussianFilter.m` (alpha=0.15) only where ABPF
fails.

**Headline: promoted, with one important, explicitly-reported caveat** —
the gate shows a real, replicated improvement on both large pools tested
(100-subject audit pool, 33-subject held-out UBFC-D2) but makes **zero
difference** on the tiny 5-subject legacy UBFC-D1 benchmark this project's
own long-standing "4/5" headline number comes from, because only one of
those 5 subjects is even eligible for substitution (ABPF already passes
the other 4), and that one subject isn't rescued by Gaussian(0.15) either.
Stated plainly below, not smoothed over.

---

## 1. Evidence base, side by side

| Pool | n | ABPF pass | Gaussian(0.15) pass | **Gate pass** | ABPF median corr | Gaussian median corr | **Gate median corr** | Severe regressions (Gaussian alone) | Severe regressions (gate) |
|---|---|---|---|---|---|---|---|---|---|
| Segment 10 Task 1 audit pool (5 UBFC-D1 + 95 VIPL v1/source1) | 100 | 24% | 31% | **47%** | 0.519 | 0.523 | **0.522** | 17 | **0** |
| Segment 14 Task 1 held-out (UBFC DATASET_2) | 33 (of 42 -- see its own doc §3) | 45% | 18% | **58%** | 0.364 | 0.604 | **0.520** | 13 | **0** |
| **Legacy 5-subject UBFC-D1 benchmark** (`segment7_task_b_notch_branch2.csv`) | 5 | **4/5** | not run at this scale | **4/5 (unchanged)** | not tracked by this script | not tracked | not tracked | n/a | 0 |

**The gate's central claim — it never turns an already-passing subject
into a failing one — holds on every pool tested, including the two real
generalization checks (audit pool, held-out UBFC-D2), zero exceptions
across 133 subjects total.** Pass rate and (mostly) median correlation
improve on both of the two large pools; the direction replicates even
though the exact magnitudes differ (a real population difference between
a VIPL-dominated pool and an all-UBFC held-out set, not a contradiction —
see each pool's own doc for detail:
`docs/Segment13_Task1_Gaussian_Regression_Root_Cause_and_Gate.md`,
`docs/Segment14_Task1_UBFC_D2_Held_Out_Validation.md`).

### The legacy 5-subject benchmark: no change, reported honestly

`results/metrics/segment7_task_b_notch_branch2.csv` (regenerated this
session, old version preserved as
`segment7_task_b_notch_branch2_preconfidencegate.csv`) now carries a third
`confidenceGate` row per subject alongside the unchanged `adaptiveHarmonic`
and `tiledROI` rows:

| Subject | ABPF confidence | Gate confidence | Gate method used | Substituted? |
|---|---|---|---|---|
| 5-gt | 0.7447 | 0.7447 | adaptiveHarmonic | no |
| 6-gt | 0.4120 | 0.4120 | adaptiveHarmonic | no |
| 7-gt | 0.6405 | 0.6405 | adaptiveHarmonic | no |
| 12-gt | 1.0000 | 1.0000 | adaptiveHarmonic | no |
| after-exercise | 0.1582 | **0.0011** | gaussian015 | **yes** |

**4 of 5 subjects are untouched by construction** (ABPF already passes).
The one eligible subject, `after-exercise` (elevated post-exercise heart
rate), is substituted — and gets WORSE, not better (0.1582 → 0.0011) —
though it was already failing the 0.3 bar before and after, so **the pass
count is exactly 4/5 under both the old and new default, unchanged.** This
is not a contradiction of the promotion decision: N=5 with only 1 eligible
subject is far too small to expect the gate's pool-level ~13-23 percentage
point improvement to show up, and this project's own standing "thin
UBFC-only data" caveat already applies to every number from this
particular 5-subject set. It is reported here specifically so the
project's own oldest, most-quoted Branch 2 number is not silently implied
to have improved when it did not.

---

## 2. Wiring (Action 2)

**Checked first, per the brief's own instruction, rather than assumed**:
`scripts/run_segment3_filtering_batch.m` and `run_vipl_integration_batch.m`
(the scripts the brief specifically named to check) do **NOT** call
`adaptiveHarmonicFilter.m` at all — confirmed by direct search. Those are
Branch 1 (HR/SpO2) production scripts; Branch 2 has never run through
them. `scripts/run_spandan_interactive.m` DOES reference
`adaptiveHarmonicFilter.m`, but only via its own embedded standalone COPY
of the function (a self-contained interactive demo script, not the shared
production orchestrator) — left untouched, out of scope (it is a
demo/report tool, not what any production metrics CSV is generated from).

**The real production Branch 2 orchestrator** is
`pipeline/estimateVitalsAndMorphology.m` (Segment 7 Task F), explicitly
documented in its own header as "the orchestrator used from this point
on." Changes:

- New `opts.useConfidenceGate` parameter, **default `true`**. When true
  (now the default), Branch 2 computes ABPF as before; if and only if
  ABPF's own notch confidence fails the 0.3 bar, it ALSO computes the
  Gaussian(0.15) candidate and calls `harmonicFilterConfidenceGate.m` to
  decide — cheap by construction, since the common already-passing case
  never touches the Gaussian path.
- New `branch2` fields for provenance: `harmonicMethodUsed`
  (`'adaptiveHarmonic'` or `'gaussian015'`), `gateSubstituted`,
  `abpfNotchConfidence` (preserved even when substituted), and
  `gaussianNotchConfidence` (`NaN` if never computed). Echoed at the
  top level too as `result.notch.methodUsed`.
- Set `opts.useConfidenceGate = false` to reproduce the exact
  pre-2026-09-13 ABPF-only behavior.

**Regression test updated, re-run, confirmed passing**:
`tests/segment7_task_f_regression_test.m`'s Part 3 (which checks
`result.notch.*` against `segment7_task_b_notch_branch2.csv`'s
`'adaptiveHarmonic'` row BY NAME) now explicitly passes
`'useConfidenceGate', false`, since it is testing that specific named
condition, independent of whatever the production default is. **Full
re-run this session: Parts 1, 2, and 3 all PASS**, confirming this
promotion did not silently break Branch 1, the SpO2 path, or the
ABPF-only legacy path.

`scripts/run_segment7_task_b_branch2_batch.m` (the script that generates
the cited `segment7_task_b_notch_branch2.csv`) updated to compute and
write the same `confidenceGate` condition per subject, additively (the
existing `adaptiveHarmonic`/`tiledROI` computations are byte-for-byte
unchanged — confirmed identical to the pre-promotion snapshot). Old file
preserved as `segment7_task_b_notch_branch2_preconfidencegate.csv`, same
"old numbers preserved alongside" convention Segment 8 Action 7 used.

---

## 3. Android (Action 3) — checked, not ported

Confirmed directly from two existing Android docs, not guessed:

- `android/docs/Defense_Readiness_Checklist.md`: *"No MATLAB-side findings
  from Tasks L/N/O/P are being ported into the Android app. The app ships
  the original validated pipeline: single forehead ROI, whole-clip FFT, no
  windowing/continuity/multi-region logic."*
- `android/docs/Segment7_Task_G_Throughput_Profiling.md`: *"Per this
  task's instructions, `adaptiveHarmonicFilter`, `ensembleAverageBeats`,
  and `notchDetectIEM` were **not** ported to Android, and no
  dicrotic-notch waveform display was added anywhere in this app."*

**Branch 2 (waveform morphology / dicrotic notch) has never shipped on
Android, by deliberate, already-documented scope decision.** This
promotion is therefore MATLAB-only, exactly as the brief anticipated — no
Android code was touched, and none needs to be.

---

## 4. Recommendation

**Promoted.** `opts.useConfidenceGate` defaults to `true` in
`pipeline/estimateVitalsAndMorphology.m`. This is now the best-evidenced
single change in this project's entire cPACE/mid-band/Gaussian-filter/gate
investigation line (Segments 11-14): it improved pass rate and (mostly)
correlation on two independently-checked pools of substantially different
composition (100-subject VIPL-dominated audit pool, 33-subject all-UBFC
held-out set), with a **zero-severe-regression guarantee that held on
every single one of 133 subjects checked across both pools** — not a
lucky property of the pool it was designed on.

**Caveats carried forward, not dropped**:
- The gate's benefit did not show up on the tiny 5-subject legacy
  benchmark (§1) — expected given its size, but real, and now on the
  record rather than glossed over.
- 9 of UBFC DATASET_2's 42 subjects could not be scored due to a newly-
  discovered duplicate-timestamp data issue in their own ground truth
  files (`docs/Segment14_Task1_UBFC_D2_Held_Out_Validation.md` §3) — not
  fixed here, flagged for any future UBFC-D2 work.
- The multi-candidate ("pick the highest self-reported confidence among
  several alphas") variant remains explicitly NOT recommended, per
  Segment 13's own finding — not touched by this promotion, still gated
  off in `harmonicFilterConfidenceGate.m`'s own multi-candidate mode.
- `filtering/bandpassClean.m`, `bandpassMorphology.m`'s `'wide'` vs.
  `'mid'` default, Branch 1's HR/SpO2 path, `cpaceProjection.m`,
  `computeCrossROIPLV.m`, and `residualAdaptiveKalmanHR.m` are all
  untouched by this promotion, per its own scope.

## Files touched/added this session

- `matlab/src/pipeline/estimateVitalsAndMorphology.m` (modified — new
  `opts.useConfidenceGate`, default `true`)
- `matlab/tests/segment7_task_f_regression_test.m` (modified — Part 3 now
  pins `useConfidenceGate=false`)
- `matlab/scripts/run_segment7_task_b_branch2_batch.m` (modified —
  additive `confidenceGate` condition)
- `results/metrics/segment7_task_b_notch_branch2.csv` (regenerated)
- `results/metrics/segment7_task_b_notch_branch2_preconfidencegate.csv`
  (new — pre-promotion snapshot)
- `matlab/docs/Segment14_Task1_UBFC_D2_Held_Out_Validation.md`
- `matlab/docs/Segment14_Task2_Confidence_Gate_Production_Promotion.md`
  (this file)
- `README.md` (folder-structure listing updated)
