package com.healthcare;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.logging.Logger;

/**
 * In-memory registry mapping patients to their medical records.
 *
 * <p>The registry uses a {@link HashMap} keyed on {@link Patient}, so correct
 * behaviour depends on a properly implemented {@link Patient#equals} and
 * {@link Patient#hashCode}.
 */
public class PatientRegistry {

    private static final Logger LOG = Logger.getLogger(PatientRegistry.class.getName());

    private final Map<Patient, List<MedicalRecord>> records = new HashMap<>();

    /**
     * Adds a validated {@link MedicalRecord} for the given patient.
     *
     * <p>BUG: any {@link IllegalArgumentException} thrown by
     * {@link MedicalRecord#validate()} is silently swallowed inside the
     * catch block.  The caller receives no indication that the record was
     * rejected, and the registry is left in the same state as if the add
     * had never been attempted.
     *
     * <p>Fix: re-throw the exception (or wrap it) so callers can detect and
     * handle invalid records.
     *
     * @param patient the patient to associate the record with
     * @param record  the record to add; will be validated before insertion
     * @throws IllegalArgumentException if {@code record} fails validation
     *         <em>(currently swallowed — must be fixed)</em>
     */
    public void addRecord(Patient patient, MedicalRecord record) {
        if (patient == null) throw new IllegalArgumentException("Patient must not be null");
        if (record == null)  throw new IllegalArgumentException("Record must not be null");

        try {
            record.validate();
            records.computeIfAbsent(patient, k -> new ArrayList<>()).add(record);
        } catch (IllegalArgumentException e) {
            // BUG: exception is logged but not re-thrown — the caller cannot detect the failure
            LOG.warning("Rejected invalid medical record for patient " + patient.getMrn()
                        + ": " + e.getMessage());
            // Missing: throw e;
        }
    }

    /**
     * Returns an unmodifiable list of records for the given patient,
     * or an empty list if no records exist.
     */
    public List<MedicalRecord> getRecords(Patient patient) {
        return Collections.unmodifiableList(
            records.getOrDefault(patient, Collections.emptyList())
        );
    }

    /** Returns the total number of distinct patients in the registry. */
    public int getPatientCount() {
        return records.size();
    }
}
