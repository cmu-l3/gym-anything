package com.healthcare;

import org.junit.Test;
import static org.junit.Assert.*;

/**
 * Tests for the healthcare record pipeline: patient equality, record ingestion,
 * validation error propagation, and null-safety of the diagnostic coder.
 */
public class PatientRegistryTest {

    // -----------------------------------------------------------------------
    // Baseline: basic record add and retrieval (should pass before any fixes)
    // -----------------------------------------------------------------------

    @Test
    public void testAddAndRetrieveRecord() {
        PatientRegistry registry = new PatientRegistry();
        Patient patient = new Patient("MRN-1001", "Alice Johnson", "1978-03-22");
        MedicalRecord record = new MedicalRecord("ICD10-J00.0", "Common cold", "2024-11-15");

        registry.addRecord(patient, record);

        assertEquals("Registry should have 1 patient", 1, registry.getPatientCount());
        assertEquals("Patient should have 1 record",   1, registry.getRecords(patient).size());
        assertEquals("Record ICD code should match",
                     "ICD10-J00.0", registry.getRecords(patient).get(0).getIcd10Code());
    }

    // -----------------------------------------------------------------------
    // Patient equality test — exercises Patient.equals/hashCode bug
    // -----------------------------------------------------------------------

    @Test
    public void testPatientsWithSameNameButDifferentDOBAreDistinct() {
        PatientRegistry registry = new PatientRegistry();

        // Two real patients with identical names but different dates of birth
        Patient patient1 = new Patient("MRN-2001", "Michael Brown", "1972-08-10");
        Patient patient2 = new Patient("MRN-2002", "Michael Brown", "1989-04-30");

        assertFalse(
            "Two patients with the same name but different dates of birth must NOT be equal. " +
            "Fix: Patient.equals() must compare dateOfBirth in addition to fullName, " +
            "and Patient.hashCode() must hash dateOfBirth as well.",
            patient1.equals(patient2)
        );

        // Add a record for each — they must be stored independently
        MedicalRecord rec1 = new MedicalRecord("ICD10-K21.0", "GERD",         "2024-01-10");
        MedicalRecord rec2 = new MedicalRecord("ICD10-M54.5", "Low back pain","2024-03-05");

        registry.addRecord(patient1, rec1);
        registry.addRecord(patient2, rec2);

        assertEquals(
            "Registry must contain 2 distinct patients (not merged due to same name). " +
            "Current patient count suggests Patient.equals() treats them as the same person.",
            2, registry.getPatientCount()
        );
        assertEquals("Patient 1 (1972) should have exactly 1 record", 1, registry.getRecords(patient1).size());
        assertEquals("Patient 2 (1989) should have exactly 1 record", 1, registry.getRecords(patient2).size());
    }

    // -----------------------------------------------------------------------
    // Exception propagation test — exercises PatientRegistry.addRecord bug
    // -----------------------------------------------------------------------

    @Test
    public void testAddingInvalidRecordThrowsException() {
        PatientRegistry registry = new PatientRegistry();
        Patient patient = new Patient("MRN-3001", "Carol White", "1965-12-01");

        // A record with an empty ICD-10 code — MedicalRecord.validate() should reject it
        MedicalRecord badRecord = new MedicalRecord("", "Unspecified condition", "2024-06-01");

        try {
            registry.addRecord(patient, badRecord);
            fail(
                "addRecord() must throw IllegalArgumentException when the record fails validation, " +
                "but no exception was thrown. " +
                "Fix: PatientRegistry.addRecord() catches IllegalArgumentException from " +
                "record.validate() but never re-throws it — add 'throw e;' in the catch block."
            );
        } catch (IllegalArgumentException e) {
            // Expected: the validation failure must propagate to the caller
        }

        // The invalid record must not have been inserted
        assertEquals("No records should exist for this patient after a failed add",
                     0, registry.getRecords(patient).size());
        assertEquals("Registry should have no patients after failed add",
                     0, registry.getPatientCount());
    }

    // -----------------------------------------------------------------------
    // Null safety test — exercises DiagnosticCoder.isValidCode NPE bug
    // -----------------------------------------------------------------------

    @Test
    public void testNullDiagnosticCodeReturnsFalseNotNPE() {
        try {
            boolean result = DiagnosticCoder.isValidCode(null);
            // If no exception was thrown, the method must return false (not true)
            assertFalse(
                "DiagnosticCoder.isValidCode(null) must return false, not true. " +
                "Fix: add a null check at the start of isValidCode().",
                result
            );
        } catch (NullPointerException e) {
            fail(
                "DiagnosticCoder.isValidCode(null) threw NullPointerException instead of returning false. " +
                "Fix: add 'if (code == null) return false;' at the beginning of the method."
            );
        }
    }

    @Test
    public void testValidIcd10CodeAccepted() {
        assertTrue(DiagnosticCoder.isValidCode("ICD10-J00.0"));
        assertTrue(DiagnosticCoder.isValidCode("ICD10-K21.0"));
        assertTrue(DiagnosticCoder.isValidCode("ICD10-Z00.00"));
    }

    @Test
    public void testInvalidIcd10CodeRejected() {
        assertFalse(DiagnosticCoder.isValidCode(""));
        assertFalse(DiagnosticCoder.isValidCode("J00.0"));        // missing prefix
        assertFalse(DiagnosticCoder.isValidCode("ICD10-J00"));    // missing dot separator
    }
}
