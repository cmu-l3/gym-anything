function y = timeint(x, fs, fc)
% TIMEINT   Time domain integration with optional high-pass filter (ABRAVIBE toolbox)
%   y = timeint(x, fs, fc)
%
%   Integrates a time signal (e.g., acceleration to velocity, or velocity
%   to displacement) using cumulative trapezoidal integration with an
%   optional high-pass filter to remove DC drift.
%
%   Parameters:
%     x  - Input time data vector
%     fs - Sampling frequency [Hz]
%     fc - High-pass cutoff frequency [Hz] for drift removal (optional)
%          If not specified, no filtering is applied.
%
%   Returns:
%     y  - Integrated signal
%
%   ABRAVIBE toolbox - Anders Brandt

    x = x(:);
    dt = 1 / fs;

    % Trapezoidal integration
    y = cumtrapz(x) * dt;

    % Optional high-pass filtering to remove DC drift
    if nargin >= 3 && fc > 0
        % 2nd order Butterworth high-pass filter
        Wn = fc / (fs/2);
        if Wn > 0 && Wn < 1
            [b, a] = butter(2, Wn, 'high');
            y = filtfilt(b, a, y);
        end
    end
end
