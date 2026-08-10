# VIPL-HR Integration — Line-by-Line Explanation

This document walks through `matlab/src/io/loadVIPLVideo.m` and
`matlab/src/io/loadVIPLGroundTruth.m` block by block, and explains what was
genuinely *different* about VIPL-HR's real on-disk format compared to
UBFC's — the design decisions those differences forced, not just what the
code does. `docs/VIPL_DATA_FORMAT.md` is the source of truth for every
factual claim made here about the raw files; this document is about the two
loader functions built on top of it.

No Segment 2-5 algorithm file changed. Every design decision below lives
entirely inside the two new loader files — that was a hard constraint of
this integration, not a coincidence.

---

## Part 0 — Why VIPL-HR needed a genuinely different loader shape than UBFC

`io/loadUBFCVideo.m` takes one input, `videoPath`, because UBFC has exactly
one addressable unit per subject: one video file, found by the caller
globbing for the single `.avi` in that subject's folder. VIPL-HR does not
have that. A real zip-entry listing of `p1-5.zip` (881 entries, no
extraction needed to see this) shows every subject has up to 9 scenario
folders (`v1`-`v9`) and up to 4 device folders inside each
(`source1`-`source4`), and **every one of those (subject, scenario, source)
combinations is its own independent video with its own independent ground
truth files**. There is no single "the video" for a VIPL-HR subject the way
there is for a UBFC subject.

This is why `loadVIPLVideo.m` and `loadVIPLGroundTruth.m` both take three
identifiers — `subjectNum`, `scenarioNum`, `sourceNum` — instead of one
`subjectID` string. The task brief that kicked off this integration
originally suggested a 2-part `(subjectID, sourceID)` scheme; that was
revised after actually looking at the real folder tree, because it silently
assumes every subject has exactly one video per source, which is false (a
given subject can have the same source recorded across up to 9 different
scenarios, each a physically different video with different ground truth).

---

## Part 1 — `loadVIPLVideo.m`

### Path construction and source validation

```matlab
if sourceNum == 4
    error('loadVIPLVideo:nirNotSupported', ...);
end

if sourceNum ~= 1 && sourceNum ~= 2 && sourceNum ~= 3
    error('loadVIPLVideo:badSource', ...);
end

subjectFolder = ['p' num2str(subjectNum)];
scenarioFolder = ['v' num2str(scenarioNum)];
sourceFolder = ['source' num2str(sourceNum)];

videoPath = fullfile(viplRoot, subjectFolder, scenarioFolder, sourceFolder, 'video.avi');
```

`source4` is rejected with a specific, named error rather than silently
loaded, because it is VIPL-HR's near-infrared (NIR) camera, not RGB — a
different sensing modality this project's `extractROISignals.m` onward was
never built to handle, and the task brief was explicit that NIR handling is
out of scope for this segment. Any other value outside `{1, 2, 3}` is also
rejected, since VIPL-HR only defines four sources total. The path is built
directly from the three numeric identifiers using VIPL-HR's own confirmed
naming convention (`pXXX/vY/sourceN/video.avi`) — no globbing needed, unlike
UBFC's DATASET_1 loader, because VIPL-HR's filenames are fixed
(`video.avi`, always) rather than varying per subject the way UBFC
DATASET_1's video filenames do.

### Opening the video and reading the container's frame rate

```matlab
frames = VideoReader(videoPath);
containerFrameRate = frames.FrameRate;
numFrames = frames.NumFrames;
```

Same discipline as `loadUBFCVideo.m`: the video is opened but not
preloaded, and frame rate is read from the file, never hardcoded. This is
where VIPL-HR's real format forced the first genuinely new design decision.

### The frame-rate correction — the biggest real format surprise found

```matlab
timePath = fullfile(viplRoot, subjectFolder, scenarioFolder, sourceFolder, 'time.txt');

if isfile(timePath)
    frameTimestampsMs = readmatrix(timePath, 'FileType', 'text');
    numTimestamps = numel(frameTimestampsMs);

    if numTimestamps >= 2
        elapsedSec = (frameTimestampsMs(numTimestamps) - frameTimestampsMs(1)) / 1000;
        timestampFrameRate = (numTimestamps - 1) / elapsedSec;
        ...
        frameRate = timestampFrameRate;
    else
        ...
        frameRate = containerFrameRate;
    end
else
    ...
    frameRate = containerFrameRate;
end
```

