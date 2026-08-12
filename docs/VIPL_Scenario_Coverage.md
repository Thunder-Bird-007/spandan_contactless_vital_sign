# VIPL-HR Scenario Coverage & Ground-Truth Spread — Reconnaissance

This is a companion to `VIPL_DATA_FORMAT.md`, not a replacement — that file's
subject/scenario/source addressing scheme, `time.txt`/frame-rate findings,
and source-device table (Section 3) are the reference for how any of this
data is actually loaded. This file only adds: (1) what v1-v9 actually
contain across all 107 subjects, read directly off the 21 zip archives'
central directories (no extraction), and (2) a lightweight ground-truth-only
spread check across scenarios, read directly from `gt_HR.csv`/`gt_SpO2.csv`
inside the zips. No video was decoded and no new extraction, ROI processing,
or batch pipeline run was started for this pass.

Source of truth: `VIPL-HR-V1/data/*.zip` (21 archives, all 107 subjects),
cross-checked against `VIPL-HR-V1/Missing_data.txt` (107 documented gaps).
`spandan/data/raw/VIPL-HR/` on disk only has v1 extracted (110 videos: p1's
4 sources + 106 other subjects' single primary/fallback source) — v2-v9 have
never been touched locally, confirming the existing project note.

## 1. Coverage matrix (subject × scenario × RGB source)

Cell digits mean which of **source1/source2/source3** have a `video.avi` in
the archive for that subject/scenario; `-` means the whole scenario is
absent for that subject. **source4 (RealSense NIR) is omitted from this
table on purpose** — it is out of scope per this project's RGB-only rule,
and per `VIPL_DATA_FORMAT.md` Section 3, `loadVIPLVideo.m` already rejects
`sourceNum==4`. For the record, source4 tracks source3 almost exactly
(NIR and RGB come off the same physical RealSense F200 rig) — everywhere
source3 is present, source4 is present too, with the same handful of
exceptions.

Per-scenario totals out of 107 subjects (RGB sources only):

| Scenario | source1 (Logitech C310) | source2 (HUAWEI P9 phone) | source3 (RealSense F200 RGB) |
|---|---|---|---|
| v1 — stable, normal light, 1m | 95 | 107 | 107 |
| v2 — large head motion | 93 | 107 | 107 |
| v3 — talking | 95 | 106 | 106 |
| v4 — bright light | 96 | 107 | 107 |
| v5 — dark light | 93 | 107 | 106 |
| v6 — stable, 1.5m | 94 | 106 | 106 |
| v7 — after exercise | 91 | 106 | 105 |
| v8 — hand-held phone, stable | 0 (phone-only) | 106 | 0 (phone-only) |
| v9 — hand-held phone, large motion | 0 (phone-only) | 105 | 0 (phone-only) |

v8/v9 confirm the already-documented "phone-only" structure — `source2` is
the **only** folder that exists for those two scenarios, for every subject
that has them at all, exactly as `VIPL_DATA_FORMAT.md` Section 2 states.

Full per-subject matrix (digits = which of source1/2/3 present, `-` = whole
scenario missing for that subject):

<details>
<summary>107-row coverage table (click to expand)</summary>

| Subject | v1 | v2 | v3 | v4 | v5 | v6 | v7 | v8 | v9 |
|---|---|---|---|---|---|---|---|---|---|
| p1 | 123 | 123 | 123 | 123 | 123 | 123 | 23 | 2 | 2 |
| p2 | 123 | 23 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p3 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p4 | 123 | 123 | 123 | 123 | 123 | 23 | 123 | 2 | 2 |
| p5 | 123 | 23 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p6 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p7 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p8 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p9 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p10 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p11 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 | 2 |
| p12 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p13 | 123 | 123 | 123 | 123 | 123 | 123 | 23 | 2 | 2 |
| p14 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p15 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p16 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p17 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p18 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p19 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p20 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p21 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p22 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p23 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p24 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p25 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p26 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p27 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p28 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p29 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p30 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p31 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p32 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p33 | 123 | 123 | 123 | 123 | 23 | 123 | 123 | 2 | 2 |
| p34 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p35 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p36 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p37 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p38 | 123 | 123 | 123 | 123 | 23 | 123 | 123 | 2 | 2 |
| p39 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p40 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p41 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p42 | 123 | 123 | - | 123 | 123 | 123 | 123 | 2 | 2 |
| p43 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p44 | 123 | 123 | 123 | 123 | 123 | 123 | 23 | 2 | 2 |
| p45 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | - |
| p46 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p47 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p48 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p49 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p50 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p51 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p52 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p53 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p54 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p55 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p56 | 123 | 123 | 123 | 123 | 123 | - | - | - | - |
| p57 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p58 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p59 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p60 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p61 | 123 | 123 | 123 | 123 | 23 | 123 | 123 | 2 | 2 |
| p62 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p63 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p64 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p65 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p66 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p67 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p68 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p69 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p70 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p71 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p72 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p73 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p74 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p75 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p76 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p77 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p78 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p79 | 123 | 123 | 123 | 123 | 12 | 123 | 123 | 2 | 2 |
| p80 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p81 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p82 | 123 | 23 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p83 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p84 | 23 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p85 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p86 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p87 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p88 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p89 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p90 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p91 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p92 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p93 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p94 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p95 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p96 | 123 | 123 | 123 | 123 | 123 | 123 | 123 | 2 | 2 |
| p97 | 23 | 23 | 23 | 23 | 23 | 23 | 23 | 2 | 2 |
| p98 | 23 | 23 | 23 | 23 | 23 | 23 | 23 | 2 | 2 |
| p99 | 23 | 23 | 23 | 23 | 23 | 23 | 23 | 2 | 2 |
| p100 | 23 | 23 | 23 | 23 | 23 | 23 | 23 | 2 | 2 |
| p101 | 23 | 23 | 23 | 23 | 23 | 23 | 23 | 2 | 2 |
| p102 | 23 | 23 | 23 | 23 | 23 | 23 | 23 | 2 | 2 |
| p103 | 23 | 23 | 23 | 23 | 23 | 23 | 23 | 2 | 2 |
| p104 | 23 | 23 | 23 | 23 | 23 | 23 | 23 | 2 | 2 |
| p105 | 23 | 23 | 23 | 23 | 23 | 23 | 23 | 2 | 2 |
| p106 | 23 | 23 | 23 | 23 | 23 | 23 | 23 | 2 | 2 |
| p107 | 23 | 23 | 23 | 23 | 23 | 23 | 23 | 2 | 2 |

</details>

### Flags against the already-known source1/source2 pattern

- **p97-p107 (11 subjects) never have source1 in any scenario, not just
  v1.** This matches and extends the existing project note ("source2 as
  fallback for 12 subjects where source1 was missing") — but that note was
  written against v1 only. It generalizes cleanly for 11 of those 12: the
  Logitech webcam was never used for their sessions at all.
- **p84 is the one exception, and it's a real surprise.** p84 is missing
  source1 **only in v1** — source1 is present for p84 in v2 through v9. The
  existing "12 subjects, source2 fallback" framing lumps p84 in with
  p97-p107 as if source1 is categorically absent for it, but it isn't; v1's
  own recording session for p84/source1 simply failed or was skipped
  (`Missing_data.txt` lists exactly one line for p84: `p84/v1/source1`).
  If this project ever extracts a second scenario, p84 should use source1
  like the other ~94 subjects, not source2 — the phone fallback was v1-only.
- **p56 is the most incomplete subject in the archive**: it has v1-v5, but
  v6, v7, v8, and v9 are entirely absent (not just one source — the whole
  scenario folder). Any per-scenario extraction plan needs to expect n=106
  for v6/v7 and treat p56 as excluded there, consistent with
  `Missing_data.txt`'s 8 separate `p56/...` lines.
- Beyond that, the gaps are small and scattered (1-6 subjects short of 107
  per scenario/source), all independently confirmed against
  `Missing_data.txt`'s 107 lines — nothing indicates a systematic recording
  failure beyond p56 and the p97-p107/source1 pattern.

## 2. v7 (after-exercise) ground-truth spread vs v1

Pulled directly from `gt_HR.csv` / `gt_SpO2.csv` inside the zips, same
source-priority rule this project already uses for v1 (source1 primary,
source2 fallback for the subjects that lack source1). Raw pooled stats
below include VIPL's own out-of-range sensor fault codes (**255 for HR,
44/127+ for SpO2** — the same class of pulse-oximeter fault already caught
for UBFC's p25); a cleaned version with those fault samples stripped
(HR<200bpm, 50≤SpO2≤100%) is reported alongside since it is the physically
meaningful number.

| Scenario | Metric | Raw min–max | Raw mean±std | **Cleaned min–max** | **Cleaned mean±std** | n subjects |
|---|---|---|---|---|---|---|
| v1 (baseline) | HR | 47–104 | 75.4 ± 10.1 | (no fault codes in v1 HR) | 75.4 ± 10.1 | 107 |
| v1 (baseline) | SpO2 | 44–99 | 96.5 ± 5.3 | **84–99** | **96.95 ± 1.88** | 107 |
| v7 (after-exercise) | HR | 56–255 | 99.3 ± 19.6 | **56–157** | **98.64 ± 16.72** | 106 |
| v7 (after-exercise) | SpO2 | 44–127 | 95.8 ± 8.1 | **54–99** | **96.80 ± 2.07** | 106 |

**v7 SpO2 is barely wider than v1's, once fault codes are stripped**: 54-99
cleaned range (driven by a couple of low outlier subjects) vs v1's 84-99,
and the std only grows from 1.88 to 2.07. This matches the already-known
finding that VIPL/UBFC SpO2 ground truth is inherently narrow-band
(95-99% is where healthy resting/post-exercise SpO2 actually lives) — v7
would **not** meaningfully strengthen the SpO2 model. It mainly adds a
handful of fault-code subjects (p24, p75, p85, p90, p94 all show
44/127-type sensor dropouts in v7 — worth noting p85 also faults in v8/v9,
suggesting p85's sensor itself is unreliable across the board, not just an
after-exercise artifact).

**v7 HR is a much bigger and more clearly genuine shift**: cleaned mean
jumps from 75.4 to 98.6 bpm (+23 bpm), and std nearly doubles (10.1 → 16.7).
This is exactly the physiologically-expected effect of "after exercise" and
is the strongest HR-variance signal found in this whole recon pass.

## 3. v2-v6 ground-truth HR spread vs v1

Same method, cleaned (HR<200bpm) pooled stats:

| Scenario | Description | Cleaned min–max | Cleaned mean±std | n subjects | Verdict |
|---|---|---|---|---|---|
| v1 | stable, normal light, 1m (baseline) | 47–104 | 75.4 ± 10.1 | 107 | — |
| v2 | large head motion | 51–108 | 76.5 ± 9.6 | 107 | near-duplicate of v1's range |
| v3 | talking | 53–107 | 81.8 ± 10.5 | 106 | mean shifted +6bpm, mild new signal |
| v4 | bright light | 48–103 | 76.3 ± 9.8 | 107 | near-duplicate of v1's range |
| v5 | dark light | 50–105 | 76.5 ± 10.0 | 107 | near-duplicate of v1's range |
| v6 | stable, 1.5m distance | 52–139 | 79.0 ± 11.7 | 106 | widest of v2-v6, some new range |
| v7 | after exercise | 56–157 | 98.6 ± 16.7 | 106 | **by far the strongest new signal** |

v2, v4, and v5 essentially reproduce v1's HR distribution — expected, since
head motion, bright light, and dark light change the **imaging** difficulty
(motion artifacts, illumination robustness) without changing the subject's
actual physiology, so their ground truth HR looks just like resting-state
v1. They're valuable for testing the pipeline's *robustness* to imaging
conditions, but they add essentially zero new HR range to train/validate
against. v3 (talking) nudges the mean up modestly (talking raises HR a
little and adds motion from jaw/face movement). v6 (1.5m) has the widest
range/std of the non-exercise scenarios — worth a note, though the physical
reason (distance changing camera framing, not physiology) is less obviously
tied to HR variance than v7's is.

For reference, v8/v9 (phone-held, source2 only) land close to v1's range too
(HR 55-102 and 50-109 respectively) — unsurprising since they're not
exercise scenarios, but they do bring a **different camera device**
(HUAWEI P9 phone) into the pool, which is a source-diversity gain distinct
from HR-range gain.

## 4. Bottom line: which combination is best for HR vs SpO2

**For strengthening the HR model:** extract **v7 (after-exercise),
source1-primary/source2-fallback**, following exactly the same
source-priority rule already used for v1. It is the only scenario in v2-v9
whose ground-truth HR distribution meaningfully differs from v1's — cleaned
mean +23bpm, std nearly doubled, min-max range extends to 157bpm (vs v1's
104bpm cap). None of v2/v4/v5/v8/v9 offer that; v3 and v6 offer a smaller
version of it. Extracting v7 next, at the same ~91-106-subject coverage as
v1, is the highest-value single addition to the HR pool this recon pass
identified. Expect roughly 5-6% of v7 subjects (p24, p90, p94, plus
whichever others show up once source1 is checked directly) to carry a
sensor-fault gt_HR.csv that needs the same 255-code stripping done here
before any model training.

**For strengthening the SpO2 model:** none of v2-v9 look promising on
ground-truth spread alone — v7's SpO2 range only grows from 84-99 to 54-99
(and that widening is fault-code driven, not a real physiological range
extension), and v8/v9's cleaned SpO2 stats (92-99, std ~1.4) are if
anything **narrower** than v1's. This confirms the standing finding from
segment 5/6 ([[segment5-spo2-implementation]], [[segment6-refinement-findings]])
that VIPL/UBFC SpO2 ground truth is a fundamentally narrow-band signal
regardless of scenario — no VIPL scenario recon can fix that; it would need
a dataset with genuine hypoxic/desaturation events, which VIPL does not
appear to contain. Extracting v7 for SpO2 specifically is not worth the
storage/processing cost on this evidence.

**If both are wanted from one extraction pass**, v7 is still the answer —
it is the only scenario that helps HR at all, and it does not hurt SpO2
(its cleaned SpO2 stats are within noise of v1's). There is no scenario in
v2-v9 that is uniquely good for SpO2 and not for HR, so there is no
trade-off to make here: extract v7 once, benefit HR, get SpO2 data
essentially "for free" (even though it won't move that model's needle).

## 5. Source3/HUAWEI-phone-device note (Task D/E cross-device R-offset)

Two device-identity corrections surfaced in this pass that affect the
cross-device R-offset question:

- **The existing "source2 = RealSense F200 fallback for p84/p97-107" framing
  in this project's own notes is wrong.** Per `VIPL_DATA_FORMAT.md` Section 3
  (already cross-checked against `ReadMe.pdf` and real file structure,
  independent of this pass), **source2 is the HUAWEI P9 phone**, and
  **source3 is the RealSense F200 RGB camera**. The 11 subjects (p97-p107)
  that never have source1, plus p84 for v1 only, were therefore processed
  through this project's existing `VIPL_p*_v1_source2_*` pipeline using
  **phone footage**, not RealSense footage as previously assumed. This
  doesn't change any numbers already computed, but it does change what
  device those 12 subjects' existing R-offset/calibration results should be
  attributed to — worth fixing in whatever writeup currently says
  "RealSense fallback" for those subjects.
- **The phone camera (source2) is not new or uncharacterized** — it's
  already present in the v1 pool for 12 subjects and now confirmed present
  in v2-v7 as well as the dedicated v8/v9 scenarios, at 105-107/107 subject
  coverage per scenario. Any future v8/v9 extraction would use the *same*
  phone device already implicitly in the v1-derived HR/SpO2 pool for those
  12 subjects, not a genuinely new fourth device.
