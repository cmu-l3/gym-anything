package com.clinicaltrial.engine;

import com.clinicaltrial.model.*;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

class StatisticalAnalyzerTest {

    @Test
    void testBasicEfficacy() {
        // All patients have valid outcomes — no edge cases
        List<Patient> patients = List.of(
                new Patient("PT-1", "A", 40, ConsentStatus.ACTIVE, 24, "G1", 10.0,
                        new Outcome(50.0, 0, "COMPLETE"), List.of()),
                new Patient("PT-2", "B", 45, ConsentStatus.ACTIVE, 24, "G1", 10.0,
                        new Outcome(60.0, 1, "COMPLETE"), List.of()),
                new Patient("PT-3", "C", 50, ConsentStatus.ACTIVE, 24, "G2", 25.0,
                        new Outcome(70.0, 0, "COMPLETE"), List.of())
        );

        StatisticalAnalyzer analyzer = new StatisticalAnalyzer();
        double efficacy = analyzer.computeEfficacy(patients);

        assertEquals(60.0, efficacy, 0.001,
                "Mean efficacy of [50, 60, 70] should be 60.0");
    }

    @Test
    void testEdgeCasePatients() {
        // Mix of completed patients and patients at exactly minWeeks with null outcomes.
        // If the filter is correct (using > not >=), only completed patients reach here.
        // If the filter is buggy (using >=), null-outcome patients slip through and
        // computeEfficacy will throw a NullPointerException.
        PatientFilter filter = new PatientFilter();
        TrialConfig config = new TrialConfig("TEST", 18, 75, 12, List.of());

        List<Patient> patients = new ArrayList<>();
        patients.add(new Patient("PT-A", "Completed1", 40, ConsentStatus.ACTIVE, 24, "G1", 10.0,
                new Outcome(55.0, 0, "COMPLETE"), List.of()));
        patients.add(new Patient("PT-B", "Completed2", 50, ConsentStatus.ACTIVE, 18, "G1", 10.0,
                new Outcome(65.0, 1, "COMPLETE"), List.of()));
        // These patients are at exactly minWeeks=12 with null outcome
        patients.add(new Patient("PT-C", "Pending1", 35, ConsentStatus.ACTIVE, 12, "G1", 10.0,
                null, List.of()));
        patients.add(new Patient("PT-D", "Pending2", 42, ConsentStatus.ACTIVE, 12, "G2", 25.0,
                null, List.of()));

        List<Patient> eligible = filter.filterEligible(patients, config);

        StatisticalAnalyzer analyzer = new StatisticalAnalyzer();
        // This should NOT throw NPE — null-outcome patients must have been filtered out
        double efficacy = analyzer.computeEfficacy(eligible);

        assertEquals(60.0, efficacy, 0.001,
                "Efficacy should be mean of [55.0, 65.0] = 60.0 (pending patients excluded)");
    }
}
