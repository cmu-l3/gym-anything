package com.clinicaltrial.engine;

import com.clinicaltrial.model.*;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

class PatientFilterTest {

    private PatientFilter filter;
    private TrialConfig config;

    @BeforeEach
    void setUp() {
        filter = new PatientFilter();
        config = new TrialConfig("TEST-001", 18, 75, 12,
                List.of("PRIOR_CHEMO", "RENAL_IMPAIRMENT"));
    }

    @Test
    void testExcludesIncompletePatients() {
        // Patients at exactly minWeeks (12) have NOT completed their final assessment.
        // Their outcomes are still pending (null). The filter must exclude them.
        List<Patient> patients = new ArrayList<>();

        // Completed patient (week 24) — should be included
        patients.add(new Patient("PT-001", "Alice", 45, ConsentStatus.ACTIVE,
                24, "Group1", 10.0,
                new Outcome(42.3, 0, "COMPLETE"), List.of()));

        // Patient at exactly week 12 — assessment not yet done, outcome is null
        patients.add(new Patient("PT-002", "Bob", 52, ConsentStatus.ACTIVE,
                12, "Group1", 10.0,
                null, List.of()));

        // Another patient at exactly week 12 with null outcome
        patients.add(new Patient("PT-003", "Carol", 38, ConsentStatus.ACTIVE,
                12, "Group2", 25.0,
                null, List.of()));

        List<Patient> eligible = filter.filterEligible(patients, config);

        // Only PT-001 should pass — PT-002 and PT-003 are at exactly minWeeks
        // and have no outcome data yet
        assertEquals(1, eligible.size(),
                "Patients at exactly minWeeks have pending assessments and must be excluded");
        assertEquals("PT-001", eligible.get(0).getId());
    }

    @Test
    void testKeepsEligiblePatients() {
        List<Patient> patients = List.of(
                new Patient("PT-010", "Dave", 30, ConsentStatus.ACTIVE,
                        24, "Group1", 10.0,
                        new Outcome(55.0, 1, "COMPLETE"), List.of()),
                new Patient("PT-011", "Eve", 60, ConsentStatus.ACTIVE,
                        20, "Group2", 25.0,
                        new Outcome(62.0, 0, "COMPLETE"), List.of())
        );

        List<Patient> eligible = filter.filterEligible(patients, config);
        assertEquals(2, eligible.size());
    }

    @Test
    void testExcludesMinors() {
        List<Patient> patients = List.of(
                new Patient("PT-020", "Minor", 16, ConsentStatus.ACTIVE,
                        24, "Group1", 10.0,
                        new Outcome(50.0, 0, "COMPLETE"), List.of())
        );

        List<Patient> eligible = filter.filterEligible(patients, config);
        assertEquals(0, eligible.size(), "Patients under minAge must be excluded");
    }
}
