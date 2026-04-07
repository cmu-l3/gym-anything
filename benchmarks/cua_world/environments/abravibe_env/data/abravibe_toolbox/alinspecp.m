function [Xrms, f, Phase] = alinspecp(x, fs, N, w, overlap)
% ALINSPECP   Calculate linear spectrum with phase (ABRAVIBE toolbox)
%   [Xrms, f, Phase] = alinspecp(x, fs, N, w, overlap)
%
%   Same as alinspec but also returns phase information.
%
%   Parameters:
%     x       - Time data vector (column)
%     fs      - Sampling frequency [Hz]
%     N       - Block size (FFT length)
%     w       - Window vector of length N
%     overlap - Overlap fraction (0 to 1), default 0.5
%
%   Returns:
%     Xrms  - RMS linear spectrum magnitude (N/2+1 x 1)
%     f     - Frequency axis [Hz] (N/2+1 x 1)
%     Phase - Phase in radians (N/2+1 x 1)
%
%   ABRAVIBE toolbox - Anders Brandt

    if nargin < 5
        overlap = 0.5;
    end

    x = x(:);
    w = w(:);

    nf = floor(N/2) + 1;
    step = round(N * (1 - overlap));
    nAvg = floor((length(x) - N) / step) + 1;

    if nAvg < 1
        error('alinspecp: data too short for given block size');
    end

    S1 = sum(w);

    XavgComplex = zeros(nf, 1);

    for k = 1:nAvg
        idx_start = (k-1)*step + 1;
        idx_end = idx_start + N - 1;
        xb = x(idx_start:idx_end) .* w;
        Xf = fft(xb);
        Xf = Xf(1:nf) / S1;
        XavgComplex = XavgComplex + Xf;
    end

    XavgComplex = XavgComplex / nAvg;

    Xrms = abs(XavgComplex);
    Xrms(2:end-1) = Xrms(2:end-1) * sqrt(2);

    Phase = angle(XavgComplex);

    f = makexaxis(fs, N, 'freq');
end
