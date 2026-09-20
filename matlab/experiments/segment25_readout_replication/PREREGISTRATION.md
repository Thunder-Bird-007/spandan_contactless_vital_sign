# Segment 25 — PREREGISTRATION (written and committed BEFORE any read-out is computed on any Segment 25 set)

Question: does Segment 24's band-matched windowed read-out — the one preregistered *control* that beat production `fftHeartRate.m` on Segment 24's PRIMARY set (CHROM person-MAE 11.94→9.21, POS 11.79→8.64 bpm, Holm p 0.0019 / 3e-5) — (A) hold up on MAIN_112, (B) replicate on unseen scenarios, (C) survive a change of camera? Replication only. **No tuning.** Registered 2026-09-20.

## 1. The condition under test — exact, unmodified, whole segment

* **Candidate (c-W):** `lgiPaperReadout(pulse, fs, [0.7 4.0])` — Butterworth-2 0.7–4.0 Hz, 256-sample Hann windows, hop = round(0.1·256), 4× zero-pad (nfft 1024), per-window max FFT peak inside 0.7–4.0 Hz, clip HR = 60·median(peaks). `src/lgiPaperReadout.m` is a byte-identical copy of `segment24_readout_heldout_validation/src/lgiPaperReadout.m` (SHA-256 `d3827463…c1f824`, verified equal), which is itself byte-identical to Segment 23's. The band `[0.7 4.0]` is production `fftHeartRate.m`'s `lowBandHz`/`highBandHz`.
* **Baseline (a):** production `matlab/src/heartrate/fftHeartRate.m`, whole-clip FFT, 0.7–4.0 Hz.
* **Pulse signals:** the production Branch-1 chain (`s23_chain`: wavelet → detrend → bandpassClean → CHROM/POS → bandpassClean), unmodified, from cached (or newly extracted, same code path as Segment 24) forehead-box RGB traces. Combiners: CHROM and POS.
* Only this one candidate is run (no tracker, no as-tested narrow band): the other Segment 24 conditions were already judged EVALUATED, NOT ADOPTED and are not re-litigated.
* **Parity gate:** before the run, the chain + `fftHeartRate` must reproduce Segment 8's wavelet CHROM/POS numbers on 5 MAIN_112 subjects to <1e-3 bpm, else abort.

## 2. The three tests (all: candidate vs baseline (a))

