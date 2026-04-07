function w = ahann(N)
% AHANN   Hanning window (ABRAVIBE toolbox)
%   w = ahann(N) returns an N-point Hanning (von Hann) window as a column vector.
%
%   The Hanning window is defined as:
%     w(n) = 0.5 * (1 - cos(2*pi*n / (N-1))),  n = 0, 1, ..., N-1
%
%   ABRAVIBE toolbox - Anders Brandt
%   Noise and Vibration Analysis, Wiley 2011

    n = (0:N-1)';
    w = 0.5 * (1 - cos(2*pi*n / (N-1)));
end
