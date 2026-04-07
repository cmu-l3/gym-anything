function [Gxx, f] = apsd(x, fs, N, w, overlap)
% APSD   Calculate power spectral density (PSD) from time data (ABRAVIBE toolbox)
%   [Gxx, f] = apsd(x, fs, N, w, overlap)
%
%   Computes one-sided power spectral density using Welch's method with
%   windowing and overlap averaging.
%
%   Parameters:
%     x       - Time data vector (column)
%     fs      - Sampling frequency [Hz]
%     N       - Block size (FFT length)
%     w       - Window vector of length N (e.g., ahann(N))
%     overlap - Overlap fraction (0 to 1), default 0.5
%
%   Returns:
%     Gxx     - One-sided PSD [(unit)^2/Hz] (N/2+1 x 1)
%     f       - Frequency axis [Hz] (N/2+1 x 1)
%
%   ABRAVIBE toolbox - Anders Brandt
%   Noise and Vibration Analysis, Wiley 2011

    if nargin < 5
        overlap = 0.5;
    end

    x = x(:);
    w = w(:);

    % Number of output frequency lines
    nf = floor(N/2) + 1;

    % Step size
    step = round(N * (1 - overlap));

    % Number of averages
    nAvg = floor((length(x) - N) / step) + 1;

    if nAvg < 1
        error('apsd: data too short for given block size');
    end

    % Window power correction factor
    S2 = sum(w.^2);

    % Frequency resolution
    df = fs / N;

    Gxx = zeros(nf, 1);

    for k = 1:nAvg
        idx_start = (k-1)*step + 1;
        idx_end = idx_start + N - 1;
        xb = x(idx_start:idx_end) .* w;
        Xf = fft(xb);
        Xf = Xf(1:nf);
        % Accumulate periodogram
        Gxx = Gxx + abs(Xf).^2;
    end

    % Average and scale to PSD
    % PSD = |X|^2 / (fs * S2 * nAvg)
    Gxx = Gxx / (fs * S2 * nAvg);

    % One-sided: multiply by 2 for all except DC and Nyquist
    Gxx(2:end-1) = 2 * Gxx(2:end-1);

    % Frequency axis
    f = makexaxis(fs, N, 'freq');
end
