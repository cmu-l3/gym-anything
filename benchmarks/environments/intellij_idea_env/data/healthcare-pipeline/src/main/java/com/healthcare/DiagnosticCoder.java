package com.healthcare;

/**
 * Utility class for validating and categorising ICD-10 diagnostic codes.
 *
 * <p>Expected code format: {@code ICD10-<CATEGORY>.<SUB>}
 * Examples: {@code ICD10-J00.0}, {@code ICD10-K21.0}, {@code ICD10-Z00.00}
 */
public class DiagnosticCoder {

    private DiagnosticCoder() { /* utility class */ }

    /**
     * Returns {@code true} if {@code code} matches the expected ICD-10 format.
     *
     * <p>BUG: this method calls {@code code.startsWith("ICD10-")} without first
     * checking whether {@code code} is {@code null}. Passing {@code null} results
     * in a {@link NullPointerException} rather than a clean {@code false} return.
     *
     * <p>Fix: add a null guard at the top of the method:
     * {@code if (code == null) return false;}
     *
     * @param code the diagnostic code to validate; {@code null} should return {@code false}
     * @return {@code true} if the code is correctly formatted
     */
    public static boolean isValidCode(String code) {
        // BUG: no null check — code.startsWith() throws NullPointerException when code is null
        return code.startsWith("ICD10-") && code.length() >= 8 && code.contains(".");
    }

    /**
     * Extracts the top-level chapter letter from a valid ICD-10 code.
     * For example, {@code "ICD10-J00.0"} returns {@code "J"}.
     *
     * @param code a valid ICD-10 code
     * @return the single-character chapter prefix
     * @throws IllegalArgumentException if the code is invalid
     */
    public static String extractChapter(String code) {
        if (!isValidCode(code)) {
            throw new IllegalArgumentException("Invalid ICD-10 code: " + code);
        }
        // Code format is "ICD10-X..." where X is the chapter letter
        return String.valueOf(code.charAt(6));
    }
}
