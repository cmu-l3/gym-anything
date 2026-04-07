function [H, f, Coh] = afrf(x, y, fs, N, w, overlap, estimator)
% AFRF   Estimate frequency response function from time data (ABRAVIBE toolbox)
%   [H, f, Coh] = afrf(x, y, fs, N, w, overlap, estimator)
%
%   Estimates the FRF H(f) = Y(f)/X(f) using H1 or H2 estimator with
%   Welch's method for spectral averaging.
%
%   Parameters:
%     x         - Input (excitation) time data
%     y         - Output (response) time data
%     fs        - Sampling frequency [Hz]
%     N         - Block size (FFT length)
%     w         - Window vector of length N
%     overlap   - Overlap fraction (0 to 1), default 0.5
%     estimator - 'H1' (default) or 'H2'
%
%   Returns:
%     H   - Complex FRF estimate (N/2+1 x 1)
%     f   - Frequency axis [Hz]
%     Coh - Ordinary coherence function gamma^2 (N/2+1 x 1)
%
%   H1 = Gxy / Gxx  (minimizes noise on output)
%   H2 = Gyy / Gyx  (minimizes noise on input)
%   Coherence = |Gxy|^2 / (Gxx * Gyy)
%
%   ABRAVIBE toolbox - Anders Brandt

    if nargin < 7
        estimator = 'H1';
    end
    if nargin < 6
        overlap = 0.5;
    end

    [Gxx, f] = apsd(x, fs, N, w, overlap);
    [Gyy, ~] = apsd(y, fs, N, w, overlap);
    [Gxy, ~] = acsd(x, y, fs, N, w, overlap);
    [Gyx, ~] = acsd(y, x, fs, N, w, overlap);

    if strcmpi(estimator, 'H1')
        H = Gxy ./ Gxx;
    elseif strcmpi(estimator, 'H2')
        H = Gyy ./ Gyx;
    else
        error('afrf: estimator must be ''H1'' or ''H2''');
    end

    % Ordinary coherence
    Coh = abs(Gxy).^2 ./ (Gxx .* Gyy);
    % Clip to [0, 1] to handle numerical issues
    Coh = min(max(Coh, 0), 1);
end
