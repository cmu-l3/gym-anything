package com.clinicaltrial.report;

import com.clinicaltrial.model.TrialSummary;

/**
 * Formats TrialSummary objects into human-readable text reports
 * suitable for regulatory submission cover pages.
 */
public class SummaryFormatter {

    /**
     * Formats a TrialSummary into a structured clinical study report section.
     */
    public String formatForSubmission(TrialSummary summary) {
        return """
                ============================================
                CLINICAL STUDY REPORT - EFFICACY SUMMARY
                ============================================
                Trial ID:          %s
                Sample Size (N):   %d
                Primary Endpoint:  %s

                RESULTS
                -------
                Mean Efficacy:     %.4f
                95%% CI:            [%.4f, %.4f]

                STATUS: %s
                ============================================
                """.formatted(
                summary.getTrialId(),
                summary.getSampleSize(),
                summary.getPrimaryEndpoint(),
                summary.getMeanEfficacy(),
                summary.getCiLower(),
                summary.getCiUpper(),
                summary.getMeanEfficacy() > 0 ? "POSITIVE SIGNAL" : "NO SIGNAL"
        );
    }
}
