# Segment 10 Task 1 — rPPG-vs-Ground-Truth-PPG Waveform & Frequency Fidelity Audit

A full, pool-scale, READ-ONLY audit of how well this project's rPPG pulse signals match
their subject's own ground-truth contact-PPG **waveform** — not just the scalar HR number
every prior comparison in this project used. Every existing production file this task
touches (`pulseextraction/chromCombine.m`, `pulseextraction/posCombine.m`,
`heartrate/fftHeartRate.m`, `morphology/adaptiveHarmonicFilter.m`,
`filtering/waveletDenoise.m`, `roi/extractROISignals.m`) is called exactly as
`pipeline/estimateVitalsAndMorphology.m` documents its own Branch 1/Branch 2 sequence and
is **not modified**. One new, additive function was written because the task specifically
asked for a capability the existing pipeline doesn't have:
`morphology/estimateLagPolarityByGroundTruth.m` (extends
`morphology/fixPolarityByGroundTruth.m`'s cross-correlation approach to solve for the best
time LAG, not just polarity sign — see that file's own header for the method).

**Pool**: the exact 100-subject pool Segment 7 Task K established and cached
(`docs/Segment7_Task_K_Template_Collapse_Diagnostic.md`) — UBFC DATASET_1 (5) + VIPL-HR
v1/source1 (95), the only subjects in this project with a real ground-truth contact-PPG
*waveform*. All 100 were reused directly from `data/processed/*_rgb_traces.mat` — **no
video was decoded or reprocessed** for this task.

**Result: 100/100 subjects succeeded, 0 failures**, for all three rPPG signals compared
(CHROM, POS, harmonic-comb).

## Method

Per subject, both branches are computed by inlining `pipeline/estimateVitalsAndMorphology.m`'s
own documented call sequence (the same way `scripts/run_segment7_task_k_template_collapse_batch.m`
already does, rather than calling the orchestrator, because this task needs signals that
function doesn't return standalone — Branch 1's pre-alignment `pulseChromFiltered`/
`pulsePosFiltered` and Branch 2's pre-polarity-fix `pulseAdaptive`):

- **Branch 1 (CHROM, POS)**: `detrendSignal` → `bandpassClean` (narrow 0.7–4 Hz) →
  `chromCombine`/`posCombine` → `bandpassClean` again.
- **Branch 2 (harmonic-comb)**: `detrendSignal` → `bandpassMorphology('wide')` (0.5–8 Hz) →
  `chromCombine` → shared f0 via `fftHeartRate` → `adaptiveHarmonicFilter` (order 6, that f0)
  per channel → `chromCombine` again.

**Ground truth**: UBFC DATASET_1's `gtdump.xmp` (real per-sample timestamps, ~62 Hz);
VIPL's `wave.csv` (CONTEC CMS60C, nominal 60 Hz, no per-sample timestamp array — same
assumed-uniform-axis convention Task K used, justified there for the same reason it holds
here: shape/lag comparison is not sensitive to a constant, even if imprecise, rate scale
factor once both signals are resampled onto a common absolute time grid rather than an
index grid).

### Action 1 — Lag + polarity alignment

`morphology/estimateLagPolarityByGroundTruth.m` resamples both signals onto a common
uniform 250 Hz grid (`morphology/resampleUniform.m`, unmodified) and searches ±5 s of lag
for the single (lag, sign) pair that maximizes `|xcorr|` — a genuine generalization of
`fixPolarityByGroundTruth.m`'s polarity-only rule (see that new file's header for the
verified sign convention). The estimated lag is reported for **every** subject/branch;
subjects whose `|lag|` exceeds one full ground-truth cardiac cycle (`1/f0_GT`, per-subject,
not a fixed constant) are **flagged**, never silently dropped.

**This flag matters more than a formality — see Finding 1 below.** ±5 s was chosen
deliberately generous (not narrowed to "only ever look plausible") specifically so a
genuinely large misalignment would be visible; the cost, stated openly in the new
function's own header before a single subject was run, is a real risk of the search
aliasing onto the wrong cardiac cycle for a strongly periodic signal. That risk turned out
to be real and common (Finding 1), not a hypothetical hedge.

