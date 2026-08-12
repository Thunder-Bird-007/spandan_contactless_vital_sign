# Segment 6 Task K Addendum: Does the CHROM-Agree/POS-Disagree Asymmetry Survive v7?

Follow-up to Task K. On the pooled v1+v7 dataset (N=218), plain POS (MAE
11.36) now beats both switching variants (old-threshold 11.52, refit-
threshold 11.65) -- a reversal of Task J's v1-only finding that switching
beat both individual methods. This addendum checks WHY, by re-slicing
Task K's already-computed data: does the asymmetry Task I originally found
(CHROM wins where CHROM and POS agree, POS wins where they disagree)
still hold once v7 is in the pool?

This is a read-only re-slice of existing numbers: no new video processing,
no changes to computeAgreementConfidence.m, computeSwitchingEstimate.m, or
Task K's own files. Source data: segment4_hr_summary.csv,
segment4_hr_summary_vipl.csv, segment4_hr_summary_v7.csv, and
segment6_hr_agreement_flags_v1_v7.csv, all already produced by
run_segment6_task_k_pooled_v1_v7.m.

## Agree/disagree breakdown, refit threshold (59.54%)

| Group | N | CHROM MAE | POS MAE | Winner |
|---|---|---|---|---|
| agree (< 59.54%) | 214 | 11.5105 | 11.2232 | POS |
| disagree (>= 59.54%) | 4 | 53.8373 | 18.5079 | POS |

## Agree/disagree breakdown, old v1-only threshold (29.27%)

| Group | N | CHROM MAE | POS MAE | Winner |
|---|---|---|---|---|
| agree (< 29.27%) | 199 | 10.2941 | 10.1107 | POS |
| disagree (>= 29.27%) | 19 | 33.1618 | 24.4089 | POS |

## Comparison against Task I's original v1-only finding

Task I (v1-only, N=112, 29.27% threshold, Segment6_Refinement_Notes.md
Section I.4-5): agree subset (N=104) CHROM MAE=6.5407 vs POS MAE=6.9863 --
CHROM wins. Disagree subset (N=8) is what drags CHROM's full-pool MAE below
POS's at the full N=112 level -- POS wins the disagree tail. This asymmetry
(CHROM-agree, POS-disagree) is the entire mechanical reason Task J's
switching estimator beat both individual methods.

On the v1+v7 pool with the refit (59.54%) threshold, the pattern **does not hold** as originally found: the agree-subset winner is POS, the disagree-subset winner is POS.

With the old (29.27%) threshold, the pattern **does not hold** as originally found: the agree-subset winner is POS, the disagree-subset winner is POS.

## Verdict

The CHROM-agree/POS-disagree asymmetry that made switching win on the v1-only pool has flipped on the v1+v7 pool under both threshold choices: POS now wins the agree subset too (refit: CHROM MAE=11.5105 vs POS MAE=11.2232; old: CHROM MAE=10.2941 vs POS MAE=10.1107). This is the direct explanation for switching's aggregate loss in Task K: the switching rule keeps CHROM in the majority-agree case precisely where CHROM is now the worse method, so it is actively steering toward the worse estimate most of the time. The rule itself has not changed -- the asymmetry it was built to exploit is what disappeared once v7's higher-HR, higher-motion subjects entered the pool.

