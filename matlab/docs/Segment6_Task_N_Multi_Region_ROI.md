# Segment 6 Task N — Multi-Region ROI Investigation

Extends the Task M line of inquiry (forehead-only ROI, the only region
validated up to this point) to three additional regions — glabella, malar
(upper cheekbone), and full cheek — compared against forehead individually
and via an agreement-based region-switching strategy, on a paired 20-subject
VIPL-HR subset originally across three scenarios — v1 (stable baseline), v2
(large head motion), and v4 (bright — see the correction note in Section 2,
and the label correction below it) — now extended to four with the addition
of v5 (dark), the real low-light scenario this report originally lacked.

**Label correction (added after this report was first written):**
`docs/Task_N_v4_v5_Brightness_Verification.md` proved by direct pixel
measurement that v4 is actually the **bright** scenario, not dark — the
opposite of what Section 2 below originally assumed from `ReadMe.pdf`
text. Every "v4 (dark)" reference in this document has been relabeled
"v4 (bright)" accordingly. The underlying MAE/RMSE/r numbers throughout
this report were always computed from real v4 video data and are
**unchanged** — only the scenario's name and the light-condition
narrative built on top of it were wrong. The true v5 (dark) 4-region
comparison this report originally lacked has since been run and is added
as a fourth scenario row in Section 5.

**Design constraint carried over from Task J's CHROM/POS switching work**:
ground truth HR is not available at real inference time, so region
selection must be decidable from the video signal alone. Just as
`computeSwitchingEstimate.m` switches on CHROM/POS *agreement*, not on
which method is actually more accurate, `computeRegionSwitchingEstimate.m`
(Action 4, Section 4) selects a region using ONLY cross-region agreement.
Ground truth is used exactly once in this whole task — Action 5 (Section 5)
— purely to check afterward whether that agreement-based choice tracked
real accuracy.

## 0. Action 0 — Regression check on the existing forehead-only geometry

`roi/extractROISignals.m`'s pre-Task-N forehead crop is:
`roiX = [faceX + 0.30*faceW, faceX + 0.70*faceW]`,
`roiY = [faceY + 0.10*faceH, faceY + 0.30*faceH]` — the center 40% of face
width, upper 10%-30% of face height. Task N added a `roiMode` parameter
(default `'forehead'`) that must reproduce this exact geometry.

**Regression check, run before any other change was made:** re-ran the new
`extractROISignals.m` (default `roiMode`, unspecified) against three
already-processed subjects and diffed the new R/G/B output against the
`.mat` files already on disk from before this task:

| Subject | Source | maxAbsDiff (R, G, B) | `isequal` |
|---|---|---|---|
| `5-gt` | UBFC DATASET_1 | 0, 0, 0 | true / true / true |
| `6-gt` | UBFC DATASET_1 | 0, 0, 0 | true / true / true |
| `VIPL_p1_v1_source1` | VIPL-HR | 0, 0, 0 | true / true / true |

Byte-identical (`isequal` true, not just numerically close) on all three —
two UBFC subjects and one VIPL-HR subject, covering both video sources this
project uses. The default `roiMode` change is a pure no-op for every
existing caller. See Section 1 below for how this was achieved
(concatenate-then-`mean()` over a single-element cell array reduces to
exactly the original `mean(roiPatch(:))` computation, same floating-point
summation order, same result).

## 1. Action 1 — Four region modes in `extractROISignals.m`

All four regions are defined as fixed fractions of the detected
Viola-Jones **face** bounding box (`vision.CascadeObjectDetector()` output)
— this project has no facial-landmark detector, so every region below is a
face-box-relative approximation, not a landmark-driven crop. Same
largest-box-wins face selection as before ([[viola-jones-largest-bbox]]),
unchanged.

| Region | x fraction of faceW | y fraction of faceH | Notes |
|---|---|---|---|
| `forehead` (default, unchanged) | [0.30, 0.70] | [0.10, 0.30] | Original Task 2/Task M geometry, byte-identical (Section 0). |
| `glabella` | [0.42, 0.58] | [0.32, 0.40] | Flat area between the eyebrows: narrower than forehead, shifted down toward eye level, still above where eyebrows/eyes sit on a typical face-box proportion. |
| `malar` (upper cheekbone) | [0.15, 0.32] (L) / [0.68, 0.85] (R) | [0.45, 0.58] | Bilateral. Kept well above the jaw/mouth line (`y` stops at 0.58) since those move more with talking/expression, per the brief's instruction to avoid that zone. |
| `cheek` (fuller cheek) | [0.10, 0.35] (L) / [0.65, 0.90] (R) | [0.55, 0.75] | Bilateral. Wider and lower than malar, kept as its own mode specifically so malar-vs-cheek can be compared directly rather than merged, per the brief. |