| Test | Set | Unit | Notes |
|---|---|---|---|
| **A — regression check** | **MAIN_112** = 5 UBFC-D1 + 107 VIPL v1 (source1, or source2 for the 12 fallback subjects) — the pool the project was tuned/validated on | subject (112) | The candidate (c-W) has never been run here (Segment 23 ran the *narrow-band* form). |
| **B — scenario shift** | VIPL **v3 (talking) + v5 (dark), source1 Logitech C310 webcam** — expected 95 + 93 = 188 clips | person (mean over the person's v3/v5 clips) | Same device as MAIN_112's v1/source1; new scenarios. |
| **C — device shift** | VIPL **v1, source3 (RealSense F200 RGB)** — expected 107 clips | person (1 clip each) | Unseen video AND unseen camera; `time.txt` timestamps used by the production loader for fs. |

All three are "held out by video, not by subject": VIPL people repeat across sources/scenarios by design, and all 107 are in MAIN_112. No new-people set exists on disk. Excluded, as diagnosed: the 321 phone clips (subject overlap, prior Branch 1 HR scoring, condition (c) already observed on them in Segment 24).

### Video-file audit (specific FILES, not subjects — done before this registration)

* **v3/source1 (95 clips) and v1/source3 (107 clips): never processed.** No RGB/HR cache of any kind exists in `data/processed`; no `results/metrics` row scores them for HR.
* **v5/source1 (93 clips): 20 have Segment 6 Task N region caches** (`VIPL_p*_v5_source1_{forehead,cheek,glabella,malar}_rgb_traces.mat`). Task N scored *production* CHROM/POS `fftHeartRate` HR error per region on those 20 (`segment6_task_n_region_hr_summary.csv`, region-switching study; doc line 150: "`fftHeartRate.m` — completely unmodified"). It compared regions, not read-outs, and selected no read-out parameter. **Disclosed, included in B** (per the brief); a pre-declared sensitivity row reports B with those 20 v5 clips removed (each person's mean over their remaining v3/v5 clips), descriptive only.
* **v1/source3:** the only prior touch is timing — the Segment 8 source2 fps investigation read `time.txt` of 12 source3 clips (p84, p97, … ) as a frame-timing reference (`segment8_source2_fps_investigation.csv`); no video decode, no HR. Disclosed; included.
* Segment 24 did not process any of these three groups. (Verified: no `VIPL_p*_v3_*`, `_v5_source1_rgb_traces`, or `_v1_source3_*` cache and no Segment 24 manifest row.)
* All Segment 25 clips are decoded fresh by the same unmodified `loadVIPLVideo` + `extractROISignals` path as `s24_extract_new_vipl.m` (default forehead box); no read-out is computed during extraction. The v5 region caches are not reused.

## 3. Ground truth, metrics, exclusions

* Ground truth per clip: VIPL — mean of `gt_HR.csv` after removing fault code 255 (same as every prior VIPL run); UBFC/MAIN_112 — the stored `HR_groundtruth` in `segment8_task4_wavelet_ablation.csv` (identical to Segment 23's).
* Per set and per combiner, per stratum where applicable (MAIN_112: UBFC 5 / VIPL 107 / MAIN_112; B: v3 / v5 / all; C): **MAE, RMSE, Pearson r**, n, severe-error count (>10 bpm). Never pooled-only.
* Extraction/processing failures are listed and excluded, never replaced. If >10 % of a set fails, that set is reported as compromised and its verdict is "inconclusive".

## 4. Statistical test — declared before any result

**Six paired tests = 3 sets × 2 combiners.** Paired two-sided Wilcoxon signed-rank (`signrank`, exact-zero differences dropped) on per-unit |error| differences (candidate − baseline) using the units in §2. **One Holm correction across all six jointly**, family α = 0.05 (not per set). Per-stratum p-values (v3, v5, UBFC, VIPL) and the "B without the 20 Task-N v5 people's v5 clips" sensitivity are descriptive only.

Definitions (fixed now):
* **Replicates** (a test): person/subject-level MAE gain ≥ 0.5 bpm **and** Holm p < 0.05 **and** pooled RMSE(candidate) ≤ RMSE(baseline).
* **Holds / no regression** (test A, per combiner): MAE(candidate) ≤ MAE(baseline) **and not** (Holm p < 0.05 with the candidate worse).
* A combiner is judged on its own; **promotion requires both combiners** to satisfy the rule for that test. A one-combiner result is reported as partial and does not promote.

## 5. Verdict rules (project vocabulary; the brief's rules, restated as binding)

* Holds on A **and** replicates on B → **CANDIDATE, VALIDATED (scenario-generalizing)** — not ADOPTED; production integration (a full pipeline swap-in test) is a separate decision.
* …and also replicates on C → state that this is the strongest validation this project has produced for any challenger, **with the precise scope: the combiner is still production CHROM/POS; only the read-out stage is new.**
* **Regresses on A** (fails "holds") even if it wins elsewhere → flagged explicitly, **not promoted**, reason to be understood first.
* **Fails on B** → Segment 24's result is reported as a likely single-set false positive: **EVALUATED, NOT ADOPTED.** C is then reported for completeness and does not rescue B.
* Any other pattern (e.g., B replicates but A partial) is reported as found with the numbers; no promotion.

## 6. One-shot rule

Once `scripts/s25_run_readouts.m` starts, **no parameter, band, window, set membership, exclusion rule, test, threshold or definition changes, on any set, regardless of outcome.** Disappointing results are reported as-is, not re-run. This file is not edited after the run starts; post-hoc analyses go in REPORT.md under an explicit "post-hoc, not pre-registered" heading.
