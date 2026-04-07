function [MIF, f] = amif(H, f)
% AMIF   Calculate Mode Indicator Function from FRFs (ABRAVIBE toolbox)
%   [MIF, f] = amif(H, f)
%
%   Computes the Mode Indicator Function (MIF) from accelerance FRFs.
%   MIF approaches zero at natural frequencies, making it useful for
%   identifying modal peaks.
%
%   If H is a matrix (nf x nFRFs), the multivariate MIF is computed
%   as the minimum eigenvalue of the real part of the FRF matrix at
%   each frequency. For a single FRF, MIF = real(H)^2 / |H|^2.
%
%   Parameters:
%     H - Complex FRF data (nf x nFRFs)
%     f - Frequency vector [Hz] (nf x 1)
%
%   Returns:
%     MIF - Mode Indicator Function (nf x 1)
%     f   - Frequency vector [Hz]
%
%   ABRAVIBE toolbox - Anders Brandt

    [nf, nFRFs] = size(H);

    MIF = zeros(nf, 1);

    if nFRFs == 1
        % Single FRF: simplified MIF
        for k = 1:nf
            magSq = abs(H(k))^2;
            if magSq > 0
                MIF(k) = real(H(k))^2 / magSq;
            end
        end
    else
        % Multiple FRFs: eigenvalue-based MIF
        for k = 1:nf
            Hk = H(k, :).';
            Rk = real(Hk * Hk');
            Ik = Hk * Hk';
            magSq = abs(diag(Ik));
            if any(magSq > 0)
                MIF(k) = min(real(diag(Rk)) ./ max(magSq, eps));
            end
        end
    end
end
