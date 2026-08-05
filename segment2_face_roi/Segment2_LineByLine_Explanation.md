# Segment 2 — Line-by-Line Explanation

This document walks through `matlab/src/io/loadUBFCVideo.m` and
`matlab/src/roi/extractROISignals.m` block by block, in plain teaching
language. It assumes you've read Chapter 4 of the project's Orientation
Lecture (Viola-Jones intuition, the "choir effect" analogy for spatial
averaging) but haven't seen this specific code before. The code files
themselves are deliberately bare of inline comments — this document is
where the *why* lives.

---

## Part 1 — `loadUBFCVideo.m`

### What the function is for

This is the very first step of the whole pipeline: open a subject's
`.avi` file and hand back something later code can pull frames from,
plus the two numbers everything downstream needs — the frame rate and
the frame count.

### The file-existence check

```matlab
if ~isfile(videoPath)
    error('loadUBFCVideo:fileNotFound', 'Video file not found: %s', videoPath);
end
```

Before doing anything else, we check the path actually points at a real
file. Without this, `VideoReader` would still throw an error if the
path is wrong, but MATLAB's own error message is a generic low-level one
("Unable to open file") that doesn't tell you *which* subject's video is
missing. When you're running a batch over dozens of subjects and one
folder is misnamed, a clear error naming the exact path saves a lot of
guessing. This is exactly the kind of failure the batch script (Part 4)
is built to catch and log, then move on from.

### Opening the video

```matlab
frames = VideoReader(videoPath);
frameRate = frames.FrameRate;
numFrames = frames.NumFrames;
```

`VideoReader` is MATLAB's built-in handle for a video file. Creating one
does **not** decode the whole video into memory — it just opens the file
and reads its header (container info, codec, frame rate, duration). That
header read is fast even though the file itself might be a gigabyte or
more.

We deliberately return the `VideoReader` object itself as `frames`,
rather than looping through it here and returning a giant
`H x W x 3 x numFrames` array of pixel data. The task brief was explicit
about this: UBFC-rPPG videos are uncompressed AVI, and a single subject's
video can be 1–2 GB on disk. Uncompressed data expands further once
loaded (each frame becomes a full-size RGB `uint8` array), and loading
every frame for every subject up front would either exhaust RAM or make
the whole pipeline painfully slow before any real work even starts.
Instead, whoever calls `loadUBFCVideo` gets a *handle* they can stream
frames from one at a time — see how `extractROISignals.m` does exactly
that with `hasFrame`/`readFrame`.

`frames.FrameRate` reads the frame rate directly from the AVI container's
own header field — it is not something MATLAB guesses or something we
hardcode. This matters a lot for this project specifically:
`docs/DATA_FORMAT.md` confirms (by directly parsing the AVI headers) that
UBFC-rPPG videos are *not* a clean 30 fps — they range roughly
28.6–29.8 fps and the exact value differs per subject. If we hardcoded
`fs = 30`, every downstream FFT-based heart-rate estimate would be
computed against a frequency axis that's subtly wrong for every subject,
which is exactly the kind of silent, hard-to-notice bug that produces
believable-but-incorrect results. Reading it straight from the file
avoids that entirely.

`frames.NumFrames` is likewise read from the container's frame index
rather than counted by decoding every frame — fast for an uncompressed
AVI like these.

---

## Part 2 — `extractROISignals.m`

### The overall shape of the function

The function receives the `VideoReader` handle and the frame rate from
`loadUBFCVideo.m`, and its job is to walk through the video frame by
frame, find the face, crop a small skin patch, and average the pixels in
that patch into one number per channel per frame. By the end it has
built three vectors — `R`, `G`, `B` — that are the raw material every
later pipeline stage (filtering, CHROM/POS, FFT heart rate) works on.

### Setting up before the loop

```matlab
detectEveryN = 5;
faceDetector = vision.CascadeObjectDetector();
frames.CurrentTime = 0;
numFrames = frames.NumFrames;
```

`vision.CascadeObjectDetector()` builds a Viola-Jones face detector using
its default frontal-face model. Viola-Jones works by sliding a window
over the image at many scales and checking, at each position, a cascade
of simple rectangular-contrast tests (this region should be darker than
that region, etc.) — most non-face windows get rejected after just the
first one or two cheap tests, which is why it can run in real time on a
CPU without any GPU or deep learning involved. That's the "cascade" in
the name: a sequence of increasingly strict filters, arranged so the vast
majority of the image is thrown out almost for free.

