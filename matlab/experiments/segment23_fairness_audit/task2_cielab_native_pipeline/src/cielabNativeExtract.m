function out = cielabNativeExtract(frames, fs)
% CIELABNATIVEEXTRACT Segment 23 Task 2: ONE video pass producing everything needed to evaluate the CIELab a*
% pipeline of Yang, Liu, Yu, Shao, Tsow & Tao (J. Biomed. Opt. 21(11):117001, 2016; PMC5995145) in its native
% form, plus the "as originally tested" (Segment 18) fixed-forehead-box per-pixel traces as a byproduct.
%
% Native components implemented (from the paper's own text, fetched this session):
%  (i)  UNIFORMITY-RANKED ROI. The paper tiles the face into 22x15 cells ("20x20 pixels each" at its 480x640
%       video), scores each cell by roughness r = mu/sigma (mean over std of the intensity), and picks a
%       "region of 120x80 pixels ... from the forehead as the optimal ROI" (= 6x4 cells). NOTE: the Segment 23
%       brief described 120x80 px CELLS; the paper's cells are 20x20 and 120x80 is the SELECTED ROI (6x4 cells).
%       Our videos are not 480x640, so the 22x15 grid is laid over the detected face box (cells = faceW/22 x
%       faceH/15); the 6x4-cell window (27% x 27% of the face box, the same fraction as 120x80 of the paper's
%       440x300 tiled area) is searched over the top 6 cell-rows (forehead) and scored by mean cell r.
%  (ii) KLT tracking: Shi-Tomasi features (detectMinEigenFeatures) tracked with vision.PointTracker; ROI is
%       translated by the median feature displacement; features re-initialised every 900 frames (paper) and
%       -- our safeguard, not in the paper -- if fewer than 10 tracked points survive. A frame is PRUNED when
%       more than 30% of the tracked points are lost in that frame (paper: "frames with loss over 30% of the
%       feature points are pruned"; we read this as per-frame loss, the paper does not say cumulative).
% (iii) The colour transform itself is applied later from the saved raw ROI means (see run_task2_eval.m).
%
% Also saved (byproduct for Task 5, same decode): forehead-box traces identical to production R/G/B, and the
% Segment 18 form of a*/Cb/Cr (rgb2lab / rgb2ycbcr per PIXEL, then averaged) on that same box.
%
% Face detection cadence/fallbacks are copied verbatim from roi/extractROISignals.m so the forehead box (and
% R/G/B) is bit-identical to the production cache (checked by the batch script).
detectEveryN = 5; reinitEvery = 900; lossThresh = 0.30; minPts = 10; maxPts = 100;
faceDetector = vision.CascadeObjectDetector();
frames.CurrentTime = 0; N = frames.NumFrames;
boxRGB = zeros(3, N); boxLab = zeros(3, N);            % rows: [a*; Cb; Cr] per-pixel-mean (Seg 18 form)
roiRGB = nan(3, N); keep = true(1, N); lossFrac = zeros(1, N); nAlive = zeros(1, N); roiRect = nan(4, N);
lastGood = []; frameIdx = 0; tracker = []; curPts = []; refPts = []; roi0 = []; sinceInit = 0; initFrames = [];
trackerOK = false; roiScoreAtInit = [];
while hasFrame(frames)
    frameIdx = frameIdx + 1; if frameIdx > N, break, end
    img = readFrame(frames); [H, W, ~] = size(img);
    if mod(frameIdx - 1, detectEveryN) == 0
        bb = step(faceDetector, img);
        if isempty(bb), cur = lastGood; else, [~, k] = max(bb(:, 3) .* bb(:, 4)); cur = bb(k, :); lastGood = cur; end
    else
        cur = lastGood;
    end
    if isempty(cur), cur = [round(0.2 * W), round(0.2 * H), round(0.6 * W), round(0.6 * H)]; end
    % ---- production forehead box (bit-identical R/G/B) + Segment-18-form per-pixel Lab/YCbCr ----
    fb = clampedBBox(cur(1), cur(2), cur(3), cur(4), 0.30, 0.70, 0.10, 0.30, W, H);
    patch = img(fb(2):fb(2) + fb(4), fb(1):fb(1) + fb(3), :);
    boxRGB(:, frameIdx) = [mean(double(reshape(patch(:, :, 1), [], 1))); mean(double(reshape(patch(:, :, 2), [], 1))); mean(double(reshape(patch(:, :, 3), [], 1)))];
    pd = im2double(patch); lab = rgb2lab(pd); ycc = rgb2ycbcr(pd);
    boxLab(:, frameIdx) = [mean(reshape(lab(:, :, 2), [], 1)); mean(reshape(ycc(:, :, 2), [], 1)); mean(reshape(ycc(:, :, 3), [], 1))];
    % ---- native pipeline ----
    gray = rgb2gray(img);
    needInit = isempty(tracker) || mod(frameIdx - 1, reinitEvery) == 0 || (trackerOK && numel(curPts) / 2 < minPts) || ~trackerOK && mod(frameIdx - 1, detectEveryN) == 0;
    if needInit
        [roi0, sc] = selectUniformROI(gray, cur);
        cx = max(1, round(cur(1))); cy = max(1, round(cur(2)));
        fr = [cx, cy, min(cur(3), W - cx), min(cur(4), H - cy)];
        pts = detectMinEigenFeatures(gray, 'ROI', fr);
        pts = pts.selectStrongest(min(maxPts, pts.Count));
        if ~isempty(tracker) && isLocked(tracker), release(tracker); end
        if pts.Count >= minPts
            tracker = vision.PointTracker('MaxBidirectionalError', 2);
            initialize(tracker, pts.Location, gray);
            curPts = pts.Location; refPts = curPts; trackerOK = true;
        else
            tracker = []; curPts = []; refPts = []; trackerOK = false;
        end
        roiScoreAtInit(end + 1) = sc; initFrames(end + 1) = frameIdx; %#ok<AGROW>
        sinceInit = 0; lossFrac(frameIdx) = 0; disp0 = [0 0];
    else
        sinceInit = sinceInit + 1;
        if trackerOK
            [p, v] = step(tracker, gray);
            lossFrac(frameIdx) = nnz(~v) / numel(v);
            refPts = refPts(v, :); curPts = p(v, :);
            if size(curPts, 1) >= 1, setPoints(tracker, curPts); end
            if size(curPts, 1) >= minPts, disp0 = median(curPts - refPts, 1); else, disp0 = [0 0]; trackerOK = false; keep(frameIdx) = false; end
            if lossFrac(frameIdx) > lossThresh, keep(frameIdx) = false; end
        else
            disp0 = [0 0]; lossFrac(frameIdx) = NaN;
        end
    end
    nAlive(frameIdx) = size(curPts, 1);
    rx = round(roi0(1) + disp0(1)); ry = round(roi0(2) + disp0(2)); rw = roi0(3); rh = roi0(4);
    rx = min(max(1, rx), max(1, W - rw)); ry = min(max(1, ry), max(1, H - rh));
    rp = img(ry:min(H, ry + rh - 1), rx:min(W, rx + rw - 1), :);
    roiRGB(:, frameIdx) = [mean(double(reshape(rp(:, :, 1), [], 1))); mean(double(reshape(rp(:, :, 2), [], 1))); mean(double(reshape(rp(:, :, 3), [], 1)))];
    roiRect(:, frameIdx) = [rx; ry; rw; rh];
end
if frameIdx < N
    boxRGB = boxRGB(:, 1:frameIdx); boxLab = boxLab(:, 1:frameIdx); roiRGB = roiRGB(:, 1:frameIdx);
    keep = keep(1:frameIdx); lossFrac = lossFrac(1:frameIdx); nAlive = nAlive(1:frameIdx); roiRect = roiRect(:, 1:frameIdx);
end
out = struct('fs', fs, 'boxRGB', boxRGB, 'boxLab', boxLab, 'roiRGB', roiRGB, 'keep', keep, 'lossFrac', lossFrac, ...
    'nAlive', nAlive, 'roiRect', roiRect, 'initFrames', initFrames, 'roiScoreAtInit', roiScoreAtInit);
end

function [roi, bestScore] = selectUniformROI(gray, faceBox)
% 22x15 cell grid over the face box; r = mean/std per cell; best 6x4-cell window in the top 6 cell rows.
[H, W] = size(gray);
x0 = max(1, faceBox(1)); y0 = max(1, faceBox(2));
fw = min(faceBox(3), W - x0); fh = min(faceBox(4), H - y0);
cw = fw / 22; ch = fh / 15; r = zeros(15, 22);
g = double(gray);
for i = 1:15
    for j = 1:22
        xs = round(x0 + (j - 1) * cw); xe = max(xs, round(x0 + j * cw) - 1);
        ys = round(y0 + (i - 1) * ch); ye = max(ys, round(y0 + i * ch) - 1);
        c = g(ys:min(H, ye), xs:min(W, xe)); sd = std(c(:));
        r(i, j) = mean(c(:)) / max(sd, 1e-3);
    end
end
bestScore = -inf; bi = 1; bj = 1;
for i = 1:3
    for j = 1:17
        s = mean(mean(r(i:i + 3, j:j + 5)));
        if s > bestScore, bestScore = s; bi = i; bj = j; end
    end
end
rx = round(x0 + (bj - 1) * cw); ry = round(y0 + (bi - 1) * ch);
roi = [rx, ry, max(4, round(6 * cw)), max(4, round(4 * ch))];
end

function bbox = clampedBBox(faceX, faceY, faceW, faceH, xLo, xHi, yLo, yHi, W, H)
x1 = max(1, round(faceX + xLo * faceW)); x2 = min(W, round(faceX + xHi * faceW));
y1 = max(1, round(faceY + yLo * faceH)); y2 = min(H, round(faceY + yHi * faceH));
bbox = [x1, y1, x2 - x1, y2 - y1];
end