This project's established rule, learned from UBFC, is "always read fps
from `VideoReader.FrameRate`, never hardcode it." Testing that rule against
real VIPL-HR files showed it is **not sufficient on its own** for this
dataset. Every video tested — regardless of source — reported exactly
`FrameRate = 25` from `VideoReader`, including `source3`/`source4`, whose
own `ReadMe.pdf` entry claims "~30 fps". Cross-checking against each
video's own `time.txt` (present for source1/3/4) showed the container's
declared 25 fps was measurably wrong for some recordings:

| Video | Container FrameRate | time.txt-derived FrameRate | Disagreement |
|---|---|---|---|
| p1/v1/source1 | 25 | 29.80 | 19.2% |
| p1/v1/source3 | 25 | 29.96 | 19.8% |
| p2/v1/source1 | 25 | 24.93 | 0.3% |
| p3/v1/source1 | 25 | 24.93 | 0.3% |

VIPL-HR's own `ReadMe.pdf` actually explains why, in a sentence easy to
skim past: for source1/source3/source4 it states *"the videos are only used
for compression and the time steps for the frames are recorded in the
time.txt."* The container's frame rate is a re-encoding artifact, not real
acquisition timing — the dataset's own authors are telling readers to
recompute it from `time.txt` instead. `loadVIPLVideo.m` does exactly that
whenever a `time.txt` file exists: it computes `(numTimestamps - 1) /
elapsed_seconds` from the real per-frame timestamps and uses that as
`frameRate`, printing a `disp()` warning whenever it disagrees with the
container's own declared value by more than 5%.

`source2` (the phone camera) has **no `time.txt` at all**, in every
instance checked — confirmed against the real zip listing, zero exceptions.
There is no way to independently verify its declared frame rate, so
`loadVIPLVideo.m` falls back to `VideoReader.FrameRate` for source2 and
says so explicitly in a `disp()` message, so this known limitation is
visible at runtime, not just in a comment nobody reads.

::: Why this matters
A wrong frame rate does not just shift a timestamp — `heartrate/
fftHeartRate.m` converts an FFT bin's frequency directly to bpm using
`frameRate`. A 19-20% frame-rate error, uncaught, would produce an HR
estimate roughly 19-20% off for every affected video, silently. This was
the single biggest, most consequential real-format surprise found in this
integration.
:::

### Return values

```matlab
frameRate = ...;
numFrames = frames.NumFrames;
videoPath = ...;
```

`videoPath` is returned in addition to the three values `loadUBFCVideo.m`
already returns, purely so `run_vipl_integration_batch.m`'s progress
logging can print exactly which file was opened without reconstructing the
path a second time — a convenience addition, not a format-driven one.

---

## Part 2 — `loadVIPLGroundTruth.m`

### Why the ground truth needed its own design decision, separate from the video loader

UBFC DATASET_1's `gtdump.xmp` is one file with four columns
(`timestamp_ms, HR, SpO2, PPG`), all sharing one row per oximeter sample —
`io/loadGroundTruth.m` returns `gt.timestamp`, `gt.hr`, `gt.spo2`, `gt.ppg`
as four parallel, equal-length vectors, and downstream code (e.g.
`scripts/run_segment5_dataset1_calibration_batch.m`) relies on that: it
masks `gt.timestamp <= videoDurationSec` and applies that same mask,
by position, to `gt.spo2`.

VIPL-HR ships ground truth as **three separate files**, each at its own
native rate, confirmed directly from real file content:

- `gt_HR.csv` — one HR value per **elapsed second**, header `HR`, no
  timestamp column.
- `gt_SpO2.csv` — one SpO2 value per elapsed second, header `SpO2`, same
  row count as `gt_HR.csv` in every file checked.
- `wave.csv` — the BVP waveform, header `Wave`, one sample roughly every
  16-17 ms (~60 Hz) — a completely different length and rate from the
  other two (e.g. p1/v1/source1: 36 HR/SpO2 rows vs. 2084 wave rows).

There is no single shared per-row timestamp covering all three the way
`gtdump.xmp`'s one timestamp column covers all four of its columns. This is
the format surprise that forced a real decision, not a mechanical
translation of `loadGroundTruth.m`'s existing shape.

### The decision: keep `gt.timestamp`/`gt.hr`/`gt.spo2` parallel; let `gt.ppg` be its own length