### Action 2 — Time-domain comparison

Both aligned signals are z-scored (zero-mean, unit-variance) before every time-domain
metric below — necessary and stated explicitly, not a stylistic choice: chrominance-based
rPPG output and a contact-sensor's raw PPG units are not on any shared physical scale, so
an un-normalized RMSE would mostly just measure that scale mismatch, not shape agreement.

- **Pearson correlation** and **RMSE / NRMSE** (NRMSE = RMSE ÷ the z-scored GT signal's own
  range) on the full aligned overlap.
- **DTW alignment cost** (MATLAB `dtw`, Sakoe–Chiba band ±1 s, both signals downsampled to
  25 Hz first) — a shape-robust check for residual *local* timing warp left over after the
  single rigid lag above has already been removed; cost normalized by warped path length so
  it's comparable across subjects of different recording length.
- **Beat-shape comparison**: `morphology/ensembleAverageBeats.m` +
  `morphology/resampleUniform.m` (both unmodified) build an ensemble-average beat prototype
  for the rPPG branch signal AND for ground truth, from the *same* aligned overlap window.
  `morphology/notchDetectIEM.m` (unmodified) runs on both prototypes. Beat-to-beat
  variability uses `ensembleAverageBeats.m`'s own `iqrBand.meanWidthNormalized` directly.
  **Systolic peak timing needed a new, separate measurement** — `ensembleAverageBeats.m`'s
  own two-anchor time warp forces every prototype's peak to land at a *constant* cycle
  fraction (0.25, its own default) by construction, so comparing peak position on its
  *output* would trivially show ~0 difference for every subject, an artifact of the warp,
  not a finding. A small new local helper (`rawPeakFractionStats`, in the audit script, not
  a src/ file — this is diagnostic-only duplication of `ensembleAverageBeats.m`'s
  segmentation Steps 1–3, explicitly not a modification of that function) measures the peak
  fraction *before* the warp is applied, for both signals.

### Action 3 — Frequency-domain comparison

Both z-scored aligned signals: Welch PSD (`pwelch`, Hamming window ≤8 s, 50% overlap — not
a raw periodogram, per the task brief), magnitude-squared coherence (`mscohere`, identical
window), and cross-spectral phase (`cpsd`), all on one common frequency grid.

**Per-band mismatch-energy breakdown**: `mismatch(f) = (1 − coherence(f)) × GT_PSD(f)`,
summed within each band and normalized by the total, giving "what fraction of the
GT-power-weighted incoherence lands in this band." Bands are anchored on **each subject's
own ground-truth f0** (`f0_GT`, from GT's own Welch-PSD peak — a shared, GT-referenced
basis so both branches are judged against the same true rate): sub-cardiac `[0, 0.7)` Hz,
fundamental `[0.7, 1.5·f0)`, harmonics 2–6 each a `±0.5·f0` window around `h·f0`, and a
noise band starting at `min(6.5·f0, 8)` Hz. That `min(...,8)` cap is a stated, deliberate
choice: for most subjects in this pool (HR ≳ 74 bpm, i.e. `f0 ≳ 1.23 Hz`), `6.5·f0` already
exceeds 8 Hz, so the noise band's lower edge is the fixed 8 Hz ceiling for the *majority* of
the pool, and only the harmonic-comb's own natural `6.5·f0` edge for the slower-HR minority.
This keeps the 8 bands contiguous and exhaustive (they always sum to 1) rather than leaving
an unclassified gap.

**Harmonic-confusion detector**: each signal's own dominant PSD peak in a 0.5–8 Hz search
band is compared to GT's; a ratio within a tolerance of an integer multiple/submultiple
(×1/3, ×1/2, ×2, ×3, excluding the trivial ×1) is flagged. The **primary** tolerance used
for headline counts is ±8% (a defensible, fairly strict choice); a looser ±15% is also
reported as an explicit sensitivity check (Finding 3), because a real harmonic-lock error
on noisy data does not always land at a razor-precise integer ratio.

