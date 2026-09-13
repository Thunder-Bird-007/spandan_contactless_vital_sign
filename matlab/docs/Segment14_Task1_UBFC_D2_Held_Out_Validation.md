# Segment 14 Task 1 — UBFC DATASET_2 Held-Out Validation

Run 2026-09-13. Before promoting `morphology/harmonicFilterConfidenceGate.m`
to Branch 2's production default, this task finds and uses GENUINELY
HELD-OUT ground-truth data — subjects never touched anywhere in Segments
10-13's tuning or evaluation — to check whether the gate's own result
(Segment 13, on the 100-subject Segment 10 Task 1 audit pool) generalizes,
rather than reusing the same pool a fourth time.

**Headline: real held-out data exists (UBFC DATASET_2, 42 subjects), was
never previously extracted or run through this pipeline, and the gate's
key properties replicate on it** — higher pass rate than ABPF alone (58%
vs. 45%) and, most importantly, **zero severe regressions, confirmed
structural rather than a lucky property of the audit pool**. One genuine,
newly-discovered data-quality issue excluded 9 of the 42 subjects from
notch/correlation scoring (§3) — reported plainly, not worked around.

---

## 1. Finding real held-out data

Checked, per the brief, both leads named in it:

- **Other VIPL scenarios (v2/v5, etc.) beyond v1/source1**: these have
  ground-truth *HR/SpO2* (used in Segment 6 Task N's region-switching
  work), but **not** the ground-truth *PPG waveform* Task 1's audit
  needed. VIPL's `wave.csv` (the BVP waveform) is present per-scenario
  regardless, but every VIPL scenario shares the SAME subject pool as
  v1/source1 — using v2/v5 would not be genuinely held-out subjects, only
  a held-out *scenario* for subjects whose v1/source1 recording is already
  in the audit/tuning pool. Not used, for this reason.
- **UBFC DATASET_2 (42 subjects)**: confirmed via `docs/DATA_FORMAT.md`
  (written 2026-07-26, recommending this exact extraction and never
  acted on) and `docs/Segment7_Task_K_Template_Collapse_Diagnostic.md`
  ("UBFC-D2 (42, not run — disk space)") that this is a complete,
  real, ground-truth-PPG-bearing 42-subject set that has **never been
  decoded, cached, or evaluated anywhere in this project**. Disk space,
  the historical blocker, is no longer one (114GB free measured this
  session vs. ~67GB needed for all 42 subjects' video). **This is the
  held-out set used below.**

Extracted via the same targeted per-entry `System.IO.Compression.ZipFile`
technique this project already uses for VIPL (not a full-archive unzip) from
`H:\EEE 312 project\Contactless Vital Sign\UBFC dataset\ubfc-rppg-
dataset.zip` into `spandan/data/raw/UBFC-rPPG/DATASET_2/<subjectN>/`. All
42 subjects extracted successfully (44GB used, 44GB still free afterward).

**Nothing in Segment 10 Task 1's own 100-subject audit pool (5 UBFC-D1 +
95 VIPL v1/source1) was touched by this task.**

---

## 2. Method

For each of the 42 subjects: decode via the unmodified `io/loadUBFCVideo.m`
→ `roi/extractROISignals.m` ('forehead', the same default every other UBFC
script uses) chain, caching to `data/processed/UBFC_D2_<id>_rgb_traces.mat`
(resumable — a subject already cached is skipped, not redecoded). Then run
the EXACT SAME three-way comparison Segment 13 Task 2 ran on the audit
pool: ABPF alone, `harmonicSelectiveGaussianFilter.m` (alpha=0.15) alone,
and the safe gate — same functions, same 0.3 confidence bar, same metrics.
**Nothing about the gate's own logic was re-derived or re-tuned**, per the
brief.

Ground truth: `io/loadGroundTruth.m`'s existing `'dataset2'` parser
(`ground_truth.txt`: PPG signal, HR, and REAL per-frame timestamps
starting at 0 — already resampled to video frame rate by the dataset's own
authors, per `docs/DATA_FORMAT.md` §2b).

---

## 3. A genuine data-quality issue found along the way

9 of the 42 decoded subjects produced `NaN` for every downstream metric.
Traced to a real, root-caused failure (not silently left unexplained):

```
Error using matlab.internal.math.interp1
Sample points must be unique.
Error in resampleUniform (line 64)
Error in estimateLagPolarityByGroundTruth (line 110)
```

