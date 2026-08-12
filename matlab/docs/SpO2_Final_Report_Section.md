# SpO2 Final Report Section

## Standing decision

SpO2 is **not approved for Android display**. No validated calibration
exists that would justify shipping it in the app. What follows is the
MATLAB-side finalized reporting for this pipeline stage -- a documentation
and evaluation deliverable, not an app feature.

## Method reported here

The numbers below come from the Task H3 **stratified (within-dataset-only)
LOSO** evaluation (`validation/runLOSOStratified.m`), the already-identified
"trustworthy" SpO2 result per `Segment6_Refinement_Notes.md` Task H3 -- each
held-out subject is predicted using a calibration fit only on other subjects
from the *same* dataset, avoiding the pool-imbalance artifact that made the
earlier pooled-LOSO UBFC number (Pearson r = +0.054) misleadingly positive.
Full v1-only pool: UBFC N=5 + VIPL N=107 = 112 subjects, `p25` included (its
constant, physiologically implausible 44% ground-truth reading is a
documented sensor-fault outlier, not excluded from this pool -- see Task H2).

No new modeling was done to produce this section. `calibrateSpO2.m`,
`centerRPerDataset.m`, `runLOSO.m`, and `runLOSOStratified.m` are all
unmodified; this section only re-reports and reformats their already-computed
outputs via a new script, `matlab/scripts/run_segment5_final_spo2_report.m`.

## Observed R / SpO2 range and validity caveat

Two ranges are reported below, and they answer two different questions.
The full-112 range (matching the with-p25/without-p25 accuracy comparison
reported elsewhere in this document) describes the training pool as
recorded, outlier included. The p25-excluded range is the one that
actually answers "what real physiological data has this model seen" --
`p25`'s ground-truth SpO2 is a constant, implausible 44% reading, already
established in Task H2 as a sensor/contact fault, not a real
physiological observation, so it should not set the floor of a validity
caveat even though it correctly stays in the accuracy pool elsewhere.

**Full 112-subject pool (with `p25`, as already computed):**

| Scope | N | R range | SpO2 range |
|---|---|---|---|
| Overall | 112 | 0.48687 - 4.2054 | 44% - 99% |
| UBFC | 5 | 0.52026 - 0.86383 | 95.993% - 98.8911% |
| VIPL | 107 | 0.48687 - 4.2054 | 44% - 99% |

**111-subject pool, `p25` excluded (the actual validity bound used below):**

| Scope | N | R range | SpO2 range |
|---|---|---|---|
| Overall | 111 | 0.48687 - 4.2054 | 87.28% - 99% |

(R range is unchanged by excluding `p25` -- its own R value, 0.89733, was
never the pool's min or max. The SpO2 floor moves from 44% to 87.28%, the
true minimum once the sensor-fault reading is set aside; the true minimum
SpO2 subject is now `VIPL_p66_v1_source1` at 87.28%.)

**This calibration is validated only for R values between 0.48687 and
4.2054 (observed SpO2 range 87.28% to 99%, `p25` excluded). Predictions
outside this range are extrapolation and should not be treated as
validated.**

*Footnote: `p25` (constant 44% SpO2 reading) is excluded from this range
as a known sensor fault, not a real physiological observation -- see
Task H2.*

All 112 subjects in the Action 1 table below were checked against the
full-pool range: **zero** subjects fall outside it (expected, since the
range was computed from this same pool) -- confirmed by direct
comparison, not assumed.

## Accuracy: Task H3 stratified LOSO (the trustworthy number)

| Scope | N | MAE | RMSE | Pearson r | Reliability |
|---|---|---|---|---|---|
| UBFC | 5 | 1.9683 | 2.1857 | -0.8415 | THIN -- trains on only 4 subjects/fold, directional signal only, not a reliable number |
| VIPL | 107 | 1.9078 | 5.4303 | -0.3333 | thin-data-safe -- trains on ~106 subjects/fold |