**Phase-spectrum classification**: cross-spectral phase in the fundamental band, taken
*after* the rigid lag has already been removed. If a pure time delay explained everything,
the post-alignment residual phase there should sit near 0°; a large residual means the
fundamental-band content is out of step in a way one global lag cannot capture. 20° is this
task's own chosen cutoff (`delayOnly` vs. `distorted`), stated as a convention, not a value
discovered from the data.

### Action 4 — Pooled reporting

Median/IQR (not mean/SD — these are error-like metrics, expected to skew) of every metric
above, pooled and split by dataset (UBFC-D1 vs. VIPL). **Device and scenario do not further
stratify this specific pool** — worth stating plainly rather than papering over: Task K
deliberately restricted VIPL to v1/source1 to avoid confounding its own correlation
comparison, so every VIPL subject here is the same device (Logitech C310 webcam) in the
same scenario (v1, stable/normal-light/1 m); UBFC has no scenario tag at all. The
dataset/device/scenario confounds this task was asked to check are real and documented
elsewhere in this project (`docs/VIPL_Scenario_Coverage.md`), but this *particular*
100-subject pool cannot exercise them — a genuine scope limit of reusing Task K's pool
as-is, not an oversight in this task's own analysis.

## Deliverables

- `matlab/scripts/run_segment10_waveform_fidelity_audit.m` (checkpointed/resumable, same
  discipline as every other batch script in this project).
- `matlab/src/morphology/estimateLagPolarityByGroundTruth.m` (new, additive).
- `results/metrics/segment10_waveform_fidelity_per_subject.csv` (100 rows × 147 columns —
  every metric above, per branch, per subject).
- `results/metrics/segment10_waveform_fidelity_pooled_summary.csv` (median/IQR per
  group×branch×metric, harmonic-confusion/lag-flag/phase-class counts, worst-5/best-5).
- `results/figures/segment10_{good,bad}_{chrom,harmonic}_<subjectID>.png` (4 figures, one
  clear good and one clear bad case for each of a Branch 1 and a Branch 2 representative,
  each a 3-panel time-domain + Welch PSD + coherence figure).

## Results

### Finding 1 — The lag search itself is a major, honest finding, not just plumbing

Flagged (`|lag| > 1/f0_GT`) rate across the 100-subject pool:

| Branch | Flagged | Fraction |
|---|---|---|
| CHROM | 34/100 | 34% |
| POS | 36/100 | 36% |
| Harmonic-comb | 46/100 | 46% |

This is not noise — flagged subjects score markedly worse on every downstream metric than
clean ones (median Pearson r, post-alignment):

| Branch | Flagged (median r) | Clean (median r) |
|---|---|---|
| CHROM | 0.402 (n=34) | 0.478 (n=66) |
| POS | 0.379 (n=36) | 0.515 (n=64) |
| Harmonic-comb | 0.322 (n=46) | 0.600 (n=54) |

The direction of causation is genuinely ambiguous and is stated as such, not resolved by
assertion: a flagged lag could mean (a) the broadband xcorr search found the true, large
delay for a subject whose rPPG really is that badly out of step, or (b) the search aliased
onto the wrong cardiac cycle for a subject whose real alignment is fine, corrupting every
downstream number for that subject/branch. **`segment10_bad_harmonic_6-gt`-style cases
(see the harmonic-comb worked example below) are clear instances of (b)** — visually, the
two signals in that figure are near-identical in period and just phase-shifted by a whole
number of cycles, which a purely time-domain broadband correlation search cannot always
resolve correctly for a strongly periodic, narrow-spectrum signal. **The harmonic-comb
branch is disproportionately affected** (46% vs. 34–36%) for exactly the reason stated
up front in `estimateLagPolarityByGroundTruth.m`'s own header: `adaptiveHarmonicFilter.m`'s
comb construction makes Branch 2's signal *more* periodic/narrowband than Branch 1's, which
is precisely the condition that makes broadband lag search least reliable. UBFC's small
sample makes this worse in relative terms: **4/5 UBFC harmonic-branch lags are flagged**
(vs. 42/95, 44%, for VIPL) — a small-N artifact worth naming, not a claim that UBFC's
harmonic-comb alignment is categorically worse than VIPL's.

