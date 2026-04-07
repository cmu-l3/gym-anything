package com.clinicaltrial.model;

import java.util.ArrayList;
import java.util.List;

/**
 * Configuration parameters for clinical trial eligibility criteria.
 * Based on ICH E6(R2) GCP protocol design standards.
 */
public class TrialConfig {

    private String trialId;
    private int minAge;
    private int maxAge;
    private int minWeeks;
    private List<String> exclusionCriteria;

    public TrialConfig(String trialId, int minAge, int maxAge, int minWeeks,
                       List<String> exclusionCriteria) {
        this.trialId = trialId;
        this.minAge = minAge;
        this.maxAge = maxAge;
        this.minWeeks = minWeeks;
        this.exclusionCriteria = exclusionCriteria != null ? exclusionCriteria : new ArrayList<>();
    }

    public String getTrialId() { return trialId; }
    public int getMinAge() { return minAge; }
    public int getMaxAge() { return maxAge; }
    public int getMinWeeks() { return minWeeks; }
    public List<String> getExclusionCriteria() { return exclusionCriteria; }
}
