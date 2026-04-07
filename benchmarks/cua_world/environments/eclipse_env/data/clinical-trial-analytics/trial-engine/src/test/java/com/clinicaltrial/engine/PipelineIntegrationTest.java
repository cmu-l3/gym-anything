package com.clinicaltrial.engine;

import com.clinicaltrial.model.*;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

/**
 * End-to-end integration test for the analysis pipeline.
 * This test exercises the full chain: filter -> analyze -> summarize.
 * It will only pass when ALL bugs in the pipeline are fixed.
 */
class PipelineIntegrationTest {

    @Test
    void testEndToEndPipeline() {
        TrialConfig config = new TrialConfig(
                "ONCO-2024-DR7", 18, 75, 12, List.of("PRIOR_CHEMO"));

        List<DoseGroup> groups = buildTrialData();

        PipelineRunner pipeline = new PipelineRunner();
        TrialSummary summary = pipeline.runPipeline(config, groups);

        // Verify trial ID propagated
        assertEquals("ONCO-2024-DR7", summary.getTrialId());

        // Verify sample size is correct (not 0, not truncated)
        assertTrue(summary.getSampleSize() > 0,
                "Sample size must be positive — check that the Builder copies sampleSize");
        assertTrue(summary.getSampleSize() <= 20,
                "Sample size should reflect only eligible patients (not all enrolled)");

        // Verify efficacy is a reasonable positive number
        assertTrue(summary.getMeanEfficacy() > 0,
                "Mean efficacy must be positive for this trial data");
        assertTrue(summary.getMeanEfficacy() < 200,
                "Mean efficacy of " + summary.getMeanEfficacy() + " is unreasonably high — "
                + "check normalization baseline calculation");

        // Verify CI is valid
        assertTrue(summary.getCiLower() < summary.getCiUpper(),
                "Confidence interval must have lower < upper");
    }

    private List<DoseGroup> buildTrialData() {
        List<DoseGroup> groups = new ArrayList<>();

        // Control (placebo) — near-zero responses
        DoseGroup control = new DoseGroup("Control", 0.0);
        control.addPatient(makeCompleted("C-01", "Control", 0.0, 0.002));
        control.addPatient(makeCompleted("C-02", "Control", 0.0, 0.005));
        control.addPatient(makeCompleted("C-03", "Control", 0.0, 0.003));
        groups.add(control);

        // 10mg arm
        DoseGroup dose10 = new DoseGroup("Dose10", 10.0);
        dose10.addPatient(makeCompleted("D10-01", "Dose10", 10.0, 22.4));
        dose10.addPatient(makeCompleted("D10-02", "Dose10", 10.0, 18.9));
        dose10.addPatient(makeCompleted("D10-03", "Dose10", 10.0, 25.1));
        // Patient at exactly minWeeks=12 with null outcome (tests Bug 1)
        dose10.addPatient(makePending("D10-04", "Dose10", 10.0, 12));
        groups.add(dose10);

        // 50mg arm
        DoseGroup dose50 = new DoseGroup("Dose50", 50.0);
        dose50.addPatient(makeCompleted("D50-01", "Dose50", 50.0, 48.2));
        dose50.addPatient(makeCompleted("D50-02", "Dose50", 50.0, 41.7));
        dose50.addPatient(makeCompleted("D50-03", "Dose50", 50.0, 52.3));
        // Another pending patient at week 12
        dose50.addPatient(makePending("D50-04", "Dose50", 50.0, 12));
        groups.add(dose50);

        // 100mg arm
        DoseGroup dose100 = new DoseGroup("Dose100", 100.0);
        dose100.addPatient(makeCompleted("D100-01", "Dose100", 100.0, 73.5));
        dose100.addPatient(makeCompleted("D100-02", "Dose100", 100.0, 68.1));
        dose100.addPatient(makeCompleted("D100-03", "Dose100", 100.0, 76.9));
        groups.add(dose100);

        // Excluded patient (prior chemo)
        DoseGroup dose25 = new DoseGroup("Dose25", 25.0);
        dose25.addPatient(new Patient("EX-01", "Excluded", 55, ConsentStatus.ACTIVE,
                24, "Dose25", 25.0,
                new Outcome(35.0, 2, "COMPLETE"), List.of("PRIOR_CHEMO")));
        dose25.addPatient(makeCompleted("D25-01", "Dose25", 25.0, 33.4));
        dose25.addPatient(makeCompleted("D25-02", "Dose25", 25.0, 37.8));
        groups.add(dose25);

        return groups;
    }

    private Patient makeCompleted(String id, String group, double dose, double response) {
        return new Patient(id, "Patient " + id, 45, ConsentStatus.ACTIVE,
                24, group, dose,
                new Outcome(response, 0, "COMPLETE"), List.of());
    }

    private Patient makePending(String id, String group, double dose, int weeks) {
        return new Patient(id, "Patient " + id, 40, ConsentStatus.ACTIVE,
                weeks, group, dose,
                null, List.of());
    }
}