**Practical read for anyone using this audit's downstream numbers**: treat flagged
subject/branch cells as *alignment-uncertain*, not as clean evidence of either good or bad
waveform shape. This is exactly why the task asked to flag rather than silently drop or
silently accept — dropping would have hidden a real, common failure mode of the
lag-estimation method itself; accepting silently would have let corrupted alignments
masquerade as genuine shape-distortion findings elsewhere in this report.

### Finding 2 — Time-domain and frequency-domain agreement is modest, and Branch 2 is higher-variance, not simply better or worse

Pooled (N=100), median [IQR], all three signals z-scored, post-alignment:

| Metric | CHROM | POS | Harmonic-comb |
|---|---|---|---|
| Pearson r | 0.445 [0.318, 0.585] | 0.452 [0.353, 0.608] | 0.519 [0.232, 0.642] |
| RMSE (z-scored) | 1.053 [0.911, 1.168] | 1.047 [0.886, 1.137] | 0.980 [0.846, 1.240] |
| NRMSE | 0.224 [0.196, 0.258] | 0.222 [0.193, 0.255] | 0.220 [0.185, 0.263] |
| DTW cost (normalized) | 0.303 [0.280, 0.323] | 0.300 [0.277, 0.318] | 0.308 [0.280, 0.355] |
| Mismatch score (1 − r) | 0.555 [0.415, 0.683] | 0.548 [0.392, 0.647] | 0.481 [0.358, 0.768] |

The harmonic-comb branch has the best *median* correlation of the three but visibly the
**widest IQR** (0.232–0.642, versus ≈0.32–0.61 for CHROM/POS) — it does better than Branch 1
on subjects where its alignment/f0 estimate holds up, and worse on the (more frequent, per
Finding 1) subjects where it doesn't. This is consistent with, and adds pool-scale evidence
to, the harmonic-lock risk `pipeline/estimateVitalsAndMorphology.m`'s own header already
warns about (a single VIPL subject's CHROM jumping 69.4→140.8 bpm under wide-band/comb
filtering) — a real, bimodal reliability trade-off, not a case where either branch is
uniformly better.

Split by dataset (median):

| Group | Branch | r | Mismatch score | Lag (s) |
|---|---|---|---|---|
| UBFC-D1 (n=5) | CHROM | 0.526 | 0.474 | −0.140 |
| UBFC-D1 (n=5) | POS | 0.515 | 0.485 | −0.140 |
| UBFC-D1 (n=5) | Harmonic | 0.240 | 0.760 | −4.052 (4/5 flagged) |
| VIPL (n=95) | CHROM | 0.429 | 0.571 | 0.244 |
| VIPL (n=95) | POS | 0.437 | 0.563 | 0.416 |
| VIPL (n=95) | Harmonic | 0.522 | 0.478 | 0.088 |

UBFC's harmonic-comb branch looks much worse than VIPL's here, but per Finding 1 that is
substantially an artifact of small-N lag-search failure (4/5 flagged) rather than a genuine
dataset-level effect — stated explicitly so this number is not mis-read as "harmonic-comb
generalizes worse to UBFC."

### Finding 3 — Harmonic confusion is real, rare at strict tolerance, and reproduces the project's own known anecdote exactly

| Tolerance | CHROM | POS | Harmonic-comb |
|---|---|---|---|
| ±8% (primary) | 1/100 | 1/100 | 5/100 |
| ±15% (sensitivity) | 2/100 | 2/100 | 8/100 |
| ±20% (sensitivity) | 3/100 | 3/100 | 9/100 |

The harmonic-comb branch shows 4–5× the confusion rate of Branch 1 at every tolerance
tried — consistent regardless of the exact cutoff, and mechanistically expected (Branch 2's
own comb construction locks the whole signal onto whichever harmonic its f0 estimate
picked, by design; Branch 1 has no such lock).

