function [Gxy, f] = acsd(x, y, fs, N, w, overlap)
% ACSD   Calculate cross spectral density (CSD) from time data (ABRAVIBE toolbox)
%   [Gxy, f] = acsd(x, y, fs, N, w, overlap)
%
%   Computes one-sided cross spectral density using Welch's method.
%
%   Parameters:
%     x       - Input time data vector (column)
%     y       - Output time data vector (column)
%     fs      - Sampling frequency [Hz]
%     N       - Block size (FFT length)
%     w       - Window vector of length N
%     overlap - Overlap fraction (0 to 1), default 0.5
%
%   Returns:
%     Gxy     - One-sided CSD (complex) (N/2+1 x 1)
%     f       - Frequency axis [Hz] (N/2+1 x 1)
%
%   ABRAVIBE toolbox - Anders Brandt

    if nargin < 6
        overlap = 0.5;
    end

    x = x(:);
    y = y(:);
    w = w(:);

    nf = floor(N/2) + 1;
    step = round(N * (1 - overlap));
    nAvg = floor((min(length(x), length(y)) - N) / step) + 1;

    if nAvg < 1
        error('acsd: data too short for given block size');
    end

    S2 = sum(w.^2);

    Gxy = zeros(nf, 1);

    for k = 1:nAvg
        idx_start = (k-1)*step + 1;
        idx_end = idx_start + N - 1;
        xb = x(idx_start:idx_end) .* w;
        yb = y(idx_start:idx_end) .* w;
        Xf = fft(xb);
        Yf = fft(yb);
        Xf = Xf(1:nf);
        Yf = Yf(1:nf);
        Gxy = Gxy + conj(Xf) .* Yf;
    end

    Gxy = Gxy / (fs * S2 * nAvg);
    Gxy(2:end-1) = 2 * Gxy(2:end-1);

    f = makexaxis(fs, N, 'freq');
end
