package com.legacy;

/**
 * Parses raw string records from upstream data feeds into structured values.
 *
 * <p>This class is called on every row in high-volume batch jobs and must
 * fail loudly on malformed input so upstream data-quality issues surface
 * immediately rather than propagating incorrect defaults downstream.
 */
public class RecordParser {

    /**
     * Parses a monetary amount from a string representation.
     *
     * <p>The string may contain an optional currency symbol, commas, and
     * optional decimal cents.  Examples: {@code "$1,234.56"}, {@code "9999"},
     * {@code "3,500.00"}.  The result is returned in cents (integer).
     *
     * <p>BUG: a {@link NumberFormatException} thrown during parsing is caught
     * and silently suppressed; the method returns {@code 0L} instead of
     * signalling the error.  Downstream code receives a plausible-looking
     * zero balance for what is actually corrupt data, leading to incorrect
     * financial calculations and audit discrepancies.
     *
     * <p>Fix: remove the {@code catch} block (or re-throw as
     * {@code IllegalArgumentException}) so the caller knows the input
     * was malformed.
     *
     * @param raw the raw monetary string (e.g., {@code "$1,500.00"})
     * @return amount in cents
     * @throws IllegalArgumentException if {@code raw} cannot be parsed
     *         <em>(currently suppressed — must be fixed)</em>
     */
    public long parseAmountCents(String raw) {
        try {
            if (raw == null || raw.isBlank()) {
                throw new IllegalArgumentException("Amount string must not be blank");
            }
            // Strip currency symbol and commas, then parse integer cents
            String cleaned = raw.replaceAll("[$,]", "").trim();
            if (cleaned.contains(".")) {
                String[] parts = cleaned.split("\\.");
                long dollars = Long.parseLong(parts[0]);
                long cents   = parts.length > 1 ? Long.parseLong(
                        (parts[1] + "0").substring(0, 2)) : 0L;
                return dollars * 100 + cents;
            }
            return Long.parseLong(cleaned) * 100;
        } catch (NumberFormatException e) {
            // BUG: silently returns 0 for malformed input — callers cannot detect parse failure
            return 0L;
        }
    }

    /**
     * Parses a user-ID field from a raw record string.
     *
     * <p>User IDs must be non-empty alphanumeric strings of length 6–20.
     *
     * @param raw the raw user-ID string
     * @return the trimmed user ID
     * @throws IllegalArgumentException if the ID is null, blank, or outside length bounds
     */
    public String parseUserId(String raw) {
        if (raw == null || raw.isBlank()) {
            throw new IllegalArgumentException("User ID must not be blank");
        }
        String trimmed = raw.trim();
        if (trimmed.length() < 6 || trimmed.length() > 20) {
            throw new IllegalArgumentException(
                "User ID length must be 6–20 characters, got " + trimmed.length());
        }
        if (!trimmed.matches("[A-Za-z0-9_-]+")) {
            throw new IllegalArgumentException(
                "User ID must be alphanumeric (with _ or -), got: '" + trimmed + "'");
        }
        return trimmed;
    }
}
