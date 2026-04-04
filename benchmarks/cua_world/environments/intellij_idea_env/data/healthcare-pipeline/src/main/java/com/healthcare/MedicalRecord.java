package com.healthcare;

/**
 * A single medical record entry for a patient: an ICD-10 diagnosis code,
 * a human-readable description, and the date the record was created.
 */
public class MedicalRecord {

    private final String icd10Code;
    private final String description;
    private final String recordDate;   // ISO-8601 YYYY-MM-DD

    public MedicalRecord(String icd10Code, String description, String recordDate) {
        this.icd10Code = icd10Code;
        this.description = description;
        this.recordDate = recordDate;
    }

    public String getIcd10Code()   { return icd10Code; }
    public String getDescription() { return description; }
    public String getRecordDate()  { return recordDate; }

    /**
     * Validates this record.  Throws {@link IllegalArgumentException} if the
     * ICD-10 code is absent or fails the DiagnosticCoder format check.
     */
    public void validate() {
        if (icd10Code == null || icd10Code.isBlank()) {
            throw new IllegalArgumentException(
                "Medical record must have a non-empty ICD-10 code");
        }
        if (!DiagnosticCoder.isValidCode(icd10Code)) {
            throw new IllegalArgumentException(
                "Invalid ICD-10 code format: '" + icd10Code + "'. " +
                "Expected format: ICD10-<category>.<sub-category>");
        }
    }

    @Override
    public String toString() {
        return String.format("MedicalRecord{code='%s', date='%s'}", icd10Code, recordDate);
    }
}
