function x = makexaxis(x_or_fs, N, type)
% MAKEXAXIS   Create a time or frequency x axis (ABRAVIBE toolbox)
%   x = makexaxis(fs, N, 'freq') returns a frequency axis from 0 to fs/2
%       with N/2+1 linearly spaced points.
%   x = makexaxis(fs, N, 'time') returns a time axis from 0 to (N-1)/fs
%       with N linearly spaced points.
%   x = makexaxis(fs, N) defaults to 'freq'.
%
%   Parameters:
%     fs   - Sampling frequency [Hz]
%     N    - Block size (number of samples)
%     type - 'freq' (default) or 'time'
%
%   ABRAVIBE toolbox - Anders Brandt

    if nargin < 3
        type = 'freq';
    end

    fs = x_or_fs;

    if strcmpi(type, 'freq')
        df = fs / N;
        nf = floor(N/2) + 1;
        x = (0:nf-1)' * df;
    elseif strcmpi(type, 'time')
        dt = 1 / fs;
        x = (0:N-1)' * dt;
    else
        error('makexaxis: type must be ''freq'' or ''time''');
    end
end
