function out = skinMaskExtract(frames, fs)
% SKINMASKEXTRACT Segment 23 Task 3: ONE video pass computing, per frame, mean RGB and the 3x3 uncentered pixel
% correlation matrix (the only pixel statistic 2SR consumes) for four pixel sets, using a REAL per-pixel skin/non-skin
% decision (Chai & Ngan 1999 YCbCr rule: 77<=Cb<=127, 133<=Cr<=173 on the JPEG/full-range YCbCr, plus 30<=Y<=245
% to drop black/blown-out pixels) rather than a fixed geometric box:
%   fbMask   : production forehead box   AND skin mask   (same region as Seg 22, non-skin removed)
%   fbUnmask : production forehead box, no mask          (parity with Seg 22 / production cache)
%   faceMask : whole detected face box   AND skin mask   (2SR's own preferred "skin pixels of the face" setting)
%   faceUnmask: whole detected face box, no mask         (isolates region-size from masking)
% If a frame's mask keeps fewer than 50 pixels, that frame falls back to the unmasked pixels of the same region
% (flagged in <set>.fallback so it is countable, never silent). Face detection cadence/fallbacks are copied verbatim
% from roi/extractROISignals.m (bit-identical forehead box).
detectEveryN = 5; minPix = 50;
faceDetector = vision.CascadeObjectDetector();
frames.CurrentTime = 0; N = frames.NumFrames;
names = {'fbMask', 'fbUnmask', 'faceMask', 'faceUnmask'};
for s = 1:4
    out.(names{s}) = struct('rgb', zeros(3, N), 'C', zeros(3, 3, N), 'n', zeros(1, N), 'skinFrac', ones(1, N), 'fallback', false(1, N));
end
lastGood = []; k = 0;
while hasFrame(frames)
    k = k + 1; if k > N, break, end
    img = readFrame(frames); [H, W, ~] = size(img);
    if mod(k - 1, detectEveryN) == 0
        bb = step(faceDetector, img);
        if isempty(bb), cur = lastGood; else, [~, j] = max(bb(:, 3) .* bb(:, 4)); cur = bb(j, :); lastGood = cur; end
    else
        cur = lastGood;
    end
    if isempty(cur), cur = [round(0.2 * W), round(0.2 * H), round(0.6 * W), round(0.6 * H)]; end
    fb = clampedBBox(cur(1), cur(2), cur(3), cur(4), 0.30, 0.70, 0.10, 0.30, W, H);
    fx1 = max(1, round(cur(1))); fy1 = max(1, round(cur(2))); fx2 = min(W, round(cur(1) + cur(3))); fy2 = min(H, round(cur(2) + cur(4)));
    regions = {img(fb(2):fb(2) + fb(4), fb(1):fb(1) + fb(3), :), img(fy1:fy2, fx1:fx2, :)};
    for rgn = 1:2
        V = double(reshape(regions{rgn}, [], 3));
        Y = 0.299 * V(:, 1) + 0.587 * V(:, 2) + 0.114 * V(:, 3);
        Cb = 128 - 0.168736 * V(:, 1) - 0.331264 * V(:, 2) + 0.5 * V(:, 3);
        Cr = 128 + 0.5 * V(:, 1) - 0.418688 * V(:, 2) - 0.081312 * V(:, 3);
        skin = Cb >= 77 & Cb <= 127 & Cr >= 133 & Cr <= 173 & Y >= 30 & Y <= 245;
        for masked = [true false]
            if rgn == 1 && masked, nm = 'fbMask'; elseif rgn == 1, nm = 'fbUnmask'; elseif masked, nm = 'faceMask'; else, nm = 'faceUnmask'; end
            P = V; fell = false;
            if masked
                if nnz(skin) >= minPix, P = V(skin, :); else, fell = true; end
            end
            n = size(P, 1);
            out.(nm).rgb(:, k) = mean(P, 1)'; out.(nm).C(:, :, k) = (P' * P) / n;
            out.(nm).n(k) = n; out.(nm).skinFrac(k) = nnz(skin) / size(V, 1); out.(nm).fallback(k) = fell;
        end
    end
end
if k < N
    for s = 1:4
        f = out.(names{s}); f.rgb = f.rgb(:, 1:k); f.C = f.C(:, :, 1:k); f.n = f.n(1:k); f.skinFrac = f.skinFrac(1:k); f.fallback = f.fallback(1:k); out.(names{s}) = f;
    end
end
out.fs = fs;
end

function bbox = clampedBBox(faceX, faceY, faceW, faceH, xLo, xHi, yLo, yHi, W, H)
x1 = max(1, round(faceX + xLo * faceW)); x2 = min(W, round(faceX + xHi * faceW));
y1 = max(1, round(faceY + yLo * faceH)); y2 = min(H, round(faceY + yHi * faceH));
bbox = [x1, y1, x2 - x1, y2 - y1];
end
