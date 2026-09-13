# Segment 10 Task 3 — Tier 0 Diagnostics

Run 2026-09-13. Four cheap, additive, read-only tests from
`docs/Segment10_Task2_Solution_Literature_Search.md` section 8 ("Tier 0 —
costs almost nothing, decides what else is worth doing"), run to decide
whether the Tier 1 candidate fixes in that document are worth starting.
**TIER 0 ONLY — no Tier 1 work was started.** All four use data already on
disk (Task 1's own per-subject CSV, Task N's cached multi-region traces, and
one brand-new synthetic waveform); none reprocess a video. None of the six
do-not-touch files (`pulseextraction/chromCombine.m`, `pulseextraction/
posCombine.m`, `heartrate/fftHeartRate.m`, `morphology/
adaptiveHarmonicFilter.m`, `filtering/waveletDenoise.m`, `filtering/
bandpassClean.m`, `roi/extractROISignals.m`) were modified — every one is
only ever called, exactly the discipline `run_segment10_waveform_fidelity_
audit.m` already established. Confirmed via `git status`-equivalent (no diff
on any of those files) before writing this doc.

Script: `matlab/scripts/run_segment10_task3_tier0_diagnostics.m` (one file,
four sections, run start-to-finish in under two minutes — cheap by design).
Outputs: `results/metrics/segment10_task3_tier0_action{1,2,3,4}_*.csv`,
`results/figures/segment10_task3_action{1,2,3,4}_*.png`.

**Headline: 3 of 4 supported, 1 not supported — and the one that failed is
the one Task 2's Revision 1 had flagged as potentially "the finding that
reframes everything."** The sampling-floor/ceiling argument
(arXiv:2606.03802) does not hold up against Spandan's own data. The
isochromatic-contamination mechanism (Kaur, Lakshminarayanan & Saini, Biomed.
Opt. Express 17(7):3832, 2026) gets independent corroboration instead, from
a completely different angle (literally — Action 4 measures an angle). See
§5 for the full verdict.

---

## Action 1 — Ceiling test: does notch confidence scale with true fps?

### Method

arXiv:2606.03802 claims the dicrotic notch spans only 1–3 samples at 30fps —
at or below the measurement's own resolution floor — which predicts notch
confidence should scale with a subject's true effective frame rate. Both
halves of this test are Task 1 outputs already on disk:
`results/metrics/segment10_waveform_fidelity_per_subject.csv`'s
`frameRate` column (per-subject true fps) and its `notchConfidence_<branch>`
/ `notchConfidenceGT_<branch>` columns (rPPG-signal and GT-signal notch
confidence, respectively, for chrom/pos/harmonic).

**Before trusting `frameRate` as "true" fps, this session independently
re-verified it**, rather than assuming `docs/VIPL_DATA_FORMAT.md` §4's
documented `time.txt` correction was actually applied to every cached
subject: `VIPL_p20_v1_source1`'s cached `frameRate` is 16.1374 fps; its raw
`data/raw/VIPL-HR/p20/v1/source1/time.txt` has 497 timestamps spanning
0–30736 ms, giving `(497-1)/(30736/1000) = 16.137` fps — an exact match.
Task 1's own `frameRate` column already **is** the `time.txt`-corrected true
fps for VIPL source1 (not the re-encoded 25fps container label), so no fresh
per-subject `time.txt` parsing was needed for this test.
`results/metrics/segment8_source2_fps_investigation.csv` (the file named in
this task's brief) turned out to document a **different** discrepancy —
source2 (phone) container-vs-sibling-duration mismatches — that does not
apply to Task 1's pool (v1/source1, webcam); it is not used here. The
Segment6 Task L v5-scenario "~16fps" finding this task's brief also
referenced is likewise a different scenario (v5, not v1) — but the same
~16fps phenomenon turns out to be present directly inside Task 1's own
v1/source1 pool too (20 of 95 VIPL subjects), which is what makes this test
possible without touching v5 at all.

Pearson and Spearman correlation of `frameRate` vs. `notchConfidence_<branch>`
(the rPPG-signal notch confidence the sampling argument is actually about)
and, as an explicit falsification check, vs. `notchConfidenceGT_<branch>`
(ground-truth PPG's own notch confidence — from a ~60Hz contact sensor whose
sampling rate the camera's fps cannot possibly affect; if this correlates
with camera fps just as strongly, the mechanism isn't camera sampling at
all). Computed pooled ("all"), and separately within UBFC-D1 and within
VIPL, per this task's explicit instruction to check for a spurious
two-cluster effect.

### Results

| Group | n | fps range | Target | chrom r (Pearson/Spearman) | pos r | harmonic r |
|---|---|---|---|---|---|---|
| all | 100 | 16.07–29.80 | notchConfidence | 0.129 / -0.048 | 0.256 / 0.132 | -0.030 / -0.008 |
| all | 100 | 16.07–29.80 | notchConfidenceGT | 0.017 / -0.055 | 0.109 / 0.020 | -0.104 / -0.054 |
| ubfc_d1 | 5 | 28.64–28.67 | notchConfidence | 0.551 / 0.707 | 0.466 / 0.707 | 0.541 / 0.707 |
| ubfc_d1 | 5 | 28.64–28.67 | notchConfidenceGT | 0.474 / 0.707 | 0.474 / 0.707 | 0.750 / 0.707 |
| **vipl** | **95** | **16.07–29.80** | notchConfidence | **-0.128 / -0.191** | **0.036 / 0.029** | **-0.108 / -0.060** |
| vipl | 95 | 16.07–29.80 | notchConfidenceGT | 0.091 / 0.021 | 0.192 / 0.104 | -0.041 / 0.017 |

Full table: `results/metrics/segment10_task3_tier0_action1_ceiling.csv`.
Figure: `results/figures/segment10_task3_action1_ceiling_scatter.png` (2×3
grid, top row = signal notch confidence, bottom row = GT control, both vs.
true fps, colour-coded by dataset).

**The spurious two-cluster check the brief asked for, made concrete:**

| Group | mean fps | mean notchConfidence_chrom | median |
|---|---|---|---|
| ubfc_d1 (n=5) | 28.66 | 0.635 | 0.515 |
| vipl (n=95) | 19.86 | 0.119 | 0.041 |

UBFC sits at both high fps *and* high notch confidence; VIPL sits at both
lower fps *and* much lower notch confidence — exactly the two-cluster shape
that manufactures a positive-looking pooled correlation out of two group
means, not a real within-dataset relationship. The pooled "all" numbers
above (r=0.13–0.26 for notchConfidence) are consistent with being entirely
this artifact.

**UBFC-D1's own within-group numbers are not a real test of anything.**
Its fps range is 28.64–28.67 — a 0.03fps spread across 5 subjects. Any
correlation computed against a functionally constant x-variable is noise,
not evidence; the fact that all three branches happen to show the same
Spearman value (0.707, the value for a specific rank permutation at n=5) is
itself a giveaway that this is a small-sample coincidence, not a signal.
**Reported as INCONCLUSIVE by construction, not by result.**

**VIPL, which has a genuine 16–30fps spread and n=95, is the real test —
and it fails the ceiling hypothesis.** Correlation with `notchConfidence` is
flat-to-negative for chrom (-0.128) and harmonic (-0.108), and negligible for
pos (0.036). If the sampling-floor mechanism were the dominant driver of
Task 1's notch-confidence numbers, this is exactly the subset where it
should show up clearest, and it does not. The GT control shows the same
null/mixed pattern (0.09, 0.19, -0.04) — reinforcing that whatever weak
signal exists is not specific to the camera-sampling mechanism, since GT's
sampling rate does not depend on camera fps at all.

### Verdict: **NOT SUPPORTED.**

The dicrotic-notch sampling-floor argument from arXiv:2606.03802 does not
explain Task 1's notch-confidence numbers. Where a real, wide within-dataset
fps range exists (VIPL, n=95), there is no positive relationship between
true fps and notch confidence — if anything a weak negative one for two of
three branches. The pooled-across-dataset appearance of a relationship is
attributable to UBFC vs. VIPL being different in ways well beyond frame
rate (dataset identity, not sampling resolution, is doing the pooled work).
This does not retract Task K's earlier "no support for template collapse"
finding (a different claim from the same paper) — it is a second, separate
claim from the same paper, now also unsupported.

---

## Action 2 — Cross-ROI phase-locking value (ground-truth-free fidelity metric)

### Method

Kaur, Lakshminarayanan & Saini (Biomed. Opt. Express 17(7):3832, 2026)
evaluate fidelity via cross-ROI PLV: ROIs sharing an arterial supply receive
the cardiac pulse at a fixed phase relationship set by pulse transit time,
so agreement between independently-extracted ROI signals is a fidelity
proxy that needs no ground truth at all. This matters directly for Spandan
because every Task 1 number is gated behind a lag/polarity alignment step
that is flagged unreliable on 34–46% of subjects.

Used Task N's already-cached four-region (`forehead`, `glabella`, `malar`,
`cheek`) v1/source1 traces for the 20 subjects Task N validated (`p1, p3,
p4, p6–p22`; confirmed all 20 are also in Task 1's own 95-subject VIPL pool,
so a same-subject comparison is possible without reprocessing anything).
Spot-checked that the `forehead` region cache is byte-identical to Task 1's
own whole-frame cache for `p1` (`isequal` on R and fs both true) — confirming
Task N's "forehead is the original, unchanged default geometry" claim
directly rather than assuming it.

Per subject, per region: `detrendSignal` → `bandpassClean` (0.7–4Hz, Branch
1's own narrow band) → `chromCombine`/`posCombine` → `bandpassClean` again
(matching Task 1's own Branch 1 sequence exactly) → instantaneous phase via
`hilbert`. PLV between every one of the 6 region pairs
(forehead–glabella, forehead–malar, forehead–cheek, glabella–malar,
glabella–cheek, malar–cheek) as `|mean(exp(i·(φ_A − φ_B)))|` over the full
recording, averaged to one PLV per subject per branch (CHROM, POS — per the
brief's own scope, harmonic-comb not included here). Correlated
(Pearson + Spearman) against Task 1's own `corr_chrom` / `corr_pos`
(GT-referenced Pearson correlation) for the same 20 subjects.

### Results

| Branch | r (Pearson) | r (Spearman) | n |
|---|---|---|---|
| CHROM | **0.571** | 0.577 | 20 |
| POS | **0.632** | 0.594 | 20 |

Full per-subject and per-pair table:
`results/metrics/segment10_task3_tier0_action2_plv.csv`. Figure:
`results/figures/segment10_task3_action2_plv_scatter.png`.

Per-subject PLV ranged 0.126–0.427 (CHROM) and 0.162–0.508 (POS) — well
below the near-1.0 that a perfectly phase-locked, noise-free signal would
give, consistent with this project's other findings that fidelity is modest
across the board, not with a PLV-computation bug.

### Honest caveats

- n=20, not the full 95-subject VIPL pool — bounded by how many subjects
  Task N happened to cache all four regions for. At n=20 (df=18), r≥0.444
  is nominally significant at p<0.05 and r≥0.561 at p<0.01 two-tailed, so
  both correlations clear the conventional p<0.05 bar and POS clears p<0.01
  — but this project has been burned by small-pool inflation before
  (`docs/Segment10_Task2_Solution_Literature_Search.md` §5's own citation of
  HR r=0.824 at N=18 → 0.314 at N=112) and this is exactly that N regime.
  Treat this as *promising*, not *established*.
- This uses Branch 1's ROI geometry and filter band only (0.7–4Hz), not
  Branch 2's wide band or the harmonic-comb signal — a deliberate scope
  match to the brief ("for CHROM and POS"), not a claim that PLV would
  behave the same way for Branch 2.
- Kaur et al.'s own PLV evaluation used MediaPipe FaceMesh ROIs; this reuses
  Spandan's axis-aligned-box ROIs instead (Task H/J already found FaceMesh
  ROIs hurt on this project's notch metric) — the correlation direction is
  what's being tested here, not an attempt to reproduce their absolute PLV
  numbers.

### Verdict: **SUPPORTED.**

Cross-ROI PLV correlates with Task 1's own GT-referenced fidelity at a
moderate-to-strong level for both CHROM (r=0.571) and POS (r=0.632) on the
20 subjects available, with no ground truth involved in computing it. This
is exactly the outcome that would make PLV worth adopting as a standing,
scalable evaluation axis — it sidesteps the 34–46% alignment-failure problem
entirely and can, in principle, be computed on every subject with cached
multi-region traces, not just the 100 with a GT PPG waveform.

---

## Action 3 — Synthetic-notch filter distortion isolation test

### Method

Built a closed-form, two-Gaussian single-cycle PPG model (documented
choice, not fit to any real data) with an exactly known notch location,
notch depth, and systolic-peak location:

```
p(τ) = A1·exp(-0.5·((τ mod T − μ1)/σ1)²) + A2·exp(-0.5·((τ mod T − μ2)/σ2)²)
f0 = 1.2 Hz (72 bpm), T = 1/f0
μ1 = 0.20s, σ1 = 0.06,  A1 = 1.00   (systolic peak)
μ2 = 0.42s, σ2 = 0.095, A2 = 0.72   (diastolic/dicrotic peak)
```

Parameters were chosen (not tuned from real data) so that: both Gaussians
decay to negligible amplitude at the cycle boundary (no periodic-tiling
discontinuity); the systolic-peak-to-notch gap (114.6ms by construction)
comfortably clears `notchDetectIEM.m`'s own hard-coded 0.1s minimum-gap
requirement, so the notch is genuinely detectable by the *same* detector
Task 1 used, not a borderline case tuned to pass; and the resulting notch
depth (0.476 on `notchDetectIEM.m`'s own normalized scale) and diastolic/
systolic amplitude ratio are within physiologically plausible PPG range.

Tiled to 36 cycles, sampled at 30/25/16 fps (evaluating the closed form
directly at each sample time — no decimation-induced aliasing beyond what
the fps itself introduces), pushed through:

- (a) `filtering/bandpassClean.m` (Butterworth order 2, 0.7–4Hz — called,
  not modified)
- (b) `morphology/bandpassMorphology.m` (Butterworth order 3, 0.5–8Hz,
  `'wide'` — called, not modified)
- (c) three **new, script-local-only** order-2 variants at 0.7–8/10/12Hz
  ceilings (`bandpassOrder2Custom`, same `butter`+`filtfilt` construction as
  (a) and (b), parameterized only for this test — not a modification of any
  existing file)

The analysis cycle (the 18th of 36, far from `filtfilt`'s edge transients at
either end of the finite signal) was extracted, pchip-resampled to a
256-sample prototype (Task 1's own convention: `fs = beatSamples·f0`), and
run through `notchDetectIEM.m` — the **same detector Task 1 used**, so
results are in the same units Task 1 already reported (`notchPosNorm`,
`notchDepth`). Ground truth used the identical detector on the pristine
analytic cycle, for apples-to-apples comparability. A pre-flight assertion
confirms the ground-truth waveform itself has a detectable notch before any
distortion number is trusted.

### Results

| Config | fps | Nyquist | Valid | Notch pos. error (ms) | Notch depth ratio | Peak timing shift (ms) |
|---|---|---|---|---|---|---|
| BwClean (0.7–4Hz, ord2) | 30 | 15.0 | yes | 6.54 | **0.579** | -6.54 |
| BwClean (0.7–4Hz, ord2) | 25 | 12.5 | yes | 0.00 | **0.554** | -6.54 |
| BwClean (0.7–4Hz, ord2) | 16 | 8.0 | yes | -3.27 | **0.493** | -16.34 |
| Morph-wide (0.5–8Hz, ord3) | 30 | 15.0 | yes | 3.27 | **0.971** | -6.54 |
| Morph-wide (0.5–8Hz, ord3) | 25 | 12.5 | yes | 6.54 | **1.003** | -6.54 |
| Morph-wide (0.5–8Hz, ord3) | 16 | 8.0 | **NO** | — | — | — |
| ord2 (0.7–8Hz) | 30 | 15.0 | yes | 6.54 | 1.023 | -6.54 |
| ord2 (0.7–8Hz) | 25 | 12.5 | yes | 6.54 | 1.059 | -6.54 |
| ord2 (0.7–8Hz) | 16 | 8.0 | **NO** | — | — | — |
| ord2 (0.7–10Hz) | 30 | 15.0 | yes | -3.27 | 1.032 | -6.54 |
| ord2 (0.7–10Hz) | 25 | 12.5 | yes | 6.54 | 1.077 | -6.54 |
| ord2 (0.7–10Hz) | 16 | 8.0 | **NO** | — | — | — |
| ord2 (0.7–12Hz) | 30 | 15.0 | yes | -3.27 | 1.043 | -6.54 |
| ord2 (0.7–12Hz) | 25 | 12.5 | yes | 6.54 | 1.092 | -6.54 |
| ord2 (0.7–12Hz) | 16 | 8.0 | **NO** | — | — | — |

Full table: `results/metrics/segment10_task3_tier0_action3_synthetic_notch.csv`.
Figure: `results/figures/segment10_task3_action3_synthetic_notch.png`.

**Finding A — the narrow HR-band destroys roughly half the notch's depth,
at every fps.** `bandpassClean.m`'s 0.7–4Hz band leaves only 49–58% of the
true notch depth intact. This is a real, filter-induced, quantified
component of Task 1 finding (4) — not a claim that filtering is the *whole*
story (§0's isochromatic mechanism is a separate, non-filter explanation
that can coexist), but a real, sizeable one.

**Finding B — the already-adopted wide-band Branch 2 filter essentially
fully preserves notch depth, when it can run at all.** `bandpassMorphology`
`'wide'` (0.5–8Hz) gives depth ratios of 0.971–1.003 at 30/25fps —
indistinguishable from perfect preservation. This is a genuine, positive
validation of this project's existing Branch 2 design choice, produced by a
test that could just as easily have gone the other way.

**Finding C — order (2 vs. 3) is not the dominant driver here; upper cutoff
is,** confirming Lapitan et al.'s own conclusion. The order-2 variants at
8/10/12Hz ceilings show depth ratios of 1.02–1.09 (slightly *above* 1,
consistent with mild passband ripple/overshoot near cutoff for a lower-order
design, not a deficiency) — comparable to or better than the order-3
wide-band result at similar ceilings. Lapitan et al.'s order-2
recommendation is not contradicted, but this specific metric (notch depth)
doesn't show order 3 paying a large tax either — the 0.7–4Hz vs. 0.5–8Hz
upper-cutoff gap dominates by a wide margin (roughly 45 percentage points)
over anything order-related (a few percentage points).

**Finding D — the exact Nyquist-unusable case the brief predicted, now
demonstrated directly.** At 16fps, Nyquist = 8.0Hz, which sits exactly at
`bandpassMorphology.m`'s own 8Hz `'wide'` ceiling — its own internal check
(`highCutoffHz >= nyquistHz`) correctly refuses to run, caught cleanly by
this script rather than crashing past it. All three order-2 8/10/12Hz
variants are equally unusable at 16fps for the same reason. **Every filter
config in this test wider than the narrow 0.7–4Hz HR-band is structurally
unavailable for any subject running at a true ~16fps** — and Action 1's own
data confirms ~~20 of Task 1's 95 VIPL subjects (21%) are in exactly that
regime~~ **[CORRECTED 2026-09-13, Segment 12 Task 1] a recount from the same
CSV finds 44 of 95 (46%)** are in exactly that regime (frameRate < 17Hz;
the true ~16fps band runs 16.07–16.65fps with a large, clean gap to the
next subject at 18.09fps, so any threshold in that gap gives the same
count). The original "20 (21%)" figure was a genuine counting error, not a
different definition — most likely a conflation with Segment 6 Task L's
*unrelated* v5-scenario 20-subject figure (a different scenario, v5 dark,
not this v1/source1 pool). Flagged and corrected here per this project's
own error-handling convention rather than silently fixed; the qualitative
verdict below is unaffected (if anything, a larger affected fraction makes
the finding MORE consequential, not less). This is not a tuning problem to
sweep away; it is a hard ceiling imposed by the recording, independent of
anything this project's own code does.

### Honest caveats

- Notch **position** and **peak timing** numbers cluster suspiciously
  tightly around multiples of 3.27ms (e.g. -6.54ms appears for almost every
  valid config). That is exactly this measurement's own resampling-grid
  resolution floor (`T·1000/(beatSamples−1) = 833.33/255 = 3.27ms`), not
  necessarily a real, distinguishable per-config timing effect — stated
  plainly rather than over-interpreted. **Depth ratio is the metric that
  clears this floor by a wide margin (tens of percentage points) and is the
  one worth trusting quantitatively here.**
- This is a single synthetic waveform at a single HR (72bpm) and a single
  notch depth/position — it isolates *filter*-induced distortion cleanly,
  which was the brief's specific ask, but says nothing about how this
  interacts with real noise, motion, or the isochromatic contamination
  Action 4 below independently measures.
- `bandpassMorphology.m`'s `'mid'` mode (0.6–6.0Hz) was not tested here (not
  in the brief's list of three configs) — it sits between the two extremes
  and might be a usable middle ground for the 16fps-Nyquist problem Finding
  D identifies, since its own ceiling is below 8Hz. Flagged as a natural
  next question, not answered here.

### Verdict: **SUPPORTED** (with the Nyquist caveat as an equally important finding).

Filtering genuinely explains a real, sizeable chunk of Task 1 finding (4)
(the narrow band halves notch depth), the already-adopted wide-band fix
already essentially solves it when it can run, and upper cutoff — not
order — is confirmed as the dominant lever, matching both literature
anchors. But the 16fps Nyquist wall is real and already affects a
non-trivial fraction (~~21%~~ **46%, corrected 2026-09-13 — see Finding D**)
of the exact pool Task 1 audited — any Tier 1 work on Branch 2's filter for
VIPL should treat "what does the ~16fps subset even run" as a first-class
question, not an edge case.

---

## Action 4 — POS cardiac-angle / sigma-ratio check

### Method

POS's σ-ratio combination (`posCombine.m`: `pulseSignal = S1 +
(std(S1)/std(S2))·S2`) implicitly assumes the cardiac signal lies at a
fixed ~57° from its first basis vector e1 (the `S1 = Gn − Bn` direction).
Kaur et al. measured actual medians of 96.6–115.5° across four cohorts —
above 90°, the combination becomes destructive (cancels cardiac signal at
the combination step, unrecoverable downstream).

**Pure measurement — `posCombine.m` was not modified, and this section's
result does not change it regardless of outcome, per the brief.** Reused
exactly `posCombine.m`'s own lines 39–40 (`S1 = Gn - Bn; S2 = Gn + Bn -
2*Rn;`), reproduced standalone here (not by calling `posCombine.m`, since
this needs `S1`/`S2` *before* they're combined) on the cardiac-band signal
(`detrendSignal` → `bandpassClean` 0.7–4Hz, same normalization convention
`posCombine.m` itself uses). For each subject, PCA (dominant eigenvector of
`cov(S1, S2)`) finds the actual empirical direction of cardiac-band
variation in the (S1, S2) plane; its angle relative to the S1 axis (e1),
mapped to [0°, 180°), is the measured cardiac angle.

**Subject pool: the same 5 UBFC-D1 + 20 VIPL v1/source1 subjects Action 2
already loads** (25 total) — reusing Task N's already-validated 20-subject
cache rather than opening a third data-loading path, and giving UBFC/VIPL
diversity within the brief's suggested 20–30-subject range.

### Results

| Group | n | median | IQR | % above 90° |
|---|---|---|---|---|
| all | 25 | **109.5°** | 100.3°–129.9° | 92% |
| ubfc_d1 | 5 | 97.8° | 84.7°–98.8° | 60% |
| vipl | 20 | **121.4°** | 106.8°–131.5° | **100%** |

Full table: `results/metrics/segment10_task3_tier0_action4_cardiac_angle.csv`.
Figure: `results/figures/segment10_task3_action4_cardiac_angle_hist.png`.

Individual values ranged 83.6°–138.8°. Not one of the 25 subjects measured
anywhere near POS's assumed 57°; the closest (83.6°, UBFC `6-gt`) is still
27° off.

### Honest caveats

- This project's own angle-measurement convention (PCA on the un-combined
  `S1`/`S2` cardiac-band signal) is not verified to be *identical* to Kaur
  et al.'s own measurement method — the paper's exact estimator wasn't
  independently reconstructed line-by-line here. The fact that Spandan's
  pooled median (109.5°) and VIPL-only median (121.4°) both land inside
  their reported 96.6–115.5° cross-cohort range is a strong consistency
  signal, but "consistency with a range" is weaker than "same estimator,
  verified."
- UBFC-D1 (n=5) is small; its 60%-above-90° split (3 of 5) is a genuine
  measurement but not a stable percentage at this N. VIPL's 100% (20 of 20)
  is a cleaner, larger-N result.
- This measures the angle on the ROI's *whole-frame* cardiac-band signal
  (same default forehead-box ROI Task 1 used), not per-region — a
  deliberate scope match to "Spandan's own cached traces," not an attempt
  to test whether the angle itself varies by ROI region (a natural
  follow-up, not attempted here).

### Verdict: **SUPPORTED.**

Every one of the 25 subjects sits well above POS's built-in 57° design
assumption, 92% sit above the 90° destructive-combination threshold, and
the measured medians land inside Kaur et al.'s own reported cross-cohort
range almost exactly. This is independent, direct evidence — on Spandan's
own data, not just cited from another paper's cohorts — that POS's
combination step is partially cancelling its own cardiac signal for most of
this project's subjects, and that the isochromatic-contamination mechanism
behind it (§0 in the Task 2 doc) is a live phenomenon here, not a concern
that only applies to other datasets.

---

## 5. Overall verdict: is Tier 1 worth starting?

**Yes — but the Tier 1 priority order from the Task 2 literature search
needs revising in light of these four results, not simply confirmed.**

- Action 1 **rules out** the sampling-floor/ceiling argument
  (arXiv:2606.03802) as the explanation for Task 1's modest notch-confidence
  numbers, at least via this specific mechanism and metric. Task 2's
  Revision 1 had this as its headline candidate explanation; that framing
  does not survive contact with Spandan's own within-dataset data. This is
  a real, negative result, not a null test — it should stop this project
  from treating "wait for higher frame rate" as sufficient on its own.
- Actions 2 and 4 both **independently corroborate** the competing
  explanation from Task 2 §0 (Kaur et al.'s isochromatic-contamination
  mechanism): Action 4 directly measures Spandan's own cardiac angle at
  97–134°, squarely in the paper's own reported "well past 57°, mostly past
  90°" regime, on Spandan's own hardware/ROI/pipeline, not an assumption
  imported from another cohort. Action 2 shows cross-ROI PLV (the metric
  the same paper's mechanism motivates) genuinely tracks Task 1's
  GT-referenced fidelity.
- Action 3 **confirms and quantifies** (rather than newly reveals) that
  filtering explains a real, sizeable, but *partial* share of Task 1
  finding (4), that the already-adopted wide-band Branch 2 filter already
  addresses most of it when it can run, and surfaces a concrete, previously
  uncharacterized-in-this-exact-pool constraint: ~~~21%~~ **46% (corrected
  2026-09-13, see Finding D)** of Task 1's own VIPL subjects run at a true
  fps where Branch 2's own filter is literally inadmissible (Nyquist).

**Concrete recommendation for the next session, in cheapest-first order:**

1. **cPACE Stage 1** (`P = I − q̂q̂ᵀ`, Task 2 §0) is now the best-supported
   candidate in the whole document — it was already the highest-expected-
   value item on paper, and Action 4 has now added direct, on-Spandan's-own-
   data evidence for the mechanism it targets, not just a citation.
2. **Adopt cross-ROI PLV** (Action 2's own method) as a standing,
   ground-truth-free evaluation metric alongside Task 1's GT-referenced
   correlation — it is cheap, already implemented in this task's script,
   and scales to every subject with cached multi-region traces, not just
   the 100 with a GT waveform.
3. **Investigate the 16fps/Nyquist gap for Branch 2 specifically** (a
   narrower, more concrete descendant of Task 2's original "cutoff/order
   sweep" item #8): `bandpassMorphology.m`'s existing but unused `'mid'`
   mode (0.6–6.0Hz) is a candidate for the ~16fps subset specifically, since
   its own ceiling sits below that subset's 8Hz Nyquist — not attempted in
   this Tier 0 pass, flagged as the natural next question from Action 3's
   Finding D.
4. The Harmonic-Selective Gaussian Filtering item (Task 2 §2, Sensors
   26(12):3710) remains a reasonable Tier 1 candidate on its own terms, but
   should now be tested *after or alongside* cPACE Stage 1 rather than
   first, per Task 2's own stated caveat that no filter fixes isochromatic
   contamination.

**Nothing in this document is adopted or wired into production.** Every
number above is a diagnostic result on data already on disk; the do-not-
touch list is untouched; this file is a decision input for Tier 1, not a
Tier 1 result itself.
