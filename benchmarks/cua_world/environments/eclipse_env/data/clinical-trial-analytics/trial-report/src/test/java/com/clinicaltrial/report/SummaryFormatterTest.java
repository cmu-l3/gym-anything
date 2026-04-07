package com.clinicaltrial.report;

import com.clinicaltrial.model.TrialSummary;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

class SummaryFormatterTest {

    @Test
    void testFormatOutput() {
        TrialSummary summary = new TrialSummary.Builder()
                .trialId("FMT-001")
                .sampleSize(200)
                .meanEfficacy(33.3)
                .ciLower(28.0)
                .ciUpper(38.6)
                .primaryEndpoint("Progression Free Survival")
                .build();

        SummaryFormatter formatter = new SummaryFormatter();
        String output = formatter.formatForSubmission(summary);

        assertTrue(output.contains("FMT-001"));
        assertTrue(output.contains("CLINICAL STUDY REPORT"));
        assertTrue(output.contains("POSITIVE SIGNAL"));
    }
}