`frames.CurrentTime = 0` rewinds the reader to the start of the video.
This matters if the same `VideoReader` object were ever reused or partly
read before this function is called — it guarantees we always start from
frame 1.

**Why detect every 5th frame instead of every single frame** (the
`detectEveryN = 5` choice): running the full Viola-Jones cascade on every
one of ~2000–2400 frames is the single most expensive operation in this
function. A face does not move far in the roughly 1/6th of a second it
takes to skip 5 frames at ~29 fps — a resting subject sitting in front of
a webcam simply doesn't jump several centimeters between one detection
and the next. So the trade-off is: run the expensive detector only once
every 5 frames, and for the frames in between, reuse the most recent
bounding box. This cuts detector calls by 80% with essentially no cost to
ROI accuracy for this kind of mostly-still footage, which is exactly the
UBFC-rPPG recording setup (seated subject, static camera). The downside
is that if a subject makes a *fast* head movement, the reused box can lag
behind the true face position for up to 4 frames before the next
detection call catches up — for this dataset and this use case that lag
is judged an acceptable trade for roughly 5x faster processing. This
number is not a MATLAB built-in default; it is a project-specific choice
that a different dataset (faster head motion, lower frame rate) might
need to revisit.

### Preallocating the output arrays

```matlab
R = zeros(1, numFrames);
G = zeros(1, numFrames);
B = zeros(1, numFrames);
roiTimestamps = zeros(1, numFrames);
frameDroppedFlag = false(1, numFrames);
```

MATLAB arrays that grow one element at a time inside a loop
(`R(end+1) = ...`) force MATLAB to reallocate and copy the whole array
on every iteration, which gets very slow for thousands of frames.
Preallocating a fixed-size array up front and filling it in by index
avoids that entirely. `frameDroppedFlag` is a same-length logical array
that starts all `false` and gets flipped to `true` at any frame index
where the detector had to fall back instead of finding a face fresh —
this is how the "log which frames this happened on" requirement is
implemented without printing to the console on every single frame.

### The main per-frame loop

```matlab
frameIdx = 0;
while hasFrame(frames)
    frameIdx = frameIdx + 1;
    ...
    img = readFrame(frames);
```

This is a plain `while`/counter loop, not a vectorized "process the
whole video at once" trick — the task deliberately asked for an
explicit, readable frame-by-frame loop rather than clever vectorization,
and this is also simply how streaming video decoding has to work:
`readFrame` can only hand back one frame at a time, in order, advancing
an internal read pointer. `hasFrame` just asks "is there another frame
left to read" so the loop stops cleanly at the true end of the file
rather than relying purely on the `numFrames` count (which, for some
container formats, can be a slight over- or under-estimate of what's
actually decodable — the loop is written defensively against that).

### Deciding whether to run the detector this frame

```matlab
runDetectionThisFrame = mod(frameIdx - 1, detectEveryN) == 0;

if runDetectionThisFrame
    bboxes = step(faceDetector, img);
    if isempty(bboxes)
        frameDroppedFlag(frameIdx) = true;
        disp(['Frame ' num2str(frameIdx) ': face detector found nothing, reusing last known bounding box.']);
        currentBBox = lastGoodBBox;
    else
        bestBBox = bboxes(1, :);
        bestArea = bboxes(1, 3) * bboxes(1, 4);
        for boxRow = 2:size(bboxes, 1)
            thisArea = bboxes(boxRow, 3) * bboxes(boxRow, 4);
            if thisArea > bestArea
                bestArea = thisArea;
                bestBBox = bboxes(boxRow, :);
            end
        end
        currentBBox = bestBBox;
        lastGoodBBox = currentBBox;
    end
else
    currentBBox = lastGoodBBox;
end
```

`mod(frameIdx - 1, detectEveryN) == 0` is just the "every Nth frame"
test — it's true on frame 1, frame 6, frame 11, and so on, implementing
the trade-off described above.

`step(faceDetector, img)` is how you actually run a `vision.CascadeObjectDetector`
in MATLAB — `step` is the standard call pattern for MATLAB System
objects (the class `vision.CascadeObjectDetector` belongs to). It returns
one row per detected face, each row formatted `[x y width height]` in
pixels — `x, y` is the top-left corner of the box.

