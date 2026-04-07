package com.clinicaltrial.report;

import com.clinicaltrial.model.TrialSummary;

/**
 * Exports trial analysis results to CSV format for downstream processing
 * by SAS, R, or CDISC submission tools.
 */
public class CsvExporter {

    public String exportSummaryAsCsv(TrialSummary summary) {
        StringBuilder sb = new StringBuilder();
        sb.append("trial_id,sample_size,mean_efficacy,ci_lower,ci_upper,primary_endpoint\n");
        sb.append(String.format("%s,%d,%.4f,%.4f,%.4f,%s\n",
                summary.getTrialId(),
                summary.getSampleSize(),
                summary.getMeanEfficacy(),
                summary.getCiLower(),
                summary.getCiUpper(),
                summary.getPrimaryEndpoint()));
        return sb.toString();
    }

    public String getCsvHeader() {
        return "trial_id,sample_size,mean_efficacy,ci_lower,ci_upper,primary_endpoint";
    }
}
