# Segment 24 — PREREGISTRATION (written and committed BEFORE any read-out is computed on any Segment 24 set)

Question: does the Segment 23 read-out candidate (windowed-peak / frequency-state-tracker HR read-out for CHROM/POS) beat production `fftHeartRate.m` on data it was not picked on, and is any gain the *mechanism* or just its *narrower band*?
This is a validation segment. **No tuning happens here.** Date of registration: 2026-09-20.

## 0. What changed vs. the original brief (disclosed)

* Step 0 found UBFC-D2 was **not** untouched (Segment 14 used it for Branch 2 gate validation). User decision: D2 is a disclosed SECONDARY second-look; a genuinely clean PRIMARY set must come from elsewhere.
* **There are no unused VIPL-HR-V1 subjects.** `I:\...\VIPL-HR-V1\data` holds exactly p1–p107 (21 zips, verified) and all 107 are already in MAIN_112 (the pool the candidate was picked on). The PRIMARY set is therefore **unused VIPL *videos* (other scenarios) of the same 107 people: held out by video/scenario, NOT by subject.** Segment 14's own doc (§1) had already flagged exactly this limitation for VIPL scenarios. The read-outs have no per-subject fitted parameters and were selected on MAIN_112 (v1 clips) only, so this is a real but weaker held-out claim than "new people". Any verdict text must carry this caveat.

## 1. D2 prior-use audit (question asked of each doc: did it compute Branch-1 CHROM/POS **HR error** on any UBFC-D2 subject, or select/tune any HR read-out parameter using UBFC-D2 data?)

