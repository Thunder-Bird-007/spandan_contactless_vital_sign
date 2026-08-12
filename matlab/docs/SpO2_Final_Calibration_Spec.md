# SpO2 Final Calibration Spec

**NOT deployed to Android — documentation only, standing decision unchanged.**
SpO2 is not approved for Android display; no validated calibration exists
that would justify shipping it in the app. This document records the
coefficients a deployed formula *would* use, for reporting purposes only.

## Method

Same `spo2/calibrateSpO2.m` linear method (`SpO2 = A - B*R`) and the same
per-dataset-centering idea already used and validated in Task E
(`validation/centerRPerDataset.m`), but fit once on the **entire 112-subject
pool at once** (UBFC N=5 + VIPL N=107, v1-only), not held out via LOSO.
This is a "what would the deployed numbers be" snapshot, not a new or
re-validated model — the accuracy numbers that matter for the report are
the LOSO ones (see `SpO2_Final_Report_Section.md`), not this fit.

Neither `calibrateSpO2.m`, `centerRPerDataset.m`, `runLOSO.m`, nor
`runLOSOStratified.m` was modified to produce this. Produced by
`matlab/scripts/run_segment5_final_spo2_report.m`.

## Per-dataset R centering offsets (full 112-subject pool, no holdout)

| Dataset | N | Mean R (subtracted before fitting) |
|---|---|---|
| UBFC | 5 | 0.759402 |
| VIPL | 107 | 1.032539533 |

The formula below is meaningless without these offsets — `R` must be
centered per-dataset before applying `A`/`B`.

## Production coefficients

Fit on all 112 subjects' per-dataset-centered R against true SpO2:

```
A = 96.47630625
B = -0.4159452784

SpO2_predicted = A - B * (R_raw - datasetMeanR[dataset])
```

where `datasetMeanR['UBFC'] = 0.759402` and
`datasetMeanR['VIPL'] = 1.032539533` per the table above. For a new
dataset/device not in this table, this formula has no defined offset and
should not be applied.

## Caveat

This is a full-pool fit, not a held-out (LOSO) evaluation — it describes
what a deployed formula's coefficients would be, not how accurate that
formula is on unseen subjects. For the actual validated accuracy of this
calibration approach, see the Task H3 stratified LOSO numbers in
`SpO2_Final_Report_Section.md`: MAE 1.908 (VIPL, N=107), which loses to
the trivial "guess the training mean" baseline within the observed R/SpO2
range documented there.
