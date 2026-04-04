package com.healthcare;

import java.util.Objects;

/**
 * Represents a patient in the hospital information system.
 *
 * <p>Two {@code Patient} objects represent the same individual if and only if
 * they share the same medical record number (MRN), full name, <em>and</em>
 * date of birth.  The date-of-birth component is critical because names are
 * not unique: two patients named "Michael Brown" born on different dates are
 * different people and must be stored separately.
 *
 * <p>This class is used as a {@link java.util.HashMap} key inside
 * {@link PatientRegistry}, so {@code equals} and {@code hashCode} must be
 * mutually consistent and must include every field that identifies the patient.
 */
public class Patient {

    private final String mrn;           // medical record number — unique per facility
    private final String fullName;
    private final String dateOfBirth;   // ISO-8601: YYYY-MM-DD

    public Patient(String mrn, String fullName, String dateOfBirth) {
        if (mrn == null || mrn.isBlank())            throw new IllegalArgumentException("MRN is required");
        if (fullName == null || fullName.isBlank())  throw new IllegalArgumentException("Full name is required");
        if (dateOfBirth == null || dateOfBirth.isBlank()) throw new IllegalArgumentException("Date of birth is required");
        this.mrn = mrn;
        this.fullName = fullName;
        this.dateOfBirth = dateOfBirth;
    }

    public String getMrn()         { return mrn; }
    public String getFullName()    { return fullName; }
    public String getDateOfBirth() { return dateOfBirth; }

    /**
     * BUG: {@code equals} compares only {@code fullName}.
     *
     * <p>Two patients with the same name but different dates of birth will be
     * considered equal, causing their records to collide in the registry's HashMap.
     * The second patient's records will silently overwrite or merge with the first's.
     *
     * <p>Fix: include {@code dateOfBirth} (and optionally {@code mrn}) in the
     * equality check and in {@link #hashCode}.
     */
    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof Patient)) return false;
        Patient other = (Patient) o;
        // BUG: only checks fullName — dateOfBirth and mrn are ignored
        return Objects.equals(fullName, other.fullName);
    }

    /**
     * BUG: {@code hashCode} is inconsistent with the buggy {@code equals} above
     * in a different way — it does include the MRN, so two patients with the same
     * name but different MRNs land in different buckets and are never compared.
     * This prevents the collision that {@code equals} would otherwise cause,
     * making the bug intermittent and hard to reproduce without the right test case.
     *
     * <p>Fix: hash exactly the same fields used in {@code equals}.
     */
    @Override
    public int hashCode() {
        // BUG: hashes on fullName only — must match the fields used in equals
        return Objects.hash(fullName);
    }

    @Override
    public String toString() {
        return String.format("Patient{mrn='%s', name='%s', dob='%s'}", mrn, fullName, dateOfBirth);
    }
}