**Malar/cheek left+right combination decision (documented explicitly, same
discipline as `chromCombine.m`'s normalization note):** both regions are
bilateral. Rather than producing two separate output traces per region
(which would break the "one trace per region" interface every other part
of this task depends on), the left-patch and right-patch pixel arrays are
**concatenated into one pool before averaging**, so
`R(frameIdx)`/`G(frameIdx)`/`B(frameIdx)` is the spatial mean over both
patches combined, not the mean of two independent per-patch means. The two
patches are built from equal fixed fractions of the same face box so they
are close to equal in pixel count in practice, but this is stated
explicitly rather than left implicit. Reasoning: (a) pooling more pixels
improves SNR, expected to matter specifically for the v4-bright comparison
this task investigates, and (b) it keeps every region's output the same
shape, so `computeRegionAgreement.m`/`computeRegionSwitchingEstimate.m`
never need bilateral-region special-casing.

`debugFrame` now always carries a `regionBBoxes` struct with all four
regions' boxes (`forehead`, `glabella`, `malarLeft`, `malarRight`,
`cheekLeft`, `cheekRight`), computed on every processed frame **regardless
of which single `roiMode` that call actually extracted from** — so a
single representative frame from any one region-mode run can still drive a
sanity PNG showing all four regions. `scripts/run_segment6_task_n_multi_region_batch.m`
draws all six boxes (malar/cheek shown as their real left+right sub-patches,
not a merged box, so the PNG shows exactly what was averaged) on one frame
per subject/scenario — 60 PNGs in `results/figures/*_multi_region_sanity.png`.

## 2. Action 2 — Extraction: 20 subjects × 3 scenarios × 4 regions

**Scenario correction, twice over (both flagged loudly, not silently
substituted):**

1. At the time this task was originally run, the task brief's low-light
   arm was assumed to be "v5". `VIPL-HR-V1/ReadMe.pdf` (checked directly,
   page 1) was read as stating:

   > **v4 (dark scenario):** The ceiling lamp of the room is turned off...
   > **v5 (bright scenario):** The filament lamp is turned on...

   — the opposite of the brief's assumption — so this task extracted and
   processed v4, not v5, for the low-light arm.

2. **Second correction, superseding the first:** `docs/
   Task_N_v4_v5_Brightness_Verification.md` later settled the question with
   direct pixel-intensity measurement on the actual video files (not
   another text source) and found **v4 is the bright scenario and v5 is
   the dark scenario** — matching the published VIPL-HR paper's Table 3
   (Niu et al.) and the *opposite* of the `ReadMe.pdf` reading above. So
   this task, despite the correction in step 1, ended up extracting and
   processing **v4 (the real bright scenario)** for what it called its
   "dark" arm — relabeled "v4 (bright)" throughout this document. The real
   dark scenario (v5) was not part of this task's original 3-scenario
   comparison; it has since been run as a follow-up and is added as a
   fourth scenario in Section 5. `docs/VIPL_Scenario_Coverage.md`'s prose
   already carries the correct v4=bright/v5=dark labels (verified current
   with this pass; no edit was needed there).

