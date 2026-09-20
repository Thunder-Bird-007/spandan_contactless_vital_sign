function [aStar, Cb, Cr, Lstar] = labFromSumNorm(R, G, B)
% LABFROMSUMNORM The colour transform of Yang et al. 2016 (PMC5995145), NOT a library rgb2lab:
%   Rnorm = R/(R+G+B) etc. (per-frame sum normalisation, cancels intensity)      [paper text]
%   [X;Y;Z] = M [Rnorm;Gnorm;Bnorm], M = [0.431 0.342 0.178; 0.222 0.707 0.071; 0.020 0.130 0.939]   [Eq. 2]
%   L*=116 f(Y/Yn)-16, a*=500[f(X/Xn)-f(Y/Yn)], b*=200[f(Y/Yn)-f(Z/Zn)],
%   f(t)=t^(1/3) for t>0.008856 else 7.787 t + 16/116   [Eqs. 3-5, standard CIELab]
% The paper states only "CIE standard illuminant D65" for (Xn,Yn,Zn) without numbers; the white of THIS matrix
% (RGB=(1,1,1)) is used, i.e. Xn,Yn,Zn = row sums of M = [0.951 1.000 1.089] (the D65 white). Because the input
% is sum-normalised (RGB sums to 1) all of X,Y,Z are ~1/3 of that white; a*'s overall scale is irrelevant to an
% FFT peak. Cb/Cr: BT.601 full-range chroma of the SAME sum-normalised RGB (offset dropped).
M = [0.431 0.342 0.178; 0.222 0.707 0.071; 0.020 0.130 0.939];
s = R(:)' + G(:)' + B(:)';
Rn = R(:)' ./ s; Gn = G(:)' ./ s; Bn = B(:)' ./ s;
XYZ = M * [Rn; Gn; Bn];
wn = sum(M, 2);
fx = f(XYZ(1, :) / wn(1)); fy = f(XYZ(2, :) / wn(2)); fz = f(XYZ(3, :) / wn(3));
Lstar = 116 * fy - 16; aStar = 500 * (fx - fy);
Cb = -0.168736 * Rn - 0.331264 * Gn + 0.5 * Bn;
Cr = 0.5 * Rn - 0.418688 * Gn - 0.081312 * Bn;
end
function y = f(t)
y = zeros(size(t)); m = t > 0.008856;
y(m) = t(m) .^ (1 / 3); y(~m) = 7.787 * t(~m) + 16 / 116;
end
