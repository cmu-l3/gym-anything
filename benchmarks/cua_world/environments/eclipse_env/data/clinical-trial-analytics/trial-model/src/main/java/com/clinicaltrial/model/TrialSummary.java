package com.clinicaltrial.model;

/**
 * Immutable summary of a clinical trial analysis run.
 * Typically produced by the analysis pipeline and consumed by report generators.
 * Follows CDISC ADaM dataset conventions for summary-level endpoints.
 */
public class TrialSummary {

    private String trialId;
    private int sampleSize;
    private double meanEfficacy;
    private double ciLower;
    private double ciUpper;
    private String primaryEndpoint;

    private TrialSummary() {}

    public String getTrialId() { return trialId; }
    public int getSampleSize() { return sampleSize; }
    public double getMeanEfficacy() { return meanEfficacy; }
    public double getCiLower() { return ciLower; }
    public double getCiUpper() { return ciUpper; }
    public String getPrimaryEndpoint() { return primaryEndpoint; }

    @Override
    public String toString() {
        return "TrialSummary{trialId='" + trialId + "', n=" + sampleSize
                + ", efficacy=" + String.format("%.4f", meanEfficacy)
                + ", CI=[" + String.format("%.4f", ciLower) + ", "
                + String.format("%.4f", ciUpper) + "]}";
    }

    public static class Builder {
        private String trialId;
        private int sampleSize;
        private double meanEfficacy;
        private double ciLower;
        private double ciUpper;
        private String primaryEndpoint;

        public Builder trialId(String id) { this.trialId = id; return this; }
        public Builder sampleSize(int n) { this.sampleSize = n; return this; }
        public Builder meanEfficacy(double e) { this.meanEfficacy = e; return this; }
        public Builder ciLower(double l) { this.ciLower = l; return this; }
        public Builder ciUpper(double u) { this.ciUpper = u; return this; }
        public Builder primaryEndpoint(String ep) { this.primaryEndpoint = ep; return this; }

        public TrialSummary build() {
            TrialSummary s = new TrialSummary();
            s.trialId = this.trialId;
            s.meanEfficacy = this.meanEfficacy;
            s.ciLower = this.ciLower;
            s.ciUpper = this.ciUpper;
            s.primaryEndpoint = this.primaryEndpoint;
            return s;
        }
    }
}