**Subject selection:** 20 subjects with `source1` present in v1, v2, AND
v4 (per `VIPL_Scenario_Coverage.md`'s coverage matrix), so the same 20
subjects are directly comparable across all three scenarios and all four
regions: `p1, p3, p4, p6, p7, p8, p9, p10, p11, p12, p13, p14, p15, p16,
p17, p18, p19, p20, p21, p22`. `p2` and `p5` were skipped (missing
`source1` in v2); `p84` was skipped (missing `source1` in v1). v1 was
already extracted locally; v2 and v4/`source1` (`video.avi`, `time.txt`,
`gt_HR.csv`, `gt_SpO2.csv`, `wave.csv`) were extracted for these 20
subjects via targeted per-entry `System.IO.Compression.ZipFile` extraction
from `VIPL-HR-V1/data/{p1-5,p6-10,p11-15,p16-20,p21-25}.zip` — the same
targeted-extraction discipline already used for v1/v7, not a full-archive
unzip (~73 GB free on `H:` before extraction, confirmed).

**Pipeline run:** for each of the 60 (subject, scenario) pairs, for each of
the 4 region modes: `loadVIPLVideo.m` (fs re-derived from `time.txt`,
unchanged) → `extractROISignals.m` (this task's only touched pipeline
file) → `detrendSignal.m` → `bandpassClean.m` → `chromCombine.m` →
`bandpassClean.m` → `fftHeartRate.m` — completely unmodified from
Segment 3/4, exactly per this task's file-scope restriction. **240
extraction runs total, 0 failures** — every subject/scenario/region
combination produced a usable HR estimate; no missing files, corrupt
videos, or detector errors. Per-region raw traces saved to
`data/processed/VIPL_pX_vY_source1_<region>_rgb_traces.mat` (240 files);
full per-subject/scenario/region HR table in
`results/metrics/segment6_task_n_region_hr_summary.csv`.

**Action 2b — the real v5 (dark) follow-up run (added after the v4/v5
label correction above).** Since Task N's original 3-scenario comparison
never actually covered the real dark condition (its "dark" arm was really
v4/bright), the same 20-subject pool was run a fourth time against
`v5/source1`, the confirmed-dark scenario. 5 of the 20 subjects
(`p1, p3, p4, p6, p7`) already had `v5/source1` on disk from the
brightness-verification pass; the other 15 (`p8-p22` minus the already-done
ones) were newly extracted with the same targeted per-entry
`System.IO.Compression.ZipFile` extraction from `VIPL-HR-V1/data/
{p6-10,p11-15,p16-20,p21-25}.zip` (~68 GB free on `H:` before extraction,
confirmed). The pipeline run itself reused every piece of Task N's
infrastructure completely unmodified — same `extractROISignals.m` region
modes, same detrend/bandpass/CHROM/FFT chain, same
`computeRegionAgreement.m`/`computeRegionSwitchingEstimate.m`/
`computeMetrics.m` calls — via a new driver script,
`scripts/run_task_n_v5_dark_batch.m`, that appends to the same
`segment6_task_n_region_hr_summary.csv` and
`segment6_task_n_validation_summary.csv` Action 2's script wrote (rather
than duplicating or rewriting Task N's original output files). **80
additional extraction runs (20 subjects × 4 regions), 0 failures** — every
subject/region combination produced a usable HR estimate. One implementation
note carried over unmodified from `loadVIPLVideo.m`: v5's `time.txt`-derived
frame rate disagreed with the container's claimed 25 fps by ~33-35% for
most of these 20 subjects (real ~16.1-16.6 fps, not 25) — the same
known/documented container-vs-`time.txt` discrepancy already established
for other VIPL scenarios (see `docs/VIPL_DATA_FORMAT.md` Section 4), not a
new issue introduced here.

## 3. Action 3 — `computeRegionAgreement.m`

Generalizes `computeAgreementConfidence.m`'s 2-way CHROM/POS disagreement
metric to 4 regions. Per subject: `relativeSpread = (max - min) / median`
across the four regions' HR estimates, a fraction (not percentage) — range
rather than standard deviation, chosen because it directly answers "how
far could one wrong region estimate be from the group," which is exactly
what the switching estimator needs. No threshold is hardcoded inside the
function (same discipline as Task I); this task's switching rule (Action 4)
turns out not to need one at all — see below.

Observed spread, pooled across the 20 usable subjects per scenario:

| Scenario | Mean relative spread | Median relative spread |
|---|---|---|
| v1 (baseline) | 0.397 | 0.316 |
| v2 (motion) | 0.422 | 0.338 |
| v4 (bright) | 0.270 | 0.128 |
| v5 (dark) | 0.216 | 0.138 |

Cross-region disagreement is substantial everywhere (30-40% of the median
HR under baseline/motion) — markedly worse than the ~29% CHROM/POS
disagreement threshold Task I found meaningful for its 2-way case — and is
*lowest* of all four scenarios under real dark light (v5: mean 0.216,
even below bright light's 0.270), not highest. Both lighting-condition
scenarios (v4-bright, v5-dark) show markedly less cross-region spread than
baseline/motion, which foreshadows Section 5's finding that region choice
matters most under baseline/motion, less so once a strong, roughly uniform
light source (bright or dark-with-single-lamp) dominates.

## 4. Action 4 — `computeRegionSwitchingEstimate.m`

**Rule, using ONLY cross-region agreement, stated explicitly:** for each
subject, take the four regions' HR estimates, compute their median, and
select the region whose estimate has the smallest absolute distance to
that median (`argmin_region |HR_region - median|`). "Or full consensus if
all four roughly agree" — the brief's other suggested starting rule —
collapses into this same rule without a separate branch: when all four
already agree, every region is close to the median and whichever happens
to be closest is picked, and since they agree, the choice barely changes
the resulting value. Ties are broken forehead > glabella > malar > cheek
(forehead is this project's only previously-validated region — a
tie-break preference, not an accuracy claim). Ground truth never enters
this function.

Region selection counts (of 20 subjects, per scenario):

| Scenario | forehead | glabella | malar | cheek |
|---|---|---|---|---|
| v1 (baseline) | 15 | 2 | 2 | 1 |
| v2 (motion) | 16 | 2 | 2 | 0 |
| v4 (bright) | 15 | 3 | 2 | 0 |
| v5 (dark) | 14 | 4 | 1 | 1 |

Forehead is selected 70-80% of the time in every scenario, dark included —
with a free-running median-closest rule and no landmark guidance,
forehead's narrower, better-centered box tends to sit closest to the pack
most often, even though (Section 5) it is not always the most *accurate*
region.

## 5. Action 5 — Validation (ground truth used only here)

| Scenario | Method | MAE (bpm) | RMSE (bpm) | Pearson r | n |
|---|---|---|---|---|---|
| v1 (baseline) | forehead | 10.79 | 21.19 | 0.127 | 20 |
| v1 (baseline) | glabella | 16.67 | 25.41 | 0.571 | 20 |
| v1 (baseline) | malar | 15.03 | 28.63 | 0.355 | 20 |
| v1 (baseline) | **cheek** | **5.27** | **7.91** | **0.852** | 20 |
| v1 (baseline) | switching | 8.00 | 16.56 | 0.621 | 20 |
| v2 (motion) | **forehead** | **8.18** | **11.18** | 0.575 | 20 |
| v2 (motion) | glabella | 17.77 | 25.20 | 0.037 | 20 |
| v2 (motion) | malar | 12.28 | 16.11 | 0.554 | 20 |
| v2 (motion) | cheek | 9.93 | 12.43 | 0.449 | 20 |
| v2 (motion) | **switching** | **7.72** | **10.68** | **0.662** | 20 |
| v4 (bright) | **forehead** | **3.03** | **4.67** | **0.942** | 20 |
| v4 (bright) | glabella | 12.08 | 18.80 | 0.194 | 20 |
| v4 (bright) | malar | 12.22 | 25.84 | 0.457 | 20 |
| v4 (bright) | cheek | 4.50 | 7.10 | 0.790 | 20 |
| v4 (bright) | switching | 3.52 | 4.79 | 0.897 | 20 |
| v5 (dark) | forehead | 6.54 | 11.32 | 0.581 | 20 |
| v5 (dark) | glabella | 9.86 | 13.84 | 0.390 | 20 |
| v5 (dark) | malar | 7.01 | 11.38 | 0.546 | 20 |
| v5 (dark) | **cheek** | **4.98** | **8.08** | **0.697** | 20 |
| v5 (dark) | **switching** | **4.79** | **6.92** | **0.791** | 20 |

Bold marks the best single region and, where switching beats every single
region outright, the switching row too, per scenario. v5 (dark) is the
**real** dark-light run, added as a follow-up after the v4/v5 label
correction (Section 2) — v1, v2, and v4's rows above are byte-identical to
this report's original numbers (confirmed against
`results/metrics/segment6_task_n_validation_summary.csv`); only v5's row is
new data.

**(a) Does switching beat the best single region? Now yes, in half the
scenarios tested.** With v5 (dark) added, switching beats the best single
region in 2 of 4 scenarios: v2 (motion) — MAE 7.72 vs forehead's 8.18, r
0.662 vs 0.575 — and now also v5 (dark) — MAE 4.79 vs cheek's 4.98, RMSE
6.92 vs 8.08, r 0.791 vs 0.697, a clean sweep on all three metrics. In v1
(baseline) and v4 (bright), switching is still clearly *worse* than that
scenario's best single region (v1: 8.00 vs cheek's 5.27; v4: 3.52 vs
forehead's 3.03). The reason is visible in Section 4's selection counts:
the switching rule picks forehead 70-80% of the time regardless of
scenario, so it mostly inherits forehead's own error pattern, and only
occasionally substitutes a different region (glabella/malar/cheek) on the
subjects where disagreement is largest. That substitution behaves
differently by scenario: in v1, switching (8.00) is noticeably better than
raw forehead-alone (10.79) because forehead's two worst outliers (`p21`,
`p22`, see (b) below) get partially rescued by the switch — but switching
still lands well short of just using cheek everywhere (5.27), the
scenario's actual best region. In v4, forehead alone is already excellent
(3.03, its best result of any scenario), so the ~25% of subjects the rule
switches away from it onto noisier glabella/malar estimates can only add
error, and switching (3.52) ends up worse than forehead alone. In v5
(dark), by contrast, forehead alone is mediocre (6.54, its second-worst
result of the four scenarios) — closer to the v1 baseline pattern than to
v4's — so the ~30% of subjects switching pulls away from forehead (onto
cheek, glabella, or malar; see Section 4's counts) land the estimate
closer to cheek's already-good baseline, and this time the substitution
tips switching just past cheek itself. Bottom line, revised: this
agreement-based switching is **not** a reliable universal win, but it is
no longer a pure wash either — it wins specifically in the two scenarios
(v2 motion, v5 dark) where the single best-performing region (forehead in
v2, cheek in v5) is not overwhelmingly dominant on its own, and loses in
the two scenarios (v1, v4) where one region (cheek in v1, forehead in v4)
is already a clear standout that switching's ~20-30% substitution rate can
only dilute.

