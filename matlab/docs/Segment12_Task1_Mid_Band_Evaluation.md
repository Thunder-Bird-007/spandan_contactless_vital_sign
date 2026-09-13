# Segment 12 Task 1 — bandpassMorphology.m's 'mid' Mode Evaluation

Run 2026-09-13. Evaluates `morphology/bandpassMorphology.m`'s existing
but never-called `'mid'` mode (0.6–6.0Hz) as a candidate fix for the
Nyquist-margin problem `docs/Segment10_Task3_Tier0_Diagnostics.md`'s
Action 3 found for VIPL subjects running at a true ~16fps.

**Correction made along the way, flagged before anything else**: Task 3's
own doc stated "20 of 95 VIPL subjects (21%)" run at this true ~16fps. A
fresh count directly from the same CSV this task also uses finds **44 of
95 (46%)** — the original figure was a genuine counting error (most likely
conflated with Segment 6 Task L's *unrelated* 20-subject v5-scenario
figure), not a different definition. Corrected in
`docs/Segment10_Task3_Tier0_Diagnostics.md` and `SESSION_HANDOFF.md` with
strikethrough, per this project's own error-handling convention. This
doc uses the corrected 44-subject figure throughout.

**Headline result**: checked first, per the brief's own instruction — the
current `'wide'` mode does **NOT error** for these subjects today (every
real subject's true fps sits fractionally above the exact 16.0fps that
would trip `bandpassMorphology.m`'s own Nyquist guard), but runs with an
extremely thin design margin (as little as 0.033Hz). Switching to `'mid'`
gives a strictly non-regressive, small improvement (3 of 100 subjects flip
from failing to passing the 0.3 notch-confidence bar, zero flip the other
way) — **but the mechanism is NOT the one hypothesized**: the improvement
is not concentrated in the near-Nyquist-margin subset, and 43 of 44
"affected" subjects show literally zero change. See §3 for why, and §4 for
the resulting recommendation (keep production on `'wide'`, but the
`'mid'` alternative is now genuinely validated as a safe option, not just
an untested idea).

Script: `matlab/scripts/run_segment12_task1_mid_band_evaluation.m`.
`bandpassMorphology.m` was only ever CALLED with a different `bandMode`
argument it already supports — not modified. Do-not-touch files confirmed
unmodified via `git status` before writing this doc.

---

## Method

For all 100 of Segment 10 Task 1's subjects (5 UBFC-D1 + 95 VIPL
v1/source1), Branch 2's harmonic pipeline (`bandpassMorphology.m` →
`chromCombine.m` → `fftHeartRate.m` → shared f0 → `adaptiveHarmonicFilter.m`
→ `chromCombine.m` → `estimateLagPolarityByGroundTruth.m` →
`ensembleAverageBeats.m` → `notchDetectIEM.m` — Task 1's own exact
"harmonic" branch sequence) was run **twice per subject**, identical in
every respect except the `bandMode` passed to `bandpassMorphology.m` for
the shared-f0 estimation step: `'wide'` (today's default) and `'mid'`
(this task's candidate). Both were freshly recomputed rather than read
from Task 1's cache, specifically so the `'wide'` condition could be
**cross-checked against Task 1's own already-published numbers** before
trusting anything built the same way for `'mid'`.

**Regression check passed**: the freshly recomputed `'wide'` condition's
`notchConfidence` matches Task 1's own cached `notchConfidence_harmonic`
to `1e-6` for **100/100 subjects** — confirming this script's
reimplementation is faithful before any new number is trusted.

**Groups** (from Task 1's own `frameRate` column, no new data): "affected"
= `frameRate < 17Hz` (44 subjects, the true ~16fps cluster — there is a
large, clean gap in the data from 16.64fps to the next subject at
18.09fps, so any threshold in that range gives the identical count);
"safe" = `frameRate >= 17Hz` (56 subjects: 51 VIPL + 5 UBFC-D1).

---

## Section 0 — what does today's code actually do for the affected group?

Checked directly, not assumed. `bandpassMorphology.m`'s own internal guard
(`highCutoffHz >= nyquistHz`) triggers an error only when a subject's
Nyquist frequency is at or below 8.0Hz exactly. Every real VIPL subject in
this pool runs at 16.07–16.65fps (never exactly 16.0), giving a Nyquist of
8.03–8.32Hz — always fractionally *above* the guard.

| bandMode | high cutoff | Nyquist margin, affected group (n=44) |
|---|---|---|
| `'wide'` (current) | 8.0Hz | min 0.033Hz, max 0.322Hz, mean 0.090Hz |
| `'mid'` (candidate) | 6.0Hz | min ~2.03Hz, max ~2.32Hz |

**So today's actual behavior is not an error — it is a filter design with
almost no transition band left** (as little as 3.3% of a Hz between the
passband edge and the point where the filter design becomes invalid).
Figure: `results/figures/segment12_task1_nyquist_margin.png` shows this
directly — `'wide'`'s margin sits in a tight cluster near zero for this
group; `'mid'`'s sits comfortably around 2–2.3Hz.

---

## Result: 'mid' vs. 'wide', both groups

| Group | bandMode | n | pass rate (notch conf > 0.3) | median notch conf | median waveform corr |
|---|---|---|---|---|---|
| affected (<17fps) | wide | 44 | 25% (11/44) | 0.065 | 0.562 |
| affected (<17fps) | **mid** | 44 | **27% (12/44)** | 0.062 | 0.562 |
| safe (≥17fps) | wide | 56 | 23% (13/56) | 0.054 | 0.503 |
| safe (≥17fps) | **mid** | 56 | **27% (15/56)** | 0.063 | 0.503 |
| **all** | wide | 100 | 24% (24/100) | 0.058 | 0.519 |
| **all** | **mid** | 100 | **27% (27/100)** | 0.062 | 0.519 |

Full per-subject and summary table:
`results/metrics/segment12_task1_mid_band_comparison.csv`. Figure:
`results/figures/segment12_task1_notch_confidence_scatter.png` (paired
scatter, both groups — visibly almost every point sits exactly on the
diagonal).

---

## 3. Why the improvement doesn't track the Nyquist-margin hypothesis

Only **6 of 100 subjects** show *any* difference at all between `'wide'`
and `'mid'` — everyone else's `sharedF0Hz` estimate, and hence every
downstream number, is bit-for-bit identical. This makes sense once traced
through: `fftHeartRate.m`'s own peak search is fixed at 0.7–4Hz regardless
of the caller's bandpass upper cutoff, and both `'wide'` (0.5–8Hz) and
`'mid'` (0.6–6Hz) pass that entire search range comfortably — so the
*content the f0 estimator actually looks at* is nearly unaffected by which
of the two upper cutoffs was used, even at a razor-thin Nyquist margin.

Of the 6 subjects that DO change, exactly **3 flip from failing to passing
the 0.3 bar, and zero flip the other way** — a genuine, if small, strictly
non-regressive win. But:

| Subject | Group | frameRate | notch conf, wide→mid | waveform corr, wide→mid |
|---|---|---|---|---|
| `VIPL_p54` | **affected** | 16.14 | 0.110 → **1.000** | 0.074 → 0.091 |
| `VIPL_p14` | safe | 24.93 | 0.036 → 0.401 | 0.184 → **0.033** |
| `VIPL_p89` | safe | 19.24 | 0.027 → **1.000** | 0.079 → 0.408 |

**Only 1 of the 3 improved subjects is actually in the "affected" (near-
Nyquist) group** — 2 of 3 are comfortably in the "safe" group, where
`'wide'` has an ample margin already. So the improvement Task 3's own
hypothesis predicted (near-Nyquist subjects specifically) is **not what is
actually happening** — this looks instead like a small, scattered,
harmonic-lock-escape effect from the two filters' slightly different
transition-band shapes, unrelated to which subject happens to sit near a
Nyquist wall. `VIPL_p14` is also a genuine, reportable tension: its notch
confidence improves markedly (0.036→0.401) while its waveform correlation
*regresses* (0.184→0.033) — the two metrics disagree for this one subject,
stated plainly rather than only reporting whichever number looks better.

**A real, if anticlimactic, finding follows from this**: the razor-thin
Nyquist margin Task 3 Action 3 correctly identified as a real filter-design
fact does **not** translate into a practical degradation of Branch 2's
shared-f0 estimation step in this architecture, because that step's own
downstream consumer (`fftHeartRate.m`'s 0.7–4Hz search) never reaches
anywhere near the marginal high-cutoff region where a poorly-conditioned
filter design would actually show artifacts. This is a genuine, useful
clarification of Task 3's own finding, not a retraction of it — the
Nyquist inadmissibility Task 3 Action 3 demonstrated with a *synthetic*
signal at exactly 16.000fps is still real and still relevant to any FUTURE
use of `bandpassMorphology.m`'s output more directly (e.g. as the
notch-bearing signal itself, not just an f0 estimate feeding a comb filter
elsewhere) — it just doesn't bite in the one specific role this pipeline
currently uses `'wide'` for.

---

## 4. Recommendation

**Do not change the production default.** `pipeline/
estimateVitalsAndMorphology.m`'s own `bandpassMorphology(...,'wide')` call
for shared-f0 estimation stays as-is — the evidence for switching is real
but weak (3 improving subjects out of 100, one of which shows a
metric disagreement), and does not specifically address the near-Nyquist
subset the original hypothesis was about.

**`'mid'` is now a genuinely validated, safe, low-risk alternative** —
not just an untested idea, per this task's own head-to-head — worth
offering as an available option (it already IS one, via
`bandpassMorphology.m`'s own existing `bandMode` argument; no new file was
needed for this task) if a future session wants to pursue harmonic-lock
avoidance further, but not compelling enough on its own to promote to
default given the small, non-targeted effect size found here.

**What this redirects attention to**: the real, still-open question from
Task 3 Finding D is not "does the shared-f0 step suffer at ~16fps" (this
task shows: not meaningfully) but "would `bandpassMorphology.m`'s wide
band cause a *bigger* problem if a future architecture change made
Branch 2 use its output more directly for the notch-bearing signal itself,
rather than only an intermediate f0 estimate" — genuinely untested here,
flagged as a real caveat for any future redesign, not answered by this
task.

## Files

- `matlab/scripts/run_segment12_task1_mid_band_evaluation.m`
- `results/metrics/segment12_task1_mid_band_comparison.csv`
- `results/figures/segment12_task1_notch_confidence_scatter.png`
- `results/figures/segment12_task1_nyquist_margin.png`
- `results/figures/segment12_task1_pass_rate.png`