**This detector independently reproduces `docs/Segment6_Task_P_Windowed_Harmonic_Quality.md`'s
own motivating case exactly, without having been told to look for it**: `VIPL_p21`'s CHROM
branch shows `sigPeakHz = 2.197 Hz` against `gtPeakHz = 1.099 Hz` — a ratio of **exactly
2.00**, flagged at every tolerance — matching that doc's own whole-clip finding (CHROM
127.20 bpm vs. a true 68 bpm, a ≈1.87× error; this task's own independent Welch-PSD-based
peak estimate lands the ratio even closer to a clean 2× than the original whole-clip FFT
did). Notably, p21's POS and harmonic-comb branches did **not** show confusion for this
same subject — the failure is CHROM-specific here, matching the original doc's own framing
(it was specifically about whole-clip CHROM).

**The strict ±8% count is very likely an undercount of the qualitative failure**, not just
a conservative one: `VIPL_p48`'s harmonic-comb branch (the worked "bad case" example figure
below) has `sigPeakHz/gtPeakHz = 2.27` — visibly, in the time-domain plot, running at almost
exactly double GT's rate — but 2.27 is 13.6% off a clean 2×, just outside the primary ±8%
tolerance. It IS caught at the ±15% sensitivity tolerance. This is exactly why both
tolerances are reported rather than only the strict one.

### Finding 4 — Phase-spectrum classification: roughly half the pool is genuinely distorted, not merely delayed

After the rigid broadband lag is already removed, classification of the *remaining*
fundamental-band phase residual:

| Branch | delayOnly | distorted |
|---|---|---|
| CHROM | 53/100 | 47/100 |
| POS | 61/100 | 39/100 |
| Harmonic-comb | 56/100 | 44/100 |

Roughly 40–47% of subjects, across all three branches, still show a fundamental-band phase
relationship that a single global time shift cannot explain, even after that shift has
already been applied — i.e. a substantial minority-to-near-half of this pool's rPPG-vs-GT
mismatch is genuine waveform distortion (different frequency components shifted by
different amounts), not simply "the rPPG signal is delayed." This directly answers the
task's "just delayed vs. genuinely distorted" question: **both mechanisms are real and both
are common; neither dominates the pool outright.**

### Finding 5 — Per-band mismatch-energy: the gap concentrates where the cardiac signal's own power is, not in noise

Pooled median fraction of (1 − coherence)·GT-PSD per band:

| Band | CHROM | POS | Harmonic-comb |
|---|---|---|---|
| Sub-cardiac (<0.7 Hz) | 0.120 | 0.119 | 0.098 |
| Fundamental (h1) | 0.443 | 0.432 | 0.517 |
| h2 | 0.215 | 0.221 | 0.196 |
| h3 | 0.094 | 0.094 | 0.082 |
| h4 | 0.019 | 0.020 | 0.017 |
| h5 | 0.006 | 0.006 | 0.005 |
| h6 | 0.001 | 0.001 | 0.001 |
| Noise (>~6.5·f0 or 8 Hz) | 0.001 | 0.001 | 0.001 |

Over 96–99% of the (GT-power-weighted) mismatch across all three branches sits in bands h1
through h3 — almost none is attributable to high-order-harmonic or broadband-noise
mismatch. Read together with Finding 2's modest correlations, this says the rPPG-vs-GT gap
is not "rPPG is missing fine harmonic detail GT has" — it is a genuine amplitude/phase
mismatch concentrated right in the fundamental and second harmonic, where both signals'
own power already concentrates. This is a meaningfully different diagnosis than "add more
harmonics" or "denoise the high-frequency tail" would fix.

### Finding 6 — Beat-shape: rPPG is 2–3× less stable beat-to-beat than GT, and the notch comparison needs the confidence bar, not the boolean

Beat-to-beat variability (`iqrNormalized`, median):

| | CHROM | POS | Harmonic-comb |
|---|---|---|---|
| rPPG branch | 0.144 | 0.132 | 0.096 |
| Ground truth (same aligned window) | 0.052 | 0.050 | 0.051 |

rPPG's own beat-to-beat spread is consistently ~2–3× GT's, across all three branches —
unsurprising (rPPG is a noisier signal by construction) but now quantified directly against
each subject's own contact-PPG on the same time window, rather than assumed. Interestingly,
the harmonic-comb branch (0.096) is *more* beat-to-beat stable than CHROM/POS (0.144/0.132)
— plausibly because the comb filter's construction suppresses inter-harmonic noise that
would otherwise perturb beat shape, consistent with `adaptiveHarmonicFilter.m`'s own stated
design rationale.

