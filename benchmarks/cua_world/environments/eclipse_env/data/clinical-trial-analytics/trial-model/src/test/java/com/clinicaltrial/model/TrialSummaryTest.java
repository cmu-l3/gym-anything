package com.clinicaltrial.model;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

class TrialSummaryTest {

    @Test
    void testBuilderCreatesObject() {
        TrialSummary summary = new TrialSummary.Builder()
                .trialId("TRIAL-2024-001")
                .sampleSize(40000)
                .meanEfficacy(45.7)
                .ciLower(38.2)
                .ciUpper(53.2)
                .primaryEndpoint("Tumor Response")
                .build();

        assertNotNull(summary);
        assertEquals("TRIAL-2024-001", summary.getTrialId());
        assertEquals(45.7, summary.getMeanEfficacy(), 0.001);
        assertEquals(38.2, summary.getCiLower(), 0.001);
        assertEquals(53.2, summary.getCiUpper(), 0.001);
        assertEquals("Tumor Response", summary.getPrimaryEndpoint());
    }

    @Test
    void testDefaultValues() {
        TrialSummary summary = new TrialSummary.Builder()
                .trialId("EMPTY")
                .build();

        assertEquals("EMPTY", summary.getTrialId());
        assertEquals(0.0, summary.getMeanEfficacy(), 0.001);
    }

    @Test
    void testToString() {
        TrialSummary summary = new TrialSummary.Builder()
                .trialId("TEST-001")
                .sampleSize(100)
                .meanEfficacy(25.5)
                .ciLower(20.0)
                .ciUpper(31.0)
                .build();

        String str = summary.toString();
        assertTrue(str.contains("TEST-001"));
        assertTrue(str.contains("25.5"));
    }
}