**(b) Does the best single region change with scenario? Yes — and the
real dark result answers the question this report originally got backwards.**
Cheek wins baseline (v1) **and real dark (v5)**; forehead wins both motion
(v2) and bright light (v4). This is the key finding the v4/v5 label error
obscured: this report's original text (before correction) claimed
forehead was the best region "in the dark," built on v4 data that was
actually bright light. Now that the real dark scenario has been run, the
answer is different — **cheek wins real dark, not forehead**, matching
cheek's baseline win rather than extending forehead's bright/motion
pattern. So the true picture is a light/motion split, not a "forehead
wins whenever conditions are hard" pattern: cheek wins under stable,
non-adversarial lighting (both v1's even ambient light and v5's single
warm filament lamp), while forehead wins specifically when the frame
either moves (v2) or is strongly, evenly overlit (v4) — conditions where a
smaller, more centrally-placed patch has an advantage over a larger,
lower one. This also retroactively confirms that Section 5(b)'s earlier
"bright-light" explanation (forehead's narrower patch resisting glare
under v4's strong lighting) was on the right track as a *bright-light*-specific
account, precisely because it does **not** generalize to v5's real dark
condition — cheek's larger patch, which that explanation predicted would
struggle under strong/uneven light, is back to winning once the light
source is dim, again consistent with pooling more skin area helping SNR
whenever lighting is not aggressively bright or uneven. One caveat on the
v1 forehead number specifically: two subjects, `VIPL_p21` (forehead 127.2
vs GT 68, a ~1.9x harmonic-confusion error) and `VIPL_p22` (forehead 112.5
vs GT 47, near the 0.7 Hz search-band edge), account for most of
forehead's v1 MAE/RMSE on their own — `p21` is the same subject already
flagged for exactly this CHROM harmonic-confusion pattern in Task H1/I
([[segment6-refinement-findings]]), so this is a known, previously-observed
failure mode recurring in the forehead-only v1 pool, not a new bug in this
task's code. Glabella and malar remain worse than forehead and cheek
across *all four* scenarios by a wide margin, every time — they are not a
viable default region on this evidence, only ever plausible as an
occasional switching-target.

**Verdict on extending to the full subject pool:** the scenario-dependent
best-region result (5b) is real and reproducible across four separate
20-subject scenario runs with zero pipeline failures across all of them,
and is worth extending — with the important correction that the
light-condition driver of forehead's wins is specifically *bright/uneven*
light and motion, not "low light" as originally miscategorized. The
switching estimator (5a) is more promising than the original 3-scenario
result suggested — it now wins outright in 2 of 4 scenarios (v2, v5) — but
still isn't a reliable universal default, since it clearly loses in the
other 2 (v1, v4). A revised switching rule that weights toward
forehead/cheek specifically, and ideally factors in which single region is
already a clear standout for the current conditions (rather than a
scenario-blind nearest-to-median vote across all four regions equally), is
still the more promising next step before spending more extraction/
processing budget on a bigger pool.

## 6. Scope reminder

**This is a MATLAB-only validation.** No Android/Kotlin work was
authorized, implied, or performed by this task. The existing
`android/` skeleton ([[android-skeleton-status]]) was not touched. If
these results are judged worth acting on, porting multi-region ROI
tracking (four simultaneous region crops, region-agreement computation,
and the switching rule) to the Android app is a separate, materially
larger decision — it requires either real-time landmark tracking or a
much more expensive per-frame multi-crop pipeline than the app's current
single forehead-box design, and is not assumed as an automatic next step
here.