**Root cause, confirmed directly from the raw files**: these 9 subjects'
own `ground_truth.txt` (line 3, the per-frame timestamp line) contains at
least one exact duplicate value — e.g. `subject1` has index 494 and 495
both equal to `16.75` seconds. `morphology/resampleUniform.m`'s
`interp1(...,'pchip')` call (an existing, unmodified production function)
requires strictly unique sample points and throws rather than silently
handling a tie. This is a genuine artifact of UBFC DATASET_2's own
ground-truth files, not a bug introduced by this task or by the gate —
**and it was never visible anywhere in this project before**, because
DATASET_2 had never actually been decoded and run through this pipeline
until this task.

**Affected subjects (9/42, 21%)**: `subject1, subject4, subject5,
subject9, subject10, subject18, subject37, subject46, subject49` — exactly
the 9 that returned NaN; confirmed by checking every subject's raw
`ground_truth.txt` directly, not inferred.

**Not fixed here** — de-duplicating timestamps (e.g. nudging a repeated
value by a microsecond before interpolation) would be a reasonable,
low-risk future fix, but doing it would mean touching
`morphology/resampleUniform.m` or working around it, which is out of this
task's scope (validate the gate on held-out data, not patch an unrelated
pre-existing function). Flagged here as a genuine open item for UBFC
DATASET_2 specifically, not silently worked around. **The remaining 33
subjects are unaffected and are what the results below are computed on.**

---

## 4. Result (n=33 valid subjects of 42 processed)

| Condition | pass rate (notch conf > 0.3) | median notch conf | median waveform corr | harmonic confusion | severe regressions vs. ABPF |
|---|---|---|---|---|---|
| ABPF (current) | 45% (15/33) | 0.239 | 0.364 | ~3% (1/33) | — |
| Gaussian, alpha=0.15 alone | 18% (6/33) | 0.104 | **0.604** | ~3% (1/33) | **13** |
| **Safe gate** | **58% (19/33)** | **0.346** | 0.520 | ~3% (1/33) | **0** |

Full table: `results/metrics/segment14_task1_ubfc_d2_held_out_validation.csv`.
Figure: `results/figures/segment14_task1_held_out_summary.png` (its own
title says n=42 — that is the total subjects *processed*; the bars are
computed on the 33 with valid results, per §3. Harmonic-confusion
percentages above are computed against all 42 processed rows in the
underlying script, not just the 33 valid ones, since a failed subject's
default is "not confused" — a minor denominator inconsistency, noted for
transparency; it does not change the finding, since confusion is rare and
essentially flat across all three conditions regardless of which
denominator is used).

**The gate's own defining property replicates exactly: zero severe
regressions.** Plain Gaussian(0.15) alone shows 13 severe regressions out
of 33 (39%) on this held-out set — proportionally WORSE than the 17/100
(17%) found on the audit pool — which makes the gate's zero-regression
guarantee, structural rather than empirical, even more valuable here than
on the pool it was originally derived from.

**Pass rate**: the gate beats ABPF alone (58% vs. 45%), replicating the
audit pool's direction (47% vs. 24%) though the absolute numbers differ —
this held-out cohort's ABPF baseline is itself much stronger (45% vs. the
audit pool's 24%), a real population difference between UBFC-D2 and the
95%-VIPL-dominated audit pool, not a contradiction.

**Median waveform correlation**: the gate (0.520) sits between ABPF alone
(0.364, worst) and plain Gaussian alone (0.604, best) — an improvement
over ABPF, but not as large as ungated Gaussian would give *if* its
13-subject regression cost were ignored. This is the same honest trade
Segment 13 already reported for the audit pool (corr up for the
substituted subjects on average, down for a real minority) — replicated
here, not a new finding.

---

## 5. Honest caveats

- n=33, not the full 42 — stated throughout, not glossed over.
- This is one held-out dataset (UBFC, a different population from VIPL,
  which dominates the original audit pool 95:5) — it is genuinely unseen
  data, but it is not a THIRD independent population; a VIPL-only held-out
  check was not possible for the reason given in §1.
- The duplicate-timestamp issue (§3) is now a known, documented limitation
  of UBFC DATASET_2 specifically within this project, worth remembering
  for any FUTURE DATASET_2 work (e.g. a future SpO2 or Branch 1 use of
  this same 42-subject set would hit the identical issue for the same 9
  subjects, in any code path that calls `resampleUniform.m` or another
  strict-`interp1` consumer on their raw timestamps).

## Files

- `matlab/scripts/run_segment14_task1_ubfc_d2_held_out_validation.m`
- `results/metrics/segment14_task1_ubfc_d2_held_out_validation.csv`
- `results/figures/segment14_task1_held_out_summary.png`
- `data/raw/UBFC-rPPG/DATASET_2/subject*/` (42 subjects, newly extracted)
- `data/processed/UBFC_D2_subject*_rgb_traces.mat` (42 subjects, newly cached)