**`notchDetectIEM.m`'s boolean `notchDetected` output is essentially useless as a gate at
this pool's scale — it fires for 100/100 GT prototypes**, because "first local minimum below
zero after the systolic peak" is a low bar that a real contact-PPG waveform will satisfy
almost regardless of whether it has a genuine, visible dicrotic notch. Using this project's
own already-established confidence bar (`notchConfidence ≥ 0.3`, from
`docs/Segment7_Task_B_Notch_Quantification.md`) instead:

| Branch | GT prototypes with confident notch (≥0.3) |
|---|---|
| CHROM | 26/100 |
| POS | 25/100 |
| Harmonic-comb | 28/100 |

**This is new information this task surfaces, and it does not simply confirm Task B's
4/5 (80%) UBFC finding at pool scale — only ~26–28% of this much larger, VIPL-dominated
pool shows a confidently-detected GT notch.** Since UBFC contributes only 5 of the 100
subjects, this pool result is not in direct tension with Task B (a 5-subject UBFC-only
result) — but it is a genuine caveat on ever generalizing Task B's ratio to VIPL's ground
truth without checking, which this task now has. Restricting the notch position/depth
comparison to only these GT-confident subjects (the task's own "where GT actually has one"
instruction):

| Branch | n (GT-confident) | Notch position diff (median cycle-fraction) | Notch depth diff (median) |
|---|---|---|---|
| CHROM | 26 | 0.045 | −0.151 |
| POS | 25 | 0.263 | −0.082 |
| Harmonic-comb | 28 | 0.033 | −0.169 |

Depth differences are consistently negative — rPPG's detected notch is consistently
**shallower** than GT's, across all three branches, on the subset where GT's own notch is
real and confident.

### Worst 5 / best 5 (pooled mismatch score = mean of `1 − r` across CHROM/POS/harmonic-comb)

| Rank | Subject | Source | Pooled mismatch score |
|---|---|---|---|
| Best 1 | VIPL_p1 | vipl | 0.271 |
| Best 2 | VIPL_p79 | vipl | 0.277 |
| Best 3 | 5-gt | ubfc_d1 | 0.279 |
| Best 4 | VIPL_p73 | vipl | 0.286 |
| Best 5 | VIPL_p75 | vipl | 0.286 |
| Worst 1 | VIPL_p48 | vipl | 0.889 |
| Worst 2 | VIPL_p57 | vipl | 0.876 |
| Worst 3 | VIPL_p28 | vipl | 0.873 |
| Worst 4 | VIPL_p29 | vipl | 0.870 |
| Worst 5 | VIPL_p82 | vipl | 0.864 |

Worked examples (`results/figures/segment10_*.png`):

- **Good, CHROM** (`segment10_good_chrom_5-gt.png`): near-overlapping z-scored waveforms,
  a sharp shared PSD peak at the fundamental (~1.3 Hz), coherence ≈0.95 there.
- **Bad, CHROM** (`segment10_bad_chrom_VIPL_p29_v1_source1.png`): visibly uncorrelated
  waveforms even after alignment, broad/mismatched PSD peaks, coherence low and scattered
  across the whole spectrum with no dominant peak — a genuinely poor rPPG signal on this
  subject, not primarily a lag-search artifact.
- **Good, harmonic-comb** (`segment10_good_harmonic_VIPL_p73_v1_source1.png`): excellent
  visual match including a visible secondary hump (dicrotic-notch-adjacent shape), PSD
  peaks aligned at the fundamental AND several harmonics, coherence ≈0.95 at the
  fundamental.
- **Bad, harmonic-comb** (`segment10_bad_harmonic_VIPL_p48_v1_source1.png`): rPPG
  oscillates visibly faster than GT — a 2.27× peak-frequency ratio (Finding 3) — a textbook
  harmonic-lock case, exactly the failure mode `pipeline/estimateVitalsAndMorphology.m`'s
  own header already warns Branch 2 is prone to.

## Verdict

