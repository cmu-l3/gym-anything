package com.clinicaltrial.model;

import java.util.ArrayList;
import java.util.List;

/**
 * Represents a treatment arm in the clinical trial (e.g., placebo, 10mg, 25mg).
 */
public class DoseGroup {

    private String groupName;
    private double doseAmountMg;
    private List<Patient> patients;

    public DoseGroup(String groupName, double doseAmountMg) {
        this.groupName = groupName;
        this.doseAmountMg = doseAmountMg;
        this.patients = new ArrayList<>();
    }

    public void addPatient(Patient patient) {
        patients.add(patient);
    }

    public String getGroupName() { return groupName; }
    public double getDoseAmountMg() { return doseAmountMg; }
    public List<Patient> getPatients() { return patients; }

    public double getMeanResponseScore() {
        return patients.stream()
                .filter(p -> p.getOutcome() != null)
                .mapToDouble(p -> p.getOutcome().getResponseScore())
                .average()
                .orElse(0.0);
    }
}
