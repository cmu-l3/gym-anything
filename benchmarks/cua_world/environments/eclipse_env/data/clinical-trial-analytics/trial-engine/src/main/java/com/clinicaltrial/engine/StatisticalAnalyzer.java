package com.clinicaltrial.engine;

import com.clinicaltrial.model.DoseGroup;
import com.clinicaltrial.model.Patient;

import java.util.ArrayList;
import java.util.List;

/**
 * Core statistical analysis engine for dose-response clinical trial data.
 * Performs response normalization, curve fitting, and efficacy computation
 * in accordance with FDA guidance for dose-response studies (ICH E4).
 */
public class StatisticalAnalyzer {

    private final BaselineCalculator baselineCalc;
    private final DoseResponseCurve curveModel;

    public StatisticalAnalyzer() {
        this.baselineCalc = new BaselineCalculator();
        this.curveModel = new DoseResponseCurve();
    }

    /**
     * Computes normalized response values for all patients across dose groups.
     * Normalization formula: ((response - baseline) / baseline) * 100
     * This yields percent change from baseline for each observation.
     */
    public double[] computeNormalizedResponses(List<DoseGroup> groups) {
        double baseline = baselineCalc.computeGroupBaseline(groups.get(0));

        List<Double> normalized = new ArrayList<>();
        for (DoseGroup group : groups) {
            for (Patient p : group.getPatients()) {
                if (p.getOutcome() != null) {
                    double raw = p.getOutcome().getResponseScore();
                    normalized.add(((raw - baseline) / baseline) * 100.0);
                }
            }
        }
        return normalized.stream().mapToDouble(Double::doubleValue).toArray();
    }

    /**
     * Computes per-group mean normalized responses and fits the dose-response curve.
     * Returns the fitted EC50 value.
     */
    public double fitDoseResponseCurve(List<DoseGroup> groups) {
        double baseline = baselineCalc.computeGroupBaseline(groups.get(0));

        double[] doses = new double[groups.size()];
        double[] meanResponses = new double[groups.size()];

        for (int i = 0; i < groups.size(); i++) {
            DoseGroup g = groups.get(i);
            doses[i] = g.getDoseAmountMg();

            double groupMean = g.getPatients().stream()
                    .filter(p -> p.getOutcome() != null)
                    .mapToDouble(p -> p.getOutcome().getResponseScore())
                    .average()
                    .orElse(0.0);

            meanResponses[i] = ((groupMean - baseline) / baseline) * 100.0;
        }

        curveModel.fit(doses, meanResponses);
        return curveModel.getEc50();
    }

    /**
     * Computes the overall mean efficacy score from eligible patient outcomes.
     * Efficacy is the average response score across all patients with valid outcomes.
     */
    public double computeEfficacy(List<Patient> eligiblePatients) {
        double sum = 0.0;
        int count = 0;
        for (Patient p : eligiblePatients) {
            sum += p.getOutcome().getResponseScore();
            count++;
        }
        return count > 0 ? sum / count : 0.0;
    }

    public DoseResponseCurve getCurveModel() {
        return curveModel;
    }
}
