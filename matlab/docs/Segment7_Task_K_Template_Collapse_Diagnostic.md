# Segment 7 Task K — Template-Collapse Diagnostic

Prompted by arXiv:2606.03802 ("Template Collapse and Information-Theoretic Limits in
Camera rPPG Pulse Morphology Restoration", 2026), which warns that a per-subject
waveform-correlation metric can look good purely because a method collapses to the SAME
population-average shape for every subject, not because it recovers real subject-specific
morphology. This task checks whether that risk applies to `morphology/adaptiveHarmonicFilter.m`'s
notch-confidence win (Segment 7 Task B: 4/5 UBFC subjects above the 0.3 bar, vs. 1/5 for
flat-band).

## Which subjects actually have ground-truth PPG *waveform* data (checked, not assumed)

The handoff's default guess — "likely only the 5 UBFC ground-truth subjects" — undercounts.
Checked directly against `docs/DATA_FORMAT.md` and `docs/VIPL_DATA_FORMAT.md` (not
re-derived from memory):

| Dataset | Subjects w/ real GT waveform | Field | Rate |
|---|---|---|---|
| UBFC DATASET_1 | 5 | `gtdump.xmp` col 4 | ~62 Hz, real per-sample timestamps |
| UBFC DATASET_2 | 42 (not extracted — ~70GB uncompressed, didn't fit in available disk space at analysis time) | `ground_truth.txt` line 1 | ~29-30 Hz, real per-frame timestamps |
| VIPL-HR | 95 (v1/source1, on disk) of 107 | `wave.csv` | ~60 Hz nominal (CONTEC CMS60C), **no per-sample timestamp array** |

**This run covers UBFC DATASET_1 (5) + VIPL-HR v1/source1 (95) = 100 subjects.**
DATASET_2 was scoped out for a disk-space reason (see Changelog/SESSION_HANDOFF.md), not a
methodological one — a real limitation of this run, not a hidden one. v1 (the "stable"
scenario) was used exclusively for VIPL to avoid confounding the correlation comparison
with scenario-driven shape differences (motion/talking/dark/exercise) unrelated to
template collapse.

## Method

For each of the 100 subjects: `roi/extractROISignals.m` (baseline ROI) →
`filtering/detrendSignal.m` → `morphology/bandpassMorphology.m` (wide) →
`pulseextraction/chromCombine.m` → `heartrate/fftHeartRate.m` (shared f0) →
`morphology/adaptiveHarmonicFilter.m` (order 6, that f0) → `chromCombine.m` again →
`morphology/fixPolarityByGroundTruth.m` → `morphology/resampleUniform.m` →
`morphology/ensembleAverageBeats.m` → the subject's **rPPG prototype**
(`prototype.trimmedMean`, 1x256, cycle-normalized). The SAME subject's ground-truth
contact-PPG waveform was run through the same `resampleUniform`/`ensembleAverageBeats`
machinery (no ROI/filtering — it's already a clean physiological signal) to get the
**ground-truth prototype**. New script:
`scripts/run_segment7_task_k_template_collapse_batch.m` (checkpointed/resumable, does not
modify any existing pipeline file). VIPL's `wave.csv` has no per-sample timestamp array, so
its ground-truth prototype used an assumed-uniform 60 Hz nominal rate (CMS60C's documented
native rate, same sensor family as UBFC DATASET_1's oximeter) — since both prototypes are
cycle-normalized to a fixed 256-sample fraction axis regardless of absolute fs, this
assumption affects reported *duration* fields only, not the shape comparison this task
actually needs (confirmed: `ensembleAverageBeats.m`'s zero-crossing beat segmentation and
two-anchor time-warp are invariant to a constant, even if imprecise, sample-rate scale
factor).

**Result: 100/100 subjects succeeded, 0 failures**
(`results/metrics/segment7_task_k_template_collapse_summary.csv`).

## Cross-subject correlation matrices

Pairwise Pearson correlation between every subject's 256-point prototype and every OTHER
subject's (off-diagonal only, 9900 pairs), separately for the rPPG set and the ground-truth
set (`results/metrics/segment7_task_k_correlation_summary.csv`,
`data/processed/segment7_task_k_correlation_matrices.mat` for the full 100x100 matrices):

| | rPPG prototypes | GT prototypes |
|---|---|---|
| Mean off-diagonal correlation | **0.9300** | **0.9719** |
| Median | 0.9502 | 0.9772 |
| Std | 0.0675 | 0.0214 |
| Min | 0.3913 | 0.8486 |
| Max | 0.9996 | 0.9996 |
| Fraction of pairs ≥ 0.80 | 0.9453 (9358/9900) | **1.0000 (9900/9900)** |

By source:

| Source (N) | rPPG mean off-diag | GT mean off-diag |
|---|---|---|
| UBFC-D1 (5) | 0.9578 | 0.9903 |
| VIPL v1/source1 (95) | 0.9288 | 0.9719 |

## Verdict

**The rPPG prototypes are NOT more similar to each other than the ground-truth prototypes
are — it's the opposite.** Mean cross-subject correlation is *lower* for rPPG (0.9300) than
for ground truth (0.9719), and ground-truth prototypes are dramatically more tightly
clustered (every single one of the 9900 GT pairs is ≥0.85 correlated; rPPG has real
outliers down to 0.39). This is the direction opposite of what template collapse would
predict (collapse would show rPPG prototypes converging to near-identical shapes while real
physiological variation keeps GT prototypes more spread out) — on this evidence, this
specific diagnostic finds **no support** for the concern that `adaptiveHarmonicFilter.m`'s
notch-confidence win is shape-convergence rather than genuine per-subject recovery.

**Necessary caveat, stated plainly rather than glossed over**: this test is not fully
conclusive either way, for a reason visible in the numbers themselves — ground-truth
contact-PPG prototypes across 100 *different, real* people are ALREADY extremely
self-similar by whole-cycle Pearson correlation (mean 0.97, literally 100% of pairs above
0.85). That is a known property of the PPG waveform's dominant shape (one big systolic peak
per cycle), not evidence of anything wrong with the ground truth — but it also means
whole-cycle Pearson correlation is a fairly coarse metric here: it is dominated by the
large-amplitude systolic peak shared by essentially everyone, and may not sensitively
separate "two prototypes share the same broad pulse shape" from "two prototypes share the
same fine dicrotic-notch detail," which is the specific thing template collapse would most
plausibly fake. So this result rules out the crude version of the concern (rPPG shapes
collapsing toward each other MORE than real physiology does) but does not, on its own,
positively prove every subject's individual notch timing/depth is independently recovered
rather than partially templated. A sharper follow-up (not attempted here) would restrict
the correlation comparison to a windowed region around the notch itself, rather than the
whole 256-point cycle.

**Bottom line for citing `adaptiveHarmonicFilter.m`'s Task B result**: no retraction
warranted by this diagnostic. The 4/5-vs-1/5 notch-confidence win is not contradicted by a
detectable cross-subject shape-convergence signal at the whole-cycle level. State the
caveat above alongside the result if pressed on methodology, but do not treat this task as
having found a problem — it didn't, on the metric it actually computed.

## Known limitations of this run

- UBFC DATASET_2 (42 more subjects with real GT waveform) was not included — disk space,
  not methodology. A rerun with DATASET_2 included, once space is available, would firm up
  the N=100 result rather than being expected to change its direction (the VIPL subgroup
  alone, N=95, already shows the same pattern as the smaller UBFC-D1 subgroup, N=5, so the
  finding is not an artifact of one dataset's idiosyncrasies).
- VIPL's ground-truth sample rate (60 Hz) is nominal, not measured per-subject (no
  timestamp array in `wave.csv`) — see the Method section for why this doesn't bias the
  shape comparison.
- Only VIPL scenario v1 (stable) was used, by design (see Method) — this task's finding
  should not be read as a claim about motion/talking/exercise scenarios.
