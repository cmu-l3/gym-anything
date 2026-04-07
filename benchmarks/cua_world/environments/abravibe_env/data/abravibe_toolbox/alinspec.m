function [Xrms, f] = alinspec(x, fs, N, w, overlap)
% ALINSPEC   Calculate linear (RMS) spectrum from time data (ABRAVIBE toolbox)
%   [Xrms, f] = alinspec(x, fs, N, w, overlap)
%
%   Computes the linear, RMS-scaled spectrum using Welch's method with
%   windowing and overlap. The result is a one-sided linear spectrum.
%
%   Parameters:
%     x       - Time data vector (column)
%     fs      - Sampling frequency [Hz]
%     N       - Block size (FFT length)
%     w       - Window vector of length N (e.g., ahann(N))
%     overlap - Overlap fraction (0 to 1), default 0.5
%
%   Returns:
%     Xrms    - RMS linear spectrum (N/2+1 x 1)
%     f       - Frequency axis (N/2+1 x 1)
%
%   ABRAVIBE toolbox - Anders Brandt

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
        error('alinspec: data too short for given block size');
    end

    % Window energy correction factor for RMS scaling
    S1 = sum(w);

    Xrms = zeros(nf, 1);

    for k = 1:nAvg
        idx_start = (k-1)*step + 1;
        idx_end = idx_start + N - 1;
        xb = x(idx_start:idx_end) .* w;
        Xf = fft(xb);
        Xf = Xf(1:nf);
        % RMS scaling: divide by sum of window
        Xf = Xf / S1;
        % Accumulate magnitude
        Xrms = Xrms + abs(Xf);
    end

    % Average
    Xrms = Xrms / nAvg;

    % Scale for one-sided: multiply by sqrt(2) for all except DC and Nyquist
    Xrms(2:end-1) = Xrms(2:end-1) * sqrt(2);

    % Frequency axis
    f = makexaxis(fs, N, 'freq');
end
