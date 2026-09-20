# Fairness Audit and Read-Out Investigation — Segments 23–26 (Consolidated Summary)

*Prepared 2026-09-20. Consolidates `segment23_fairness_audit/MASTER_REPORT.md`, `segment24_readout_heldout_validation/REPORT.md`, `segment25_readout_replication/REPORT.md`, and `segment26_readout_mechanism/REPORT.md`. Written to stand on its own as a record of a four-segment investigation, so an instructor does not need to read all four source reports.*

## 1. The original question

By Segment 22, CHROM and POS (the project's production pulse-extraction combiners) had beaten every alternative method tried against them — 2SR, LGI, cPACE, CIELab a*, YCbCr Cb/Cr, RAKF, GREEN — across eight prior segments. That record raised an obvious methodological worry: was CHROM/POS's win **real robustness**, or an **artefact of an unfair test** — every challenger implemented in a simplified or partial form, while CHROM/POS carried eight segments of tuning (wavelet smoothing, a whole-clip FFT read-out, etc.)? Segment 23 was designed specifically to answer this.

## 2. Segment 23's answer: mostly real, narrower than it looks

Segment 23 rebuilt every challenger in its **native or paper-specified form** (not the earlier simplified version), de-tuned CHROM/POS to test the reverse direction, and cross-checked every combiner against every read-out to rule out "the read-out stage explains the loss."

**Four corrections to the task brief, found by reading the primary papers** (recorded here so they are not rediscovered):

| # | Source paper | Brief assumed | Paper actually says |
|---|---|---|---|
| 1 | Yang et al. 2016 (CIELab a*) | 120×80 px processing cells | Cells are 20×20 px; 120×80 px is the *selected ROI*, not the cell size |
| 2 | Kaur et al. (cPACE) | A sliding-window q̂ | The paper does not specify a windowed q̂ at all — q̂ is a static per-ROI mean direction; the windowed form tested was a fairness hypothesis, not the native method |
| 3 | Pilz et al. | A state-space HR tracker as the benchmark read-out | The paper's own benchmark read-out is a 256-sample/90%-overlap FFT peak-pick; the state-space tracker is a separate modelling framework with no numeric parameters given |
| 4 | Debnath & Kim (RAKF) | A tunable β exponent | No numeric β is given anywhere in the paper — only R0 = 25, Q = 2×10⁻⁴ — and the paper's Eq. 14 and Eq. 15–17 have never been implemented in this project's port |

Two further, non-brief findings worth recording: the CHROM/POS primary text (de Haan & Jeanne) was unreadable from this environment, so "native CHROM" for the de-tuning test (Task 6) relied on the McDuff `iphys` reference implementation as a secondary source; and Segment 22's 2SR test used a forehead-only ROI that was unfairly small for 2SR specifically — widening it to the whole face closed part of the motion-pool gap (21.3 → 15.4 bpm MAE) without closing all of it.

**Results.** Every challenger re-tested in native form still lost, and three of five native forms were *worse* than the earlier simplified test (native a*: 16.5 vs 9.5 bpm; native RAKF: 11.95 vs 10.73 bpm; masked-forehead 2SR: 10.1 vs 9.5 bpm). The 19-combiner × 6-read-out matrix (Task 5) showed no challenger beating CHROM/POS under any shared read-out, ruling out "the read-out stage was rigged" as an explanation. De-tuning CHROM/POS (Task 6) — stripping the wavelet stage, or moving to the papers' fully native windowed forms — cost 1.3–1.5 bpm and 3–4 bpm of pooled MAE respectively, but **no de-tuned CHROM/POS variant was statistically distinguishable from production per subject** (all p ≥ 0.08).

**The precise bottom line — how strong is the incumbents' lead, honestly:**

| Pool | Closest challengers vs CHROM | Closest challengers vs POS | Clearly worse |
|---|---|---|---|
| MAIN_112 (112 subjects, general condition) | p = 0.07–0.36 (a*, 2SR, LGI, masked 2SR — **not significant**) | p ≈ 0.02–0.08 for a*/2SR/LGI | cPACE Full and native a* (p ≤ 0.04) |
| VIPL v2 motion pool (20 subjects) | CHROM beats 2SR p = 0.010, LGI p = 0.016, cPACE Full bw 0.15 p = 0.018 (**significant**) | — | — |

No formal multiple-comparisons correction was applied across Segment 23's roughly 114 tested combinations (Tasks 5 and 6 explicitly instruct reading "patterns, not single p-values"). The motion-pool p-values above should therefore be read as **suggestive, not airtight** — real but not correction-proof evidence.

**Conclusion, stated as the project states it**: CHROM/POS's edge is real but is **concentrated in degraded/motion conditions**, not a uniform advantage across general resting-condition data. On ordinary resting data the best challengers (a*, 2SR, LGI) trail on pooled MAE but are not statistically separable from CHROM per subject.

## 3. The Segment 24–26 side investigation: a read-out candidate

Segment 23's Task 5 turned up an unrelated, unexpected finding: replacing the whole-clip FFT HR read-out with a **windowed read-out** (256-sample/90%-overlap, median over windows) improved even the *incumbents*' MAIN_112 MAE by 1.1–1.5 bpm (CHROM 7.83 → 6.38/6.54 bpm; POS 7.22 → 6.70/6.29 bpm), flagged as an unvalidated CANDIDATE. Three further segments traced this candidate's validation arc.

| Segment | Test | Result | Verdict |
|---|---|---|---|
| 24 | Held-out (unused VIPL videos, by scenario not subject): as-tested 0.5–2 Hz windowed read-out | CHROM 11.94→11.47 (p_Holm=1.0); POS 11.79→11.54 (p_Holm=1.0) — no gain | **EVALUATED, NOT ADOPTED** as tested |
| 24 | Same test, frequency-state tracker | Gains of −0.06 to +0.72 bpm, all p_Holm=1.0 | **EVALUATED, NOT ADOPTED** |
| 24 | Band-matched control: same windowed read-out, production's 0.7–4 Hz band instead of 0.5–2 Hz | CHROM 11.94→9.21 (p_Holm=0.0019); POS 11.79→8.64 (p_Holm=3e-5) — clear win | **CANDIDATE, NOT VALIDATED** — single observation, a pre-registered control never run on MAIN_112 or a fresh set |
| 25 | Replication — MAIN_112 (regression check) | CHROM 7.83→6.73, POS 7.22→6.45; not significant alone (p_Holm 0.997/0.522) | Holds, no regression |
| 25 | Replication — fresh scenarios v3 (talking) + v5 (dark) | CHROM 9.43→7.12 (p_Holm=0.020); POS 10.27→7.49 (p_Holm=0.00073) | **Replicates** |
| 25 | Device-shift check — v1 source3 (RealSense) | CHROM 6.90→6.79 (n.s.); POS 7.20→6.76 (n.s.) | **Does not replicate** |
| 26 | Mechanism test 1: median vs mean aggregation (14 tests) | Mean recovers 101% (CHROM) / 86% (POS) of the median's gain on degraded strata; no difference significant (all Holm p ≥ 0.078) | **Not supported** |
| 26 | Mechanism test 2: gain vs. cached quality proxies (fps, dropped-frame fraction, ROI green; 730 clips) | Max \|ρ\| = 0.094, no proxy reaches Holm p < 0.05 | **Not supported** |

Segment 25 initially promoted the candidate to "CANDIDATE, VALIDATED (scenario-generalizing)." That label was corrected in Segment 26 Step 0 after a closer look: the v3 (talking) scenario showed no effect for CHROM (p = 0.89, uncorrected) and only a marginal, correction-failing effect for POS (p = 0.030), while the v5 (dark, low-fps) scenario carried essentially all of the replication (CHROM p = 0.0001, POS p = 0.0016, both uncorrected but large). The corrected label — **degraded-signal conditions only**, not general scenario-generalizing — is the one that stands.

Segment 26 then ran two dedicated mechanism-isolation tests to explain *why* the windowed read-out helps on degraded clips: neither the median-vs-mean aggregation hypothesis nor any of three quality proxies (frame rate, dropped-frame fraction, ROI green level) explained the pattern. Frame rate in particular does not order the gains at all — v3 and v6 share the same fps with different gains, while v4 and v5 sit at opposite ends of the fps range with similarly large gains. **The mechanism remains genuinely unresolved.**

## 4. The decision to stop

After two dedicated, well-designed mechanism-hunting segments (26's median-vs-mean test and its three-proxy quality test) came back empty, the investigation was **deliberately stopped** rather than continued indefinitely. A proposed Segment 27 — a third mechanism-isolation attempt (windowing vs. band-limit separation, window-length/hop sensitivity, a genuine signal-quality proxy such as spectral SNR) — was designed but **never run**, on the judgment that further mechanism-hunting had hit diminishing returns relative to its cost: no production decision was actually pending on knowing the mechanism.

**Final resting verdict, stated exactly:**

> CANDIDATE, VALIDATED — degraded-signal conditions only (dark/low-fps scenarios evidenced; motion conditions plausible by extension from Segment 23 but not directly re-tested by the same read-out); not shown in normal-lighting conditions or across camera devices; mechanism tested twice and not found; not adopted into production; no further mechanism investigation planned without new evidence prompting one.

## 5. What is still true, unconditionally

Across all four segments, **production has not changed**: CHROM/POS remain the production combiners, and the whole-clip FFT remains the production HR read-out. Nothing from this investigation was promoted into the pipeline. In every one of Segments 23–26, all protected production files were verified byte-identical (SHA-256) before and after the segment's work — 18/18 in each case.

## 6. What this demonstrates methodologically

This four-segment arc is as much a demonstration of process as of a numerical result, and that is worth noting in a course context. The project ran a genuine fairness audit against its own long-standing conclusion rather than assuming it — and that audit found and fixed four real errors in its own prior task brief (misread paper details in Yang, Kaur, Pilz, and Debnath & Kim), not just errors in outcome. When a side-finding emerged from that audit, later segments used pre-registration and Holm-corrected, multiple-comparisons-aware statistics to test it rather than reporting the first favorable number, and one of those segments caught and corrected its own premature "scenario-generalizing" claim down to the narrower, better-supported "degraded-signal conditions only" claim. Finally, after two honest attempts to explain the mechanism came back negative, the investigation stopped rather than let a side-question run indefinitely with no production decision riding on it. That combination — rigor in testing a claim, and honesty about when to stop — is the substance of this investigation, not the bpm numbers alone.
