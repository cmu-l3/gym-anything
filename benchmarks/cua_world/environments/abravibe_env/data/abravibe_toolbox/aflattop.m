function w = aflattop(N)
% AFLATTOP   Flat-top window (ABRAVIBE toolbox)
%   w = aflattop(N) returns an N-point flat-top window as a column vector.
%
%   The flat-top window provides very accurate amplitude measurements at the
%   expense of frequency resolution. Used for calibration and amplitude-critical
%   spectrum analysis.
%
%   Coefficients from ISO 18431-2 (HFT95 window):
%     a0=1, a1=1.93, a2=1.29, a3=0.388, a4=0.0322
%
%   ABRAVIBE toolbox - Anders Brandt

    a0 = 1;
    a1 = 1.93;
    a2 = 1.29;
    a3 = 0.388;
    a4 = 0.0322;

    n = (0:N-1)';
    w = a0 - a1*cos(2*pi*n/(N-1)) + a2*cos(4*pi*n/(N-1)) ...
       - a3*cos(6*pi*n/(N-1)) + a4*cos(8*pi*n/(N-1));

    % Normalize so that max value is 1
    w = w / max(w);
end