**Why the largest box, not just the first one.** The obvious first
instinct is "UBFC-rPPG videos are single-subject recordings, so just take
`bboxes(1, :)`, the first detected face." That was this implementation's
first version — and it broke on real data. Testing against subject
`6-gt` in this dataset, `step` returned *two* rows for the middle frame:
a tiny `[3 428 49 49]` box in a bottom corner of the frame (a false
positive — some patch of background texture that happened to pass the
whole Viola-Jones cascade) and the actual face at `[295 120 183 183]`.
Because `bboxes(1, :)` just takes whichever row the detector happens to
list first — which is not guaranteed to be sorted by confidence or size
— the first version of this code locked onto the tiny false-positive box
for that subject's entire video, and the sanity PNG for that subject
showed the ROI sitting on an empty corner of the room instead of a face.
The fix, shown above, is a small explicit loop that compares
`width * height` across every returned row and keeps whichever one is
largest. This works because in a single-subject frontal recording, a
real face detection is almost always a much bigger box than a stray
false positive — background clutter rarely coincidentally matches the
cascade at a large scale. It's not a mathematically guaranteed fix (a
close-up false positive could in principle be large too), but for this
dataset and this camera framing it is a simple, cheap, and effective
one — and it is exactly the kind of failure the mandatory sanity PNG
(see the next section) is there to catch before anyone trusts the
resulting signal.

If `step` comes back empty, that means Viola-Jones genuinely found no
face-shaped region this frame (could be a brief awkward head angle,
motion blur, or a lighting flicker). Rather than crash, or — worse —
silently write zero into `R`/`G`/`B` for that frame (which would look
like a legitimate physical measurement of "no light at all," corrupting
the signal), we fall back to `lastGoodBBox`, the most recent bounding box
that *did* come from a real successful detection, and we flag the frame
and print exactly which frame it happened on. This is the "handle missed
detections per frame gracefully" requirement from the brief, implemented
literally.

On frames where we don't run the detector at all (the 4 out of every 5
"skip" frames), we don't even attempt detection — we just carry forward
`lastGoodBBox` directly. This isn't a failure and isn't logged as one; it
is the intended behavior of the every-N-frames strategy.

### The one-time cold-start fallback

```matlab
if isempty(currentBBox)
    frameDroppedFlag(frameIdx) = true;
    disp(['Frame ' num2str(frameIdx) ': no bounding box available yet, using centered fallback box.']);
    currentBBox = [round(0.2 * frameWidth), round(0.2 * frameHeight), round(0.6 * frameWidth), round(0.6 * frameHeight)];
end
```

There's one edge case the logic above doesn't cover: what if the very
first frame (or first several frames, if the subject briefly isn't
facing the camera yet) fails to detect a face at all? Then
`lastGoodBBox` is still empty — there is nothing to fall back to yet.
Rather than let the ROI crop step below crash on an empty box, we use a
generic centered box covering the middle 60% of the frame width and
height. This is a coarse fallback, not a real face detection, but it is
far better than a crash, and it only ever applies to the small number of
frames before the first successful detection — every one of these frames
is flagged and printed just like a normal detection miss, so nothing is
hidden.

### Turning a face box into a forehead ROI box

```matlab
faceX = currentBBox(1);
faceY = currentBBox(2);
faceW = currentBBox(3);
faceH = currentBBox(4);

roiX1 = max(1, round(faceX + 0.30 * faceW));
roiX2 = min(frameWidth, round(faceX + 0.70 * faceW));
roiY1 = max(1, round(faceY + 0.10 * faceH));
roiY2 = min(frameHeight, round(faceY + 0.30 * faceH));
```

The Viola-Jones face box spans roughly hairline-to-chin vertically and
ear-to-ear horizontally. We don't want the whole face — eyes and
eyebrows move (blinking, expressions), the mouth moves (talking,
swallowing), and hair/background at the very edges of the box carries no
blood-flow signal at all and would just dilute the average with noise.
What we want is a patch of *plain, mostly-still skin* with strong blood
perfusion under it.

The chosen fractions crop a horizontal band that sits:
- **Horizontally**, from 30% to 70% of the face box width — i.e. the
  central 40%, discarding the outer 30% on each side where hair, ears,
  and the edge of the face curve away from the camera tend to sit.
- **Vertically**, from 10% to 30% of the face box height — i.e. a band
  just below the hairline and well above where eyebrows typically start
  (eyebrows are usually somewhere past the 35–40% mark down a
  Viola-Jones face box). This keeps the crop squarely on forehead skin
  and clear of both hair above and eyes/eyebrows below.

These specific numbers (0.30/0.70 horizontally, 0.10/0.30 vertically)
were chosen by inspection as a safe, conservative forehead patch rather
than tuned against ground truth — see the sanity PNGs in
`results/figures/` for a visual check that they land where intended for
this project's subjects. `max(1, ...)` and `min(frameWidth/frameHeight, ...)`
just guard against the box mathematically stepping outside the actual
frame if a detected face box happens to sit very close to an image edge.