| Doc | Answer | Evidence |
|---|---|---|
| `Segment6_Task_N_Multi_Region_ROI.md` | **NO** | Only UBFC subjects named are DATASET_1: "\| `5-gt` \| UBFC DATASET_1 \|", "\| `6-gt` \| UBFC DATASET_1 \|" (lines 49–50); zero matches for DATASET_2/UBFC-D2/D2 in the file. (Segment 14 §1's "used in Segment 6 Task N" remark refers to *VIPL* v2/v5, not D2.) |
| `Segment10_Task1_Waveform_Fidelity_Audit.md` | **NO** | "UBFC DATASET_2's 42 additional subjects were never extracted, disk space" (line 447). |
| `Segment15_Task1…Task4` (all `Segment15*` docs + `run_segment15_task3_task4_cpace_full_evaluation.m`) | **NO** | Only D2 mention is a segment-numbering note ("held-out UBFC DATASET_2 validation and promoting harmonicFilterConfidenceGate.m", Task1 lines 40–48); the script's only UBFC ground-truth path is `…'UBFC-rPPG', 'DATASET_1', id, 'gtdump.xmp'` (line 530). |
| `Segment7_Task_K_Template_Collapse_Diagnostic.md` | **NO** | "UBFC DATASET_2 \| 42 (not extracted — ~70GB uncompressed, didn't fit in available disk space at analysis time)" (line 20); "DATASET_2 was scoped out for a disk-space reason" (line 24). |

Additional (found while auditing, disclosed rather than hidden): `Segment14_Task1` (Branch 2 gate use, excluded from the question by the brief) does call `fftHeartRate` on D2's CHROM-family pulse (`run_segment14_task1_ubfc_d2_held_out_validation.m` lines 150, 280) — to anchor the harmonic-comb f0 and to set the effective sampling rate for notch detection — and computes a per-subject ratio of signal-spectral-peak to ground-truth-PPG-spectral-peak (the harmonic-confusion test). It scored no CHROM/POS HR error against ground-truth HR and selected no read-out parameter. **Conclusion: D2 is held out from the read-out selection and from HR-accuracy scoring; it is NOT "never touched" (Segment 14), hence SECONDARY.**

## 2. Subject-overlap check: UBFC-D2 vs the 5-subject UBFC pool (DATASET_1)

Listed from disk (`data/raw/UBFC-rPPG/`), not assumed:

* DATASET_1 (5): `5-gt, 6-gt, 7-gt, 12-gt, after-exercise`.
* DATASET_2 (42): subject1, 3, 4, 5, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 20, 22, 23, 24, 25, 26, 27, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49.
* Name-level diff: the tokens **5 and 12 appear in both** sets (6, 7, `after-exercise` do not appear in D2). The two datasets use independent numbering schemes, so a name collision is not evidence of the same person; checked on content:

| clip | D1 | D2 |
|---|---|---|
| "5" | 2409 frames, 84.0 s, file 2,220,276,144 B, mean GT HR 77.32 bpm | 1550 frames, 52.3 s, file 1,428,595,464 B, mean GT HR 98.28 bpm |
| "12" | 2388 frames, 83.3 s, file 2,200,922,208 B, mean GT HR 94.57 bpm | 1989 frames, 68.5 s, file 1,833,191,912 B, mean GT HR 65.97 bpm |

Different length, size and heart rate ⇒ different recordings (a same-person-different-session identity cannot be excluded from this evidence alone; D1/D2 are separate UBFC releases). **Result: zero shared recordings; D1 subject IDs are not reused as D2 recordings.** Segment 24 uses no D1 clip anyway (D1 is inside MAIN_112).

## 3. Sets (labels are binding)

| Label | Set | Rule (fixed by file listings, not by results) |
|---|---|---|
| **PRIMARY — held out by video/scenario (not by subject)** | VIPL-HR-V1 source1 (Logitech C310 webcam — same device as MAIN_112's v1/source1), scenarios **v7 (after exercise; cached)**, **v4 (bright light; NEW decode)**, **v6 (stable, 1.5 m; NEW decode)**. Every source1 video present for these scenarios. | Never in MAIN_112 (v1 only) and never in the v2 motion pool. v4/v6 were never processed by any segment before this one; v7 was processed (Segment 6 Task K, production HR only) but never read out with these read-outs. |
| **EXPLORATORY — phone (descriptive only, cannot drive the verdict)** | source2 (HUAWEI P9 phone) v7 (15), v8 (106), v9 (105), and v1/source2 for the 95 subjects whose MAIN_112 row is source1. | Phone containers have known fps mislabelling (Segment 8; only 12 v1/source2 clips were ever corrected), cached `fs` used as-is; adds noise, not evidence. Reported, not tested. |
| **SECONDARY — second-look, NOT held-out (prior use: Segment 14, Branch 2 gate)** | UBFC-D2, all 42 subjects with cached traces (`data/processed/UBFC_D2_subject*_rgb_traces.mat`, forehead box, from Segment 14) and finite ground-truth HR. Also reported split by Segment 14's 33 valid / 9 excluded subjects (those 9 were excluded for a timestamp problem in the waveform ground truth, which HR-only scoring does not need). | Descriptive only. **No test, no verdict.** |

Ground truth per clip = the same scalar used everywhere in this project: VIPL — mean of `gt_HR.csv` after removing fault code 255; UBFC-D2 — mean of `ground_truth.txt` line 2 after removing non-finite/≤0/≥255 samples. Pulse signal = the production Branch-1 chain (`s23_chain`: wavelet → detrend → bandpassClean → CHROM/POS → bandpassClean), unmodified — identical to Segment 23. Cached RGB traces are reused; only v4/v6 needed decode.

Expected N (verified by file listing): v7/source1 = 91, v4/source1 = 96, v6/source1 = 94 (**PRIMARY 281 videos, ≤107 distinct people**); phone 15+106+105+95 = 321; D2 = 42. Final N after any extraction/processing failures is reported in REPORT.md (failures listed, never silently dropped).

## 4. The three conditions — fixed, run identically on BOTH combiners (CHROM, POS) and ALL sets

* **(a) BASELINE** — production `matlab/src/heartrate/fftHeartRate.m`, whole-clip FFT, peak in **0.7–4.0 Hz (42–240 bpm)** (`lowBandHz = 0.7; highBandHz = 4.0;`, read from the function, lines 33–34).
* **(b) CANDIDATE AS TESTED IN SEGMENT 23**, byte-identical copies (SHA-256 verified against the originals) of `segment23_fairness_audit/task4_lgi_state_space_tracker/src/{lgiPaperReadout,lgiStateSpaceTracker}.m` (Segment 23's Task 5 script calls exactly these two files as E5/E6; its own `src/` is empty):
  * **(bW) windowed peak**: Butterworth-2 0.5–2.0 Hz, 256-sample Hann windows, 90 % overlap, 4× zero-pad, per-window max peak, clip HR = median. Band **0.5–2.0 Hz = 30–120 bpm**.
  * **(bT) frequency-state tracker**: exactly its committed defaults (grid 0.7–3.0 Hz, Δ0.025, σΠ 0.05, r 0.3, qs 0.005, mix hop 0.5 s, burn-in 3 s). *Its band is 0.7–3.0 Hz = 42–180 bpm — wider than the brief's "≤120 bpm" (that figure belongs to the windowed read-out only); recorded as found.*
* **(c) CANDIDATE, BAND-MATCHED** — same code, only the band changed to (a)'s: **(cW)** `lgiPaperReadout(p, fs, [0.7 4.0])` (this also matches (a)'s lower edge 0.5→0.7); **(cT)** `lgiStateSpaceTracker(p, fs, struct('fHi', 4.0))` (grid 0.7–4.0 Hz). Nothing else changes.
* Not isolated (stated, out of scope): the median-over-windows aggregate inside (bW)/(cW), and a whole-clip FFT restricted to 0.5–2.0 Hz ("band alone"). Suggested as separate later tests.
* **Parity gate:** before the run, `s23_chain` + `fftHeartRate` must reproduce Segment 8's CHROM/POS wavelet numbers on 5 MAIN_112 subjects to < 1e-3 bpm, else the run aborts.

## 5. Metrics and the pre-declared statistical test

* Per (set, stratum, combiner, condition): **MAE, RMSE, Pearson r** of clip HR vs ground-truth HR (NaN-safe, n reported), plus count of severe errors (>10 bpm). Full per-stratum tables, never pooled-only.
* **Verdict test — PRIMARY only:** unit = **person (VIPL subject)**. A person's error under a condition = mean absolute error over that person's PRIMARY videos (v7/v4/v6 source1 that exist), so one person contributes one paired difference even though up to three of their clips are used (clips from one person are not independent). Test = **paired two-sided Wilcoxon signed-rank** (MATLAB `signrank`, exact zero differences dropped) on the per-person |error| differences, **(a) vs (b)** and **(a) vs (c)**, for each mechanism (W, T) × combiner (CHROM, POS) = **8 tests**, **Holm-adjusted, family α = 0.05**. Per-stratum Wilcoxon p-values are reported as descriptive extras only.
* **"Clearly beats (a)"** = person-level mean-|error| gain ≥ 0.5 bpm **and** Holm-adjusted p < 0.05 **and** the pooled RMSE does not get worse than (a)'s.
* Exploratory phone strata and SECONDARY D2: MAE/RMSE/r + paired win/loss counts only.

## 6. Verdict rules (project vocabulary), per mechanism × combiner cell, on PRIMARY

* **(b) and (c) both clearly beat (a)** → that cell is **CANDIDATE, HELD-OUT VALIDATED** (held out by video/scenario, not by subject; still not ADOPTED — a production-integration pass is a separate decision). A mechanism is reported validated overall only if both its combiner cells are.
* **(b) clearly beats (a) but (c) does not** → the Segment 23 gain was mostly the narrower band, not the mechanism; report plainly; the band alone is a separate, simpler test (out of scope).
* **Neither clearly beats (a)** → **EVALUATED, NOT ADOPTED.**
* Any other pattern (e.g. (c) beats but (b) does not — the band *hurts* the as-tested form) is reported as found, with the cell's numbers. **If PRIMARY and SECONDARY (D2) disagree, the disagreement is reported explicitly; neither is used to overrule the other.** D2 never drives the verdict.

## 7. ONE-SHOT statement

Once Step 5 starts (`scripts/s24_run_readouts.m`), **no parameter, band, window, set membership, exclusion rule, test, or threshold changes on any dataset, for any condition, regardless of how results look.** If a result is disappointing it is reported plainly as-is, not re-run with a tweak. This file is not edited after that point (post-hoc analyses go in REPORT.md under an explicit "post-hoc, not pre-registered" heading).
