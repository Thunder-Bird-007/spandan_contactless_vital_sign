function out = s23_chain(R, G, B, fs, useWavelet)
% S23_CHAIN production Branch-1 chain (Segment 8 Action 7 default), unmodified production calls:
% [waveletDenoise] -> detrendSignal -> bandpassClean -> chrom/posCombine -> bandpassClean.
% out.chrom / out.pos are the final pulse signals fftHeartRate reads; out.green = filtered G.
if useWavelet
    Rw = waveletDenoise(R); Gw = waveletDenoise(G); Bw = waveletDenoise(B);
else
    Rw = R; Gw = G; Bw = B;
end
[Rd, ~] = detrendSignal(Rw); [Gd, ~] = detrendSignal(Gw); [Bd, ~] = detrendSignal(Bw);
[Rf, ~] = bandpassClean(Rd, fs); [Gf, ~] = bandpassClean(Gd, fs); [Bf, ~] = bandpassClean(Bd, fs);
out.chrom = bandpassClean(chromCombine(Rf, Gf, Bf, Rw, Gw, Bw), fs);
out.pos = bandpassClean(posCombine(Rf, Gf, Bf, fs, Rw, Gw, Bw), fs);
out.green = Gf;
out.Rw = Rw; out.Gw = Gw; out.Bw = Bw; out.Rf = Rf; out.Gf = Gf; out.Bf = Bf;
end
