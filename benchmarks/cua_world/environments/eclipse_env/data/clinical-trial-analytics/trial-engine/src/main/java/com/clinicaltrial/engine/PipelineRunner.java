package com.clinicaltrial.engine;

import com.clinicaltrial.model.*;

import java.util.ArrayList;
import java.util.List;

/**
 * Orchestrates the end-to-end analysis pipeline:
 * raw patient data -> eligibility filtering -> statistical analysis -> trial summary.
 */
public class PipelineRunner {

    private final PatientFilter filter;
    private final StatisticalAnalyzer analyzer;

    public PipelineRunner() {
        this.filter = new PatientFilter();
        this.analyzer = new StatisticalAnalyzer();
    }

    /**
     * Runs the full analysis pipeline and returns a TrialSummary.
     *
     * @param config trial configuration with eligibility criteria
     * @param groups list of dose groups with enrolled patients
     * @return summary of the trial analysis
     */
    public TrialSummary runPipeline(TrialConfig config, List<DoseGroup> groups) {
        // Step 1: Collect all patients across groups
        List<Patient> allPatients = new ArrayList<>();
        for (DoseGroup g : groups) {
            allPatients.addAll(g.getPatients());
        }

        // Step 2: Filter eligible patients
        List<Patient> eligible = filter.filterEligible(allPatients, config);

        // Step 3: Re-build dose groups with only eligible patients
        List<DoseGroup> filteredGroups = new ArrayList<>();
        for (DoseGroup original : groups) {
            DoseGroup filtered = new DoseGroup(original.getGroupName(), original.getDoseAmountMg());
            for (Patient p : eligible) {
                if (p.getDoseGroup().equals(original.getGroupName())) {
                    filtered.addPatient(p);
                }
            }
            if (!filtered.getPatients().isEmpty()) {
                filteredGroups.add(filtered);
            }
        }

        // Step 4: Compute efficacy
        double efficacy = analyzer.computeEfficacy(eligible);

        // Step 5: Fit dose-response curve
        double ec50 = 0.0;
        if (filteredGroups.size() >= 3) {
            ec50 = analyzer.fitDoseResponseCurve(filteredGroups);
        }

        // Step 6: Compute confidence interval (simplified: +/- 10% of mean)
        double ciHalfWidth = efficacy * 0.10;

        // Step 7: Build summary
        return new TrialSummary.Builder()
                .trialId(config.getTrialId())
                .sampleSize(eligible.size())
                .meanEfficacy(efficacy)
                .ciLower(efficacy - ciHalfWidth)
                .ciUpper(efficacy + ciHalfWidth)
                .primaryEndpoint("Response Score")
                .build();
    }
}
