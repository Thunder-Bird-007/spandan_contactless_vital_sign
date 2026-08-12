# Task N v4/v5 Brightness Verification

Task N's report ([Segment6_Task_N_Multi_Region_ROI.md](Segment6_Task_N_Multi_Region_ROI.md),
Section 2) claimed, sourced from `VIPL-HR-V1/ReadMe.pdf` text, that **v4 is
the dark scenario and v5 is the bright scenario**. This directly
contradicts the published VIPL-HR paper's own Table 3 (Niu et al.), which
lists Situation 4 = Bright and Situation 5 = Dark — the opposite mapping.
Both a local PDF and a published paper are text sources that could each be
right or stale relative to the actually-distributed data, so this could
not be settled by reading a third document. It is settled here with the
most direct evidence available: real frame brightness, measured directly
from the video files this project actually has on disk.

This is a pure read-only verification pass. No pipeline file
(`roi/extractROISignals.m`, `filtering/*`, `pulseextraction/*`,
`heartrate/*`, `spo2/*`, any `validation/*` function) was touched, and
Task N's own report file was **not** edited — that correction is left for
a deliberate follow-up, per this task's instructions.

## Method

For 5 subjects with both `v4/source1` and `v5/source1` on disk (`p1`,
`p3`, `p4`, `p6`, `p7` — the same 20-subject Task N subset;
`v5/source1` was newly extracted for these 5 via the same targeted
per-entry zip extraction already used throughout this project), the frame
at `round(NumFrames / 2)` was read from each of that subject's v4 and v5
videos — the same "representative midpoint frame" convention already used
by `roi/extractROISignals.m`'s `debugFrame.frameIndex` for the existing
sanity PNGs. Each frame was converted to grayscale and its mean pixel
intensity (0-255 scale) computed over the **full frame**, not just the
face/ROI, as a simple, objective brightness number independent of any
face-detection step.

## Results

| Subject | v4 mean intensity | v5 mean intensity | Brighter |
|---|---|---|---|
| p1 | 133.98 | 131.05 | **v4** |
| p3 | 127.31 | 120.56 | **v4** |
| p4 | 135.21 | 120.40 | **v4** |
| p6 | 149.50 | 115.61 | **v4** |
| p7 | 129.54 | 102.41 | **v4** |

Consistent across all 5 subjects, no exceptions, no ties. v4 is brighter
than v5 by 3-27 mean-intensity points, every time.

Side-by-side frame pairs (v4 left, v5 right, each labeled with its
measured mean intensity):

- `results/figures/v4_v5_brightness_check_p1.png`
- `results/figures/v4_v5_brightness_check_p3.png`
- `results/figures/v4_v5_brightness_check_p4.png`
- `results/figures/v4_v5_brightness_check_p6.png`
- `results/figures/v4_v5_brightness_check_p7.png`

Visual inspection of all 5 pairs confirms the numbers, not just the raw
average: v4 frames show even, cool-toned, well-lit rooms consistent with
a ceiling lamp being on. v5 frames are visibly dimmer overall, with a
warm/orange directional glow on one side of the face and a noticeably
darker background — consistent with the ceiling lamp being off and only a
single filament lamp providing light, exactly the physical setup
`ReadMe.pdf` itself describes for "dark: ceiling lamp off" (just attached
to the wrong scenario number). This is not a borderline or ambiguous
result in either the numbers or the images.

## Conclusion

**v4 is confirmed to be the bright scenario and v5 is the dark scenario,
based on direct pixel intensity measurement.**

This matches the published VIPL-HR paper's Table 3 (Situation 4 = Bright,
Situation 5 = Dark) and contradicts the `ReadMe.pdf` text `docs/
Segment6_Task_N_Multi_Region_ROI.md` relied on (whether that PDF's text is
itself wrong, or was misread, or the distributed folder naming simply does
not follow the PDF's prose 1:1, was not further investigated here — the
measured pixel evidence is conclusive regardless of which text source
caused the mix-up).

## Consequence for Task N's report — flagged, not auto-corrected

Per this task's explicit instruction, `Segment6_Task_N_Multi_Region_ROI.md`
was **not** edited. Stated plainly instead: that report's v4/v5 label is
**backwards**. Its "v4 (dark)" scenario arm is actually the bright
scenario, and its Section 5 narrative that currently reads "forehead wins
both motion (v2) and dark (v4)" and "cheek's larger, lower patch pools
more/better-lit skin at baseline; under motion and in the dark, forehead's
narrower patch... holds up better" has its v4 half of that claim backwards
as a light-condition explanation — the numbers themselves (MAE/RMSE/r per
region, computed straight from the real v4 video files) are NOT affected
by this label error and do not need to be re-run or recomputed. Only the
scenario's name and the light-condition narrative built on top of it need
correcting: relabel that arm "v4 (bright)", and note that this project's
20-subject subset does not yet have a v5/dark ROI comparison run at all
(only 5 subjects' v5 video are even extracted, purely for this brightness
check) — extending Task N's 4-region comparison to actual v5/dark data is
a real, not-yet-done follow-up, separate from Task N's existing v1/v2/v4
results.

`docs/VIPL_Scenario_Coverage.md`'s prose (which independently also swaps
v4/v5's descriptions) should be corrected in the same follow-up pass, for
the same underlying reason.
