package com.clinicaltrial.engine;

import com.clinicaltrial.model.*;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

class DoseResponseCurveTest {

    /**
     * Creates a realistic set of dose groups with a clear dose-response signal.
     * Control group has very low response (~0.003), treatment groups scale up.
     * This tests that the normalization and curve fitting produce sane values.
     */
    private List<DoseGroup> createRealisticDoseGroups() {
        List<DoseGroup> groups = new ArrayList<>();

        // Control group (placebo) — very low residual response
        DoseGroup control = new DoseGroup("Control", 0.0);
        control.addPatient(makePatient("C-01", "Control", 0.0, 0.002));
        control.addPatient(makePatient("C-02", "Control", 0.0, 0.004));
        control.addPatient(makePatient("C-03", "Control", 0.0, 0.003));
        groups.add(control);

        // Low dose (10mg)
        DoseGroup low = new DoseGroup("LowDose", 10.0);
        low.addPatient(makePatient("L-01", "LowDose", 10.0, 15.2));
        low.addPatient(makePatient("L-02", "LowDose", 10.0, 18.7));
        low.addPatient(makePatient("L-03", "LowDose", 10.0, 12.9));
        groups.add(low);

        // Medium dose (50mg)
        DoseGroup med = new DoseGroup("MedDose", 50.0);
        med.addPatient(makePatient("M-01", "MedDose", 50.0, 42.1));
        med.addPatient(makePatient("M-02", "MedDose", 50.0, 38.5));
        med.addPatient(makePatient("M-03", "MedDose", 50.0, 45.8));
        groups.add(med);

        // High dose (100mg)
        DoseGroup high = new DoseGroup("HighDose", 100.0);
        high.addPatient(makePatient("H-01", "HighDose", 100.0, 71.3));
        high.addPatient(makePatient("H-02", "HighDose", 100.0, 65.9));
        high.addPatient(makePatient("H-03", "HighDose", 100.0, 74.2));
        groups.add(high);

        return groups;
    }

    private Patient makePatient(String id, String group, double dose, double response) {
        return new Patient(id, "Patient " + id, 45, ConsentStatus.ACTIVE,
                24, group, dose,
                new Outcome(response, 0, "COMPLETE"), List.of());
    }

    @Test
    void testCurveFitAccuracy() {
        List<DoseGroup> groups = createRealisticDoseGroups();
        StatisticalAnalyzer analyzer = new StatisticalAnalyzer();

        // The normalized responses should reflect reasonable percent change from
        // a population-level baseline. With population median around ~30-40,
        // normalized values should be in the -100% to +200% range, not thousands.
        double[] normalized = analyzer.computeNormalizedResponses(groups);

        for (double val : normalized) {
            assertTrue(val > -200.0 && val < 500.0,
                    "Normalized response " + val + " is out of reasonable range. " +
                    "Check that the baseline calculation uses the population baseline, " +
                    "not a single group baseline that may be near zero.");
        }
    }

    @Test
    void testSigmoidShape() {
        DoseResponseCurve curve = new DoseResponseCurve();
        double[] doses = {1.0, 10.0, 25.0, 50.0, 100.0};
        double[] responses = {5.0, 20.0, 45.0, 70.0, 85.0};

        curve.fit(doses, responses);
        assertTrue(curve.isFitted());

        // EC50 should be somewhere in the middle dose range
        double ec50 = curve.getEc50();
        assertTrue(ec50 > 5.0 && ec50 < 80.0,
                "EC50 of " + ec50 + " is outside expected range for this dose-response data");
    }
}