**VIPL's N=107 stratified number (MAE 1.908, r=-0.333) is the one worth
citing as this project's SpO2 accuracy** -- it is not a pool-imbalance
artifact the way the old pooled UBFC number was, and has a large enough N
(training on ~106 subjects per fold) to be a real, if still weak, read on
within-dataset generalization. UBFC's N=5 stratified number (MAE 1.968,
r=-0.841) should only ever be reported as directional, given it trains on
just 4 subjects per fold.

**Stated plainly, not softened: this calibration loses to the trivial
"guess the training-set mean" baseline.** Per
`Segment6_Refinement_Notes.md` (Tasks D and H), the real R-based
calibration does not beat a baseline that ignores R entirely and simply
predicts the mean SpO2 of the training fold, at every pool size checked
(N=8, N=18, N=112, with and without the `p25` outlier). At the same
N=112 pool used here (`segment6_spo2_with_p25.csv`, pooled-LOSO variant):
pooled MAE 1.8519 (real calibration) vs. 1.8373 (baseline) -- the
calibration is *worse* than simply predicting the training mean. The
baseline's Pearson r of exactly -1.0000 in every scope is a known LOSO
arithmetic artifact (an exact negative-affine function of the held-out
subject's own true value -- see Task D Section 2), not a real correlation,
and should not be read as the baseline being a *good* model -- only that
it is, on plain MAE, a better one than the current R-based calibration at
this data scale. The wrong-sign Pearson r for the real calibration
(negative, when SpO2 should fall as R rises per `calibrateSpO2.m`'s own
physiological convention) persists across raw pooling, per-dataset
centering, and this stratified check alike.

## Action 1: per-subject predictions (Task H3 stratified LOSO, N=112)

Predicted SpO2 formatted to 1 decimal place (not rounded to the nearest
integer). Full CSV: `results/metrics/segment5_final_spo2_predictions.csv`.

| Subject ID | Dataset | True SpO2 (%) | Predicted SpO2 (%) | R value | Abs error | Out of range |
|---|---|---|---|---|---|---|
| 5-gt | UBFC | 98.8911 | 96.8 | 0.83583 | 2.0630 | no |
| 6-gt | UBFC | 96.5468 | 97.9 | 0.85947 | 1.3190 | no |
| 7-gt | UBFC | 96.4386 | 98.0 | 0.86383 | 1.5184 | no |
| 12-gt | UBFC | 95.9930 | 99.8 | 0.52026 | 3.7700 | no |
| after-exercise | UBFC | 97.9614 | 96.8 | 0.71762 | 1.1708 | no |
| VIPL_p1_v1_source1 | VIPL | 96.1944 | 96.6 | 1.37750 | 0.3955 | no |
| VIPL_p2_v1_source1 | VIPL | 96.0000 | 96.4 | 0.82349 | 0.3639 | no |
| VIPL_p3_v1_source1 | VIPL | 97.5806 | 96.5 | 1.24650 | 1.0628 | no |
| VIPL_p4_v1_source1 | VIPL | 98.4286 | 96.5 | 1.24070 | 1.9232 | no |
| VIPL_p5_v1_source1 | VIPL | 97.7742 | 96.5 | 1.33090 | 1.2274 | no |
| VIPL_p6_v1_source1 | VIPL | 97.4516 | 96.5 | 1.10130 | 0.9893 | no |
| VIPL_p7_v1_source1 | VIPL | 98.3750 | 96.4 | 0.96973 | 1.9752 | no |
| VIPL_p8_v1_source1 | VIPL | 97.4839 | 96.5 | 1.09760 | 1.0234 | no |
| VIPL_p9_v1_source1 | VIPL | 97.5000 | 96.4 | 1.06370 | 1.0532 | no |
| VIPL_p10_v1_source1 | VIPL | 94.9143 | 96.5 | 1.01740 | 1.5380 | no |
| VIPL_p11_v1_source1 | VIPL | 96.2667 | 96.5 | 1.08450 | 0.2003 | no |
| VIPL_p12_v1_source1 | VIPL | 98.8333 | 96.3 | 0.86228 | 2.4854 | no |
| VIPL_p13_v1_source1 | VIPL | 97.4667 | 96.5 | 1.10350 | 1.0036 | no |
| VIPL_p14_v1_source1 | VIPL | 96.0000 | 96.4 | 0.97339 | 0.4242 | no |
| VIPL_p15_v1_source1 | VIPL | 98.4062 | 96.4 | 0.97657 | 2.0038 | no |
| VIPL_p16_v1_source1 | VIPL | 97.0938 | 96.4 | 0.99226 | 0.6724 | no |
| VIPL_p17_v1_source1 | VIPL | 97.3030 | 96.5 | 1.08550 | 0.8456 | no |
| VIPL_p18_v1_source1 | VIPL | 97.8000 | 96.5 | 1.23500 | 1.2892 | no |
| VIPL_p19_v1_source1 | VIPL | 95.7059 | 96.5 | 1.24740 | 0.8350 | no |
| VIPL_p20_v1_source1 | VIPL | 98.0000 | 96.5 | 1.18840 | 1.5092 | no |
| VIPL_p21_v1_source1 | VIPL | 96.4390 | 96.5 | 1.11110 | 0.0372 | no |
| VIPL_p22_v1_source1 | VIPL | 95.0000 | 96.5 | 1.20240 | 1.5296 | no |
| VIPL_p23_v1_source1 | VIPL | 98.1290 | 96.5 | 1.12930 | 1.6623 | no |
| VIPL_p24_v1_source1 | VIPL | 97.0000 | 96.5 | 1.20240 | 0.4927 | no |
| VIPL_p25_v1_source1 | VIPL | 44.0000 | 96.9 | 0.89733 | 52.9404 | no |
| VIPL_p26_v1_source1 | VIPL | 98.9000 | 96.4 | 0.87672 | 2.5463 | no |
| VIPL_p27_v1_source1 | VIPL | 95.6053 | 96.4 | 0.97740 | 0.8243 | no |
| VIPL_p28_v1_source1 | VIPL | 98.9688 | 96.4 | 0.99927 | 2.5623 | no |
| VIPL_p29_v1_source1 | VIPL | 98.0000 | 96.5 | 1.21670 | 1.4985 | no |
| VIPL_p30_v1_source1 | VIPL | 97.7419 | 96.4 | 1.00130 | 1.3229 | no |
| VIPL_p31_v1_source1 | VIPL | 98.2424 | 96.5 | 1.26480 | 1.7260 | no |
| VIPL_p32_v1_source1 | VIPL | 95.7222 | 96.5 | 1.12400 | 0.7664 | no |
| VIPL_p33_v1_source1 | VIPL | 95.3750 | 96.6 | 1.31650 | 1.2006 | no |
| VIPL_p34_v1_source1 | VIPL | 95.6786 | 96.4 | 0.97713 | 0.7502 | no |
| VIPL_p35_v1_source1 | VIPL | 95.4412 | 96.4 | 0.97917 | 0.9907 | no |
| VIPL_p36_v1_source1 | VIPL | 97.7500 | 96.4 | 0.86513 | 1.3888 | no |
| VIPL_p37_v1_source1 | VIPL | 98.8235 | 96.4 | 1.01360 | 2.4097 | no |
| VIPL_p38_v1_source1 | VIPL | 93.9355 | 96.4 | 0.78956 | 2.4416 | no |
| VIPL_p39_v1_source1 | VIPL | 99.0000 | 96.3 | 0.87093 | 2.6500 | no |
| VIPL_p40_v1_source1 | VIPL | 98.6774 | 96.3 | 0.76266 | 2.3746 | no |
| VIPL_p41_v1_source1 | VIPL | 96.3871 | 96.8 | 1.93440 | 0.4466 | no |
| VIPL_p42_v1_source1 | VIPL | 96.0000 | 96.4 | 0.94867 | 0.4142 | no |
| VIPL_p43_v1_source1 | VIPL | 98.9688 | 96.4 | 1.05610 | 2.5390 | no |
| VIPL_p44_v1_source1 | VIPL | 97.1562 | 96.4 | 0.84041 | 0.7989 | no |
| VIPL_p45_v1_source1 | VIPL | 95.1613 | 96.4 | 0.85635 | 1.2252 | no |
| VIPL_p46_v1_source1 | VIPL | 97.9375 | 96.4 | 0.91288 | 1.5576 | no |
| VIPL_p47_v1_source1 | VIPL | 97.5200 | 96.4 | 0.87539 | 1.1518 | no |
| VIPL_p48_v1_source1 | VIPL | 98.9688 | 96.5 | 1.12650 | 2.5115 | no |
| VIPL_p49_v1_source1 | VIPL | 98.0000 | 96.5 | 1.32850 | 1.4574 | no |
| VIPL_p50_v1_source1 | VIPL | 96.0000 | 97.4 | 2.70830 | 1.3544 | no |
| VIPL_p51_v1_source1 | VIPL | 97.8235 | 96.3 | 0.83556 | 1.4761 | no |
| VIPL_p52_v1_source1 | VIPL | 97.8611 | 96.3 | 0.77749 | 1.5403 | no |
| VIPL_p53_v1_source1 | VIPL | 97.8125 | 96.3 | 0.83765 | 1.4641 | no |
| VIPL_p54_v1_source1 | VIPL | 95.2903 | 96.5 | 1.20030 | 1.2351 | no |
| VIPL_p55_v1_source1 | VIPL | 96.2903 | 96.3 | 0.65543 | 0.0014 | no |
| VIPL_p56_v1_source1 | VIPL | 97.1515 | 96.5 | 1.13910 | 0.6711 | no |
| VIPL_p57_v1_source1 | VIPL | 97.0000 | 96.5 | 1.20920 | 0.4900 | no |
| VIPL_p58_v1_source1 | VIPL | 92.0606 | 96.5 | 1.03440 | 4.4256 | no |
| VIPL_p59_v1_source1 | VIPL | 96.8750 | 96.4 | 0.93173 | 0.4764 | no |
| VIPL_p60_v1_source1 | VIPL | 93.9655 | 96.4 | 0.96750 | 2.4760 | no |
| VIPL_p61_v1_source1 | VIPL | 97.4194 | 96.4 | 0.96376 | 1.0129 | no |
| VIPL_p62_v1_source1 | VIPL | 99.0000 | 96.4 | 0.94916 | 2.6151 | no |
| VIPL_p63_v1_source1 | VIPL | 98.1765 | 96.4 | 0.91862 | 1.7966 | no |
| VIPL_p64_v1_source1 | VIPL | 98.7895 | 96.5 | 1.14780 | 2.3224 | no |
| VIPL_p65_v1_source1 | VIPL | 98.7812 | 96.5 | 1.14690 | 2.3143 | no |
| VIPL_p66_v1_source1 | VIPL | 87.2800 | 96.6 | 1.09820 | 9.2796 | no |
| VIPL_p67_v1_source1 | VIPL | 96.3636 | 96.4 | 1.02350 | 0.0775 | no |
| VIPL_p68_v1_source1 | VIPL | 99.0000 | 96.4 | 1.10700 | 2.5505 | no |
| VIPL_p69_v1_source1 | VIPL | 97.2500 | 96.4 | 0.95583 | 0.8451 | no |
| VIPL_p70_v1_source1 | VIPL | 98.3636 | 96.4 | 0.92301 | 1.9837 | no |
| VIPL_p71_v1_source1 | VIPL | 94.5938 | 96.5 | 1.21310 | 1.9451 | no |
| VIPL_p72_v1_source1 | VIPL | 94.0256 | 96.5 | 1.02360 | 2.4377 | no |
| VIPL_p73_v1_source1 | VIPL | 98.0000 | 96.4 | 0.90247 | 1.6253 | no |
| VIPL_p74_v1_source1 | VIPL | 98.3667 | 96.4 | 0.95646 | 1.9725 | no |
| VIPL_p75_v1_source1 | VIPL | 93.6452 | 96.4 | 0.94106 | 2.7893 | no |
| VIPL_p76_v1_source1 | VIPL | 97.1935 | 96.4 | 0.97414 | 0.7805 | no |
| VIPL_p77_v1_source1 | VIPL | 98.2500 | 96.4 | 0.99099 | 1.8401 | no |
| VIPL_p78_v1_source1 | VIPL | 98.1176 | 96.4 | 1.04800 | 1.6830 | no |
| VIPL_p79_v1_source1 | VIPL | 93.7500 | 96.5 | 0.98808 | 2.7017 | no |
| VIPL_p80_v1_source1 | VIPL | 95.8125 | 96.4 | 0.97306 | 0.6134 | no |
| VIPL_p81_v1_source1 | VIPL | 97.9677 | 96.4 | 1.04240 | 1.5340 | no |
| VIPL_p82_v1_source1 | VIPL | 99.0000 | 96.3 | 0.80587 | 2.6806 | no |
| VIPL_p83_v1_source1 | VIPL | 96.1915 | 96.4 | 0.83988 | 0.1768 | no |
| VIPL_p84_v1_source2 | VIPL | 97.3226 | 96.2 | 0.50436 | 1.1205 | no |
| VIPL_p85_v1_source1 | VIPL | 97.2258 | 96.4 | 0.90588 | 0.8416 | no |
| VIPL_p86_v1_source1 | VIPL | 97.5000 | 96.4 | 0.97866 | 1.0881 | no |
| VIPL_p87_v1_source1 | VIPL | 97.0000 | 96.3 | 0.68855 | 0.7064 | no |
| VIPL_p88_v1_source1 | VIPL | 99.0000 | 96.2 | 0.51731 | 2.8342 | no |
| VIPL_p89_v1_source1 | VIPL | 96.1562 | 96.3 | 0.73409 | 0.1698 | no |
| VIPL_p90_v1_source1 | VIPL | 98.5161 | 96.3 | 0.71325 | 2.2351 | no |
| VIPL_p91_v1_source1 | VIPL | 96.9706 | 96.4 | 1.05050 | 0.5242 | no |
| VIPL_p92_v1_source1 | VIPL | 96.5882 | 96.4 | 0.93388 | 0.1858 | no |
| VIPL_p93_v1_source1 | VIPL | 96.7273 | 96.4 | 0.83782 | 0.3661 | no |
| VIPL_p94_v1_source1 | VIPL | 98.0000 | 96.3 | 0.82181 | 1.6609 | no |
| VIPL_p95_v1_source1 | VIPL | 95.6875 | 96.4 | 0.97017 | 0.7384 | no |
| VIPL_p96_v1_source1 | VIPL | 98.0000 | 97.3 | 4.20540 | 0.6740 | no |
| VIPL_p97_v1_source2 | VIPL | 97.3824 | 96.4 | 0.83123 | 1.0317 | no |
| VIPL_p98_v1_source2 | VIPL | 96.0303 | 96.4 | 0.90111 | 0.3644 | no |
| VIPL_p99_v1_source2 | VIPL | 96.5882 | 96.3 | 0.77034 | 0.2534 | no |
| VIPL_p100_v1_source2 | VIPL | 97.0811 | 96.3 | 0.74716 | 0.7631 | no |
| VIPL_p101_v1_source2 | VIPL | 96.5000 | 96.3 | 0.75079 | 0.1722 | no |
| VIPL_p102_v1_source2 | VIPL | 94.9714 | 96.4 | 0.84000 | 1.4111 | no |
| VIPL_p103_v1_source2 | VIPL | 94.0000 | 96.4 | 0.89925 | 2.4153 | no |
| VIPL_p104_v1_source2 | VIPL | 98.7647 | 96.4 | 1.08930 | 2.3198 | no |
| VIPL_p105_v1_source2 | VIPL | 96.2321 | 96.2 | 0.48687 | 0.0087 | no |
| VIPL_p106_v1_source2 | VIPL | 97.7273 | 96.3 | 0.81386 | 1.3884 | no |
| VIPL_p107_v1_source2 | VIPL | 96.9677 | 96.3 | 0.78637 | 0.6312 | no |