### Averaging the ROI into one number per channel — the "choir effect"

```matlab
roiPatch = img(roiY1:roiY2, roiX1:roiX2, :);

redChannel = double(roiPatch(:, :, 1));
greenChannel = double(roiPatch(:, :, 2));
blueChannel = double(roiPatch(:, :, 3));

R(frameIdx) = mean(redChannel(:));
G(frameIdx) = mean(greenChannel(:));
B(frameIdx) = mean(blueChannel(:));
```

`img(roiY1:roiY2, roiX1:roiX2, :)` crops out just the forehead patch —
all rows from `roiY1` to `roiY2`, all columns from `roiX1` to `roiX2`,
and all 3 color planes (`:` in the third dimension). Each color plane is
converted to `double` before averaging, because the raw frame is `uint8`
(0–255 integers) and `uint8` arithmetic in MATLAB saturates and rounds
in ways that would quietly corrupt an average of a large pixel patch.

The single `mean(...)` call over every pixel in that patch, for each
channel, one number, is the "choir effect" from the Orientation Lecture:
any one pixel's blood-flow-driven brightness change is tiny and buried
in camera sensor noise — like a single singer's voice being hard to pick
out. But the *pattern* of that tiny change is shared across every pixel
in the ROI at once (blood volume under the whole patch of skin rises and
falls together), while the noise at each pixel is independent and
random. Averaging hundreds or thousands of pixels together lets that
shared, physiologically-driven signal survive while the independent
per-pixel noise mostly cancels out — the same way a choir of untrained
voices sounds more in tune together than any one voice does alone. This
is also exactly why we crop a *specific* patch of skin rather than
averaging the whole image: including hair, background, or eyes would add
pixels whose brightness has nothing to do with blood flow, diluting the
very signal the averaging is trying to strengthen.

`roiTimestamps(frameIdx) = (frameIdx - 1) / frameRate;` builds each
frame's timestamp in seconds directly from its position and the true
frame rate read back in `loadUBFCVideo.m` — frame 1 is time 0, frame 2 is
time `1/frameRate`, and so on. This is what later lets a ground-truth
signal (sampled on its own independent clock) be aligned against these
per-frame RGB values.

### Capturing one frame for the sanity-check figure

```matlab
currentROIBBox = [roiX1, roiY1, roiX2 - roiX1, roiY2 - roiY1];

if frameIdx == debugFrame.frameIndex
    debugFrame.image = img;
    debugFrame.faceBBox = currentBBox;
    debugFrame.roiBBox = currentROIBBox;
    debugFrame.frameIndex = frameIdx;
end
```

`debugFrame.frameIndex` was initialized before the loop to
`round(numFrames / 2)` — the middle frame of the video. On the one loop
iteration where `frameIdx` reaches that target, we save a copy of the
raw frame plus both bounding boxes (face and ROI), converting the ROI
box into the same `[x y width height]` format as the face box so both
can be drawn the same way. This is the data
`scripts/run_segment2_roi_batch.m` uses to draw the two colored
rectangles and save the sanity PNG — the whole point being that a human
can glance at one frame per subject and immediately confirm the ROI
landed on forehead skin, not hair, background, or eyes, before trusting
any signal built from it.

### Trimming the arrays and finalizing the dropped-frame list

```matlab
actualNumFrames = frameIdx;

if actualNumFrames < numFrames
    R = R(1:actualNumFrames);
    ...
end

droppedFrameIdx = find(frameDroppedFlag);
```

Because the arrays were preallocated using `frames.NumFrames` (a count
read from the file header) but the loop actually stops based on
`hasFrame` (what can really be decoded), the two counts can occasionally
disagree by a frame or two. If fewer frames were actually read than were
preallocated for, this trims the unused trailing zeros off every output
array so nothing downstream mistakes an unfilled zero for a real
(very dark) measurement. `find(frameDroppedFlag)` turns the logical
true/false array built during the loop into the actual list of frame
numbers where a fallback bounding box was used — this is the
`droppedFrameIdx` output, and its length becomes `numDroppedFrames` when
the batch script saves the `.mat` file.

Finally, there's a small safety check after the loop: if the video
turned out to be so short that the loop never reached the target middle
frame for the debug snapshot, the last frame processed is used instead,
so `debugFrame.image` is never left empty.
