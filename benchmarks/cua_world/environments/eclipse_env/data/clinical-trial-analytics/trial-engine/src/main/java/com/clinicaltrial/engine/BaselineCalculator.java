package com.clinicaltrial.engine;

import com.clinicaltrial.model.DoseGroup;
import com.clinicaltrial.model.Patient;

import java.util.List;

/**
 * Computes baseline response values used for normalizing efficacy data.
 * Supports both per-group and population-level baseline calculations.
 */
public class BaselineCalculator {

    /**
     * Computes the mean response score for a single dose group.
     * Typically used for the control/placebo arm baseline.
     */
    public double computeGroupBaseline(DoseGroup group) {
        return group.getPatients().stream()
                .filter(p -> p.getOutcome() != null)
                .mapToDouble(p -> p.getOutcome().getResponseScore())
                .average()
                .orElse(0.0);
    }

    /**
     * Computes the population-wide median baseline across all dose groups.
     * Preferred for normalization when control group size is small or
     * when responses have high inter-group variance at baseline.
     */
    public double computePopulationBaseline(List<DoseGroup> groups) {
        double[] allScores = groups.stream()
                .flatMap(g -> g.getPatients().stream())
                .filter(p -> p.getOutcome() != null)
                .mapToDouble(p -> p.getOutcome().getResponseScore())
                .sorted()
                .toArray();

        if (allScores.length == 0) return 0.0;

        int mid = allScores.length / 2;
        if (allScores.length % 2 == 0) {
            return (allScores[mid - 1] + allScores[mid]) / 2.0;
        } else {
            return allScores[mid];
        }
    }
}
