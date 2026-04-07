package com.clinicaltrial.model;

/**
 * Clinical outcome assessment for a trial participant.
 * Recorded at the end of the treatment observation period.
 */
public class Outcome {

    private double responseScore;
    private int adverseEventCount;
    private String completionStatus;

    public Outcome(double responseScore, int adverseEventCount, String completionStatus) {
        this.responseScore = responseScore;
        this.adverseEventCount = adverseEventCount;
        this.completionStatus = completionStatus;
    }

    public double getResponseScore() {
        return responseScore;
    }

    public int getAdverseEventCount() {
        return adverseEventCount;
    }

    public String getCompletionStatus() {
        return completionStatus;
    }
}
