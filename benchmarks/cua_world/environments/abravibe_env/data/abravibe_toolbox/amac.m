function MAC = amac(Phi1, Phi2)
% AMAC   Calculate Modal Assurance Criterion matrix (ABRAVIBE toolbox)
%   MAC = amac(Phi1, Phi2)
%
%   Computes the Modal Assurance Criterion (MAC) matrix between two sets
%   of mode shapes. MAC values range from 0 (uncorrelated) to 1 (identical).
%
%   Parameters:
%     Phi1 - First mode shape matrix (n x m1), columns are mode shapes
%     Phi2 - Second mode shape matrix (n x m2), columns are mode shapes
%
%   Returns:
%     MAC  - MAC matrix (m1 x m2)
%
%   MAC(i,j) = |Phi1(:,i)' * Phi2(:,j)|^2 / (|Phi1(:,i)|^2 * |Phi2(:,j)|^2)
%
%   ABRAVIBE toolbox - Anders Brandt

    m1 = size(Phi1, 2);
    m2 = size(Phi2, 2);
    MAC = zeros(m1, m2);

    for i = 1:m1
        for j = 1:m2
            num = abs(Phi1(:,i)' * Phi2(:,j))^2;
            den = (Phi1(:,i)' * Phi1(:,i)) * (Phi2(:,j)' * Phi2(:,j));
            if den > 0
                MAC(i,j) = num / den;
            end
        end
    end
end
