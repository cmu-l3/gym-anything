package com.clinicaltrial.model;

import java.util.ArrayList;
import java.util.List;

/**
 * Represents a clinical trial participant with demographic and treatment data.
 */
public class Patient {

    private String id;
    private String name;
    private int age;
    private ConsentStatus consentStatus;
    private int weeksEnrolled;
    private String doseGroup;
    private double doseMg;
    private Outcome outcome;
    private List<String> exclusions;

    public Patient(String id, String name, int age, ConsentStatus consentStatus,
                   int weeksEnrolled, String doseGroup, double doseMg,
                   Outcome outcome, List<String> exclusions) {
        this.id = id;
        this.name = name;
        this.age = age;
        this.consentStatus = consentStatus;
        this.weeksEnrolled = weeksEnrolled;
        this.doseGroup = doseGroup;
        this.doseMg = doseMg;
        this.outcome = outcome;
        this.exclusions = exclusions != null ? exclusions : new ArrayList<>();
    }

    public String getId() { return id; }
    public String getName() { return name; }
    public int getAge() { return age; }
    public ConsentStatus getConsentStatus() { return consentStatus; }
    public int getWeeksEnrolled() { return weeksEnrolled; }
    public String getDoseGroup() { return doseGroup; }
    public double getDoseMg() { return doseMg; }
    public Outcome getOutcome() { return outcome; }
    public List<String> getExclusions() { return exclusions; }

    @Override
    public String toString() {
        return "Patient{id='" + id + "', age=" + age + ", weeks=" + weeksEnrolled
                + ", dose=" + doseMg + "mg}";
    }
}
