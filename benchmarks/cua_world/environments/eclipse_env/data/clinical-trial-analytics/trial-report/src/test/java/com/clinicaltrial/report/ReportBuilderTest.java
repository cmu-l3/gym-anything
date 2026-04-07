package com.clinicaltrial.report;

import com.clinicaltrial.model.TrialSummary;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

class ReportBuilderTest {

    @Test
    void testSummaryContainsTrialId() {
        TrialSummary summary = new TrialSummary.Builder()
                .trialId("ONCO-2024-DR7")
                .sampleSize(150)
                .meanEfficacy(42.5)
                .ciLower(35.0)
                .ciUpper(50.0)
                .primaryEndpoint("Response Score")
                .build();

        ReportBuilder builder = new ReportBuilder();
        String report = builder.buildReport(summary);

        assertTrue(report.contains("ONCO-2024-DR7"),
                "Report must contain the trial ID");
        assertTrue(report.contains("CLINICAL TRIAL ANALYSIS REPORT"),
                "Report must contain the header");
    }

    @Test
    void testSummaryReportValues() {
        TrialSummary summary = new TrialSummary.Builder()
                .trialId("TRIAL-RPT-001")
                .sampleSize(40000)
                .meanEfficacy(55.3)
                .ciLower(48.1)
                .ciUpper(62.5)
                .primaryEndpoint("Overall Survival")
                .build();

        ReportBuilder builder = new ReportBuilder();
        int extractedSize = builder.extractSampleSize(summary);

        assertEquals(40000, extractedSize,
                "Extracted sample size must match what was set in the builder. "
                + "If this returns 0, the Builder.build() method is not copying sampleSize.");
    }
}