```matlab
hrValues = hrTable.HR;
spo2Values = spo2Table.SpO2;
ppgValues = waveTable.Wave;

numCommonSamples = min(numHRSamples, numSpO2Samples);

for samplePos = 1:numCommonSamples
    hr(samplePos) = hrValues(samplePos);
    spo2(samplePos) = spo2Values(samplePos);
    timestamp(samplePos) = samplePos - 1;
end

gt.timestamp = timestamp;
gt.hr = hr;
gt.spo2 = spo2;
gt.ppg = ppgValues;
```

`gt.timestamp` is **reconstructed**, not read from a file — there is no
timestamp column in `gt_HR.csv`/`gt_SpO2.csv` to read. It is built as
elapsed whole seconds (`0, 1, 2, ...`) because the VIPL-HR `ReadMe.pdf`
states both files are "recorded every second," implying a shared, implicit
t=0 start with one sample per second thereafter. This was chosen
specifically so `gt.timestamp <= videoDurationSec` masking — the exact
pattern `run_segment5_dataset1_calibration_batch.m` already uses for UBFC —
keeps working unmodified if a future VIPL-specific validation script needs
it: index-position alignment between `gt.timestamp`, `gt.hr`, and `gt.spo2`
is preserved, just like UBFC's shape, only at a coarser (1 Hz instead of
~62 Hz) native resolution.

`gt.ppg` is deliberately **not** forced into that same length. Padding or
resampling `wave.csv`'s ~60 Hz, ~2084-sample BVP waveform down to
`gt.hr`'s 36 samples would either throw away almost all of the real
waveform detail or fabricate samples that were never actually measured —
neither is honest, and neither was necessary: none of this project's
existing Segment 4/5 batch scripts index `gt.ppg` elementwise against
`gt.timestamp` today. `gt.ppg` is returned as-is, at its own native rate,
with this asymmetry documented explicitly in the function's own header
comment so a future caller does not assume all four fields are parallel the
way they are for UBFC DATASET_1.

::: A smaller, easy-to-miss format detail
`gt_HR.csv`/`gt_SpO2.csv`/`wave.csv` are only guaranteed to share one
recording session **within** a given `(subject, scenario, source1-or-3-or-4)`
group — confirmed for p1/v1: source1, source3, and source4's ground truth
files all have identical row counts (36/36/2084) because those three
physical devices record simultaneously. `source2` (the phone) is a
**separate take** with its own independent, different-length ground truth
(45/45/2621 for the same p1/v1) — it is not the same physiological
recording repackaged. `loadVIPLGroundTruth.m` does not need to handle this
specially (it always reads exactly the one folder matching the
`(subjectNum, scenarioNum, sourceNum)` it was given), but a caller must not
assume a source2 video and a source1 video from the "same" scenario share a
timeline — they don't.
:::

### Row-count mismatch defense

```matlab
if numHRSamples ~= numSpO2Samples
    disp(['loadVIPLGroundTruth: WARNING -- gt_HR.csv has ' ... 'truncating both to the shorter length.']);
end

numCommonSamples = min(numHRSamples, numSpO2Samples);
```

Every file pair checked in this integration had matching row counts, but
nothing in VIPL-HR's format guarantees that for the full 107-subject pool
this integration has not yet processed. Truncating to the shorter length
and printing a loud `disp()` warning (rather than erroring outright, or
silently zero-padding) keeps the batch script's fail-and-continue pattern
working for a subject with this kind of minor real-world data glitch,
without hiding that the glitch happened.

---

## Part 3 — Why the shared result CSVs got their own VIPL-suffixed files

`results/metrics/segment4_hr_summary.csv` and
`segment5_dataset1_calibration.csv` already exist on disk with real UBFC
rows, written by teammates' `run_segment4_heartrate_batch.m` and
`run_segment5_dataset1_calibration_batch.m` under a fixed column header
that has no `dataset` column. Those two scripts own those files' headers —
they are explicitly out of scope for this integration to touch. Rewriting
a live, already-populated shared file's schema out from under a 4-person
team, just so this integration's own rows can carry one extra column, was
judged a worse outcome than the alternative: `run_vipl_integration_batch.m`
writes to its own `segment4_hr_summary_vipl.csv` and
`segment5_vipl_calibration.csv`, using the exact same column order as their
UBFC counterparts plus one explicit trailing `dataset` column (always
`VIPL`). Segment 6 can pool both datasets either by reading the explicit
`dataset` column on the VIPL files, or by concatenating both HR files
directly and inferring dataset from the `VIPL_` subjectID prefix on rows
that lack the column — both paths work, and neither required touching a
file this integration does not own.
