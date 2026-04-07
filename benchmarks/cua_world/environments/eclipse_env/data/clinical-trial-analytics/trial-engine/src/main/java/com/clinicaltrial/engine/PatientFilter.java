package com.clinicaltrial.engine;

import com.clinicaltrial.model.ConsentStatus;
import com.clinicaltrial.model.Patient;
import com.clinicaltrial.model.TrialConfig;

import java.util.List;
import java.util.stream.Collectors;

/**
 * Filters clinical trial participants based on protocol eligibility criteria.
 * Implements ICH E9 statistical principles for population selection.
 */
public class PatientFilter {

    /**
     * Returns the per-protocol population: patients meeting all eligibility
     * criteria who have remained in the study long enough for assessment.
     */
    public List<Patient> filterEligible(List<Patient> patients, TrialConfig config) {
        return patients.stream()
                .filter(p -> p.getConsentStatus() == ConsentStatus.ACTIVE)
                .filter(p -> p.getAge() >= config.getMinAge() && p.getAge() <= config.getMaxAge())
                .filter(p -> p.getWeeksEnrolled() >= config.getMinWeeks())
                .filter(p -> p.getExclusions().stream()
                        .noneMatch(e -> config.getExclusionCriteria().contains(e)))
                .collect(Collectors.toList());
    }
}