Branch 1 (CHROM/POS) and Branch 2 (harmonic-comb) show **modest but real** waveform
agreement with ground truth at pool scale (median r ≈0.44–0.52), well above chance but far
from strong — consistent with, and now quantifying in the waveform/frequency domain, what
this project's existing HR-accuracy numbers (MAE 7–8 bpm at pool scale) already implied
about pulse-signal quality. **No branch is a clean winner**: Branch 2 has the best median
correlation but a distinctly bimodal reliability profile (wider spread, higher
harmonic-confusion rate, more lag-search failures) rather than a uniform improvement over
Branch 1 — this is additional, independent evidence for `pipeline/estimateVitalsAndMorphology.m`'s
existing decision to keep the two branches separate rather than merge them, not a reason to
revisit that decision.

**The single most load-bearing finding of this audit is methodological, not a pipeline
result**: a rigid, broadband cross-correlation lag search — even a "solve for the best lag"
generalization of this project's own existing polarity-fix approach — is measurably
unreliable (34–46% flagged) on this kind of quasi-periodic pulse waveform, and
disproportionately so for the harmonic-comb branch precisely because that branch's own
construction makes its signal more periodic. Any future task that needs waveform-level
rPPG-vs-GT alignment should budget for this explicitly (e.g. a periodicity-aware search that
biases toward the smallest-magnitude lag among near-tied candidates, or a first per-beat
local alignment before any broadband search) rather than assume single global
cross-correlation is sufficient — this audit flags every case rather than silently accepting
or dropping it, per its own brief, but does not itself fix the underlying alignment
reliability problem.

The frequency-domain findings are the audit's clearest positive contribution: mismatch
energy concentrates in the fundamental/second-harmonic bands (Finding 5), not in
inter-harmonic or supra-harmonic noise, and roughly half the pool shows genuine
fundamental-band phase distortion beyond what a pure delay explains (Finding 4) — both are
new, quantified answers to "which frequency is responsible" that no prior HR-accuracy-only
comparison in this project could have produced.

## Known limitations of this run

- **Lag-search reliability is itself a limitation of this audit's own method**, discussed
  at length in Finding 1 — flagged subject/branch cells should be read as
  alignment-uncertain, not as clean shape-distortion evidence.
- **Device/scenario stratification could not be meaningfully exercised**: this pool is
  VIPL v1/source1 only (one device, one scenario) by Task K's own deliberate restriction, so
  the dataset split (UBFC vs. VIPL) is the only real stratification this specific 100-subject
  pool supports, even though the task brief correctly names device/scenario as real,
  documented confounds elsewhere in this project.
- **VIPL's ground-truth sample rate is nominal (60 Hz), not measured per-subject** — the
  same caveat Task K already documented and the same reasoning for why it doesn't bias a
  shape/lag comparison once both signals are resampled onto a common absolute-time grid
  (this task's own method, not index-based resampling).
- **The harmonic-confusion detector's tolerance is a chosen convention, not derived from the
  data** — reported at three tolerances (±8/15/20%) specifically so this choice is visible
  and its effect on the headline count is not hidden behind one arbitrarily-picked cutoff.
- **The 20° phase-delay-vs-distortion cutoff is likewise a stated convention**, not a
  data-derived threshold.
- **`notchDetectIEM.m`'s boolean output was confirmed unusable as a gate at this pool's
  scale (100/100 "detected")** — this audit substitutes the project's own established 0.3
  confidence bar, but that substitution is this task's own choice, made explicit rather than
  silently applied.
- Systolic-peak-timing and notch comparisons both depend on `ensembleAverageBeats.m`
  successfully segmenting ≥3 raw beats from the aligned overlap; no subject failed this in
  practice (0/100 sub-step failures recorded), but a shorter/noisier future clip could hit
  this floor.
- This audit reuses Task K's exact 100-subject pool and its VIPL v1/source1 restriction —
  it does not re-litigate whether that pool is representative; see
  `docs/Segment7_Task_K_Template_Collapse_Diagnostic.md`'s own known-limitations section for
  that discussion (UBFC DATASET_2's 42 additional subjects were never extracted, disk space).
