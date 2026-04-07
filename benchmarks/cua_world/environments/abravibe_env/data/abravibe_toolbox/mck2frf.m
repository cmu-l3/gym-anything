function [H, f] = mck2frf(M, C, K, f, inDof, outDof, respType)
% MCK2FRF   Calculate FRF(s) from M, C, K matrices (ABRAVIBE toolbox)
%   [H, freq] = mck2frf(M, C, K, f, inDof, outDof, respType)
%
%   Computes frequency response functions from mass, viscous damping, and
%   stiffness matrices by direct inversion at each frequency line.
%
%   Parameters:
%     M        - Mass matrix (n x n)
%     C        - Viscous damping matrix (n x n)
%     K        - Stiffness matrix (n x n)
%     f        - Frequency vector [Hz]
%     inDof    - Input DOF index (force application point)
%     outDof   - Output DOF index (response measurement point)
%     respType - Response type: 'd' (displacement/receptance),
%                'v' (velocity/mobility), 'a' (acceleration/accelerance)
%                Default: 'd'
%
%   Returns:
%     H    - Complex FRF vector (length(f) x 1)
%     f    - Frequency vector [Hz]
%
%   The FRF is computed as:
%     H_d(w) = [K - w^2*M + j*w*C]^{-1}   (receptance)
%     H_v(w) = j*w * H_d(w)                 (mobility)
%     H_a(w) = -w^2 * H_d(w)                (accelerance)
%
%   ABRAVIBE toolbox - Anders Brandt
%   Noise and Vibration Analysis, Wiley 2011

    if nargin < 7
        respType = 'd';
    end

    f = f(:);
    nf = length(f);
    omega = 2 * pi * f;

    n = size(M, 1);
    H = zeros(nf, 1);

    for k = 1:nf
        w = omega(k);
        % Dynamic stiffness matrix
        Z = K - w^2 * M + 1i * w * C;
        % Invert to get receptance matrix
        Hinv = Z \ eye(n);
        % Extract desired FRF
        Hd = Hinv(outDof, inDof);

        switch lower(respType)
            case 'd'
                H(k) = Hd;
            case 'v'
                H(k) = 1i * w * Hd;
            case 'a'
                H(k) = -w^2 * Hd;
            otherwise
                error('mck2frf: respType must be ''d'', ''v'', or ''a''');
        end
    end
end
