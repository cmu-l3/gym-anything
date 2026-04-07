function [fn, zeta, Phi] = mck2modal(M, C, K)
% MCK2MODAL   Compute modal model from M, C, K matrices (ABRAVIBE toolbox)
%   [fn, zeta, Phi] = mck2modal(M, C, K)
%
%   Computes natural frequencies, damping ratios, and mode shapes from
%   mass, damping, and stiffness matrices. If C is empty or zero, undamped
%   analysis is performed.
%
%   Parameters:
%     M    - Mass matrix (n x n)
%     C    - Damping matrix (n x n), can be [] for undamped
%     K    - Stiffness matrix (n x n)
%
%   Returns:
%     fn   - Natural frequencies [Hz] (n x 1), sorted ascending
%     zeta - Damping ratios (n x 1), zero if undamped
%     Phi  - Mode shape matrix (n x n), columns are mode shapes
%
%   ABRAVIBE toolbox - Anders Brandt

    n = size(M, 1);

    if isempty(C) || all(C(:) == 0)
        % Undamped case: solve generalized eigenvalue problem K*phi = w^2*M*phi
        [V, D] = eig(K, M);
        omega2 = diag(D);
        [omega2, idx] = sort(real(omega2));
        V = V(:, idx);

        fn = sqrt(abs(omega2)) / (2*pi);
        zeta = zeros(n, 1);
        Phi = V;
    else
        % Damped case: state-space formulation
        % [C M; M 0] * qdot = [-K 0; 0 M] * q
        A = [zeros(n) eye(n); -M\K -M\C];
        [V, D] = eig(A);
        lambda = diag(D);

        % Select modes with positive imaginary part (conjugate pairs)
        idx = find(imag(lambda) > 0);
        [~, sortIdx] = sort(abs(lambda(idx)));
        idx = idx(sortIdx);

        if length(idx) < n
            % If not enough complex modes, also include real modes
            realIdx = find(imag(lambda) == 0 & real(lambda) < 0);
            idx = [idx; realIdx(1:min(n-length(idx), length(realIdx)))];
        end

        poles = lambda(idx(1:min(n,end)));

        fn = abs(poles) / (2*pi);
        zeta = -real(poles) ./ abs(poles);
        Phi = V(1:n, idx(1:min(n,end)));

        % Normalize mode shapes to unit mass
        for k = 1:size(Phi, 2)
            scale = sqrt(abs(Phi(:,k)' * M * Phi(:,k)));
            if scale > 0
                Phi(:,k) = Phi(:,k) / scale;
            end
        end
    end
end
