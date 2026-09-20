
"Best-known" = the configuration listed; for challengers the *as-tested and native* forms are on adjacent rows so the retest effect is visible. The last four rows (gating/continuity, Segment 6 Tasks P/Q) were **not** re-run — they exist only for VIPL-107 on the pre-wavelet chain; shown for completeness, not re-tested.

## Which task supports which conclusion

| conclusion | supported by | strength |
|---|---|---|
| Challengers do not lose because they were tested simplified: completed/native forms still lose | T1, T2, T3, T4, T7 (each with a regression check against the earlier result — all exact) | strong on MAIN_112 pooled MAE; weaker per subject vs CHROM (p 0.07–0.36) except cPACE Full / native a* |
| Losses are not read-out artefacts | T5 (19 × 6, per pool), T4 | strong: gaps keep sign under E1/E2/E5/E6 |
| De-tuning CHROM/POS moves pooled MAE by 1.3–4 bpm but not per subject | T6 | moderate; some T6 rungs were added after seeing the first result (exploratory) |
| RAKF's Eq. 12 bug was not why it lost | T7 | strong: exponent form is slightly worse (p < 0.0001 vs the division form, MAIN_112) |
| Read-out stage is a bigger lever than the combiner | T4, T5 (T7 corroborates: RAKF worst) | moderate; confounded by the 0.5–2 Hz band prior; no held-out check |
| Forehead-box "non-skin contamination" premise was mostly false here | T3 (median 97 % skin; masking does not help 2SR) | moderate (one colour rule, no visual audit) |

## Corrections to the Segment 23 brief found by reading the primary sources (recorded so they are not rediscovered)

1. **Yang et al. 2016:** cells are 20×20 px; 120×80 px is the *selected ROI* (T2).
2. **Kaur et al.:** the paper does **not** specify a sliding-window q̂ — q̂ is a static per-ROI mean-direction; windowed q̂ was tested as a fairness hypothesis, not a native form (T1).
3. **Pilz et al.:** the paper's own benchmark read-out is a 256-sample / 90 %-overlap FFT peak-pick, **not** the state-space tracker, which is the modelling framework with no numeric parameters given (T4).
4. **Debnath & Kim:** no numeric β is given anywhere; only R0 = 25 and Q = 2×10⁻⁴; the paper's RAKF also includes Eq. 14 and Eq. 15–17, which this project's port has never had (T7).
5. **de Haan & Jeanne (CHROM):** primary text unreadable from this environment (BLOCKED); "native CHROM" uses the McDuff iphys reference values as a secondary source (T6).
6. **Segment 22's 2SR used a forehead-only region**, unfairly small for 2SR on the motion pool; widening to the face closes part of the gap (T3) — a genuine fairness gap in the earlier record, still not enough to beat CHROM/POS.

## Honest limitations of this segment

* Pools: UBFC N = 5 and VIPL v2 N = 20 cannot carry claims alone; MAIN_112 is 95 % VIPL v1. Held-out data (UBFC-D2) was **not** used anywhere in this segment.
* Multiple comparisons: Tasks 5/6 report dozens of paired tests; read patterns, not single p-values.
* Not done: cumulative-loss reading of KLT pruning and any threshold sensitivity (T2 — pruning was inert under the per-frame reading); ROI overlays were not inspected (T2's explanation of the ROI loss is a hypothesis); one skin-mask rule, no HSV/learned variant (T3); tracker constants untuned by design (T4); the paper's full per-frame RAKF (T7); as-tested a* and 2SR were not re-run with production's wavelet stage except T2 A3w and T3 waveletOut (neither beat production); challengers were not re-tuned per method (that would be the fishing this segment forbids).
* T6's diagnostic rungs (L4b–L5) were added after L4's poor result; their apparent advantage is exploratory.
* No production file was modified: PROTECTED_VERIFICATION_RESULT (details: `common/protected_files_verification.txt`).

## Recommended follow-ups (not started)

1. Held-out validation (UBFC-D2, 33 valid subjects) of the windowed/tracked read-out for CHROM/POS — the only new candidate this segment produced.
2. If challengers keep being tested, use the motion pool with a larger N; MAIN_112 cannot separate the top group.
