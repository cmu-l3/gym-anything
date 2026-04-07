package com.bank.commons;

import java.math.BigDecimal;
import java.math.RoundingMode;

/**
 * Utility class for monetary calculations.
 * Uses BigDecimal internally to avoid floating-point precision issues.
 */
public final class MoneyUtils {

    private MoneyUtils() {
        throw new UnsupportedOperationException("Utility class");
    }

    /**
     * Rounds a monetary amount to exactly 2 decimal places using banker's rounding.
     */
    public static double roundToTwoDecimals(double amount) {
        return BigDecimal.valueOf(amount)
                .setScale(2, RoundingMode.HALF_UP)
                .doubleValue();
    }

    /**
     * Returns true if the given amount is a valid positive monetary value.
     */
    public static boolean isValidAmount(double amount) {
        return amount > 0 && Double.isFinite(amount);
    }

    /**
     * Formats a monetary amount as a string with 2 decimal places.
     */
    public static String format(double amount) {
        return String.format("$%.2f", amount);
    }
}
