package com.library.strings;

/**
 * String utility functions.
 * Adapted from Apache Commons Lang StringUtils patterns (Apache License 2.0).
 *
 * These utilities form the "strings" component of the library — independent
 * of the math and collections components, so they naturally belong in
 * their own Maven module.
 */
public class StringUtils {

    private StringUtils() {}

    /**
     * Returns true if the string is null, empty, or contains only whitespace.
     */
    public static boolean isBlank(String s) {
        return s == null || s.trim().isEmpty();
    }

    /**
     * Reverses a string. Returns null if input is null.
     */
    public static String reverse(String s) {
        if (s == null) return null;
        return new StringBuilder(s).reverse().toString();
    }

    /**
     * Returns true if the string reads the same forwards and backwards,
     * ignoring case and non-alphanumeric characters.
     */
    public static boolean isPalindrome(String s) {
        if (s == null) return false;
        String cleaned = s.toLowerCase().replaceAll("[^a-z0-9]", "");
        return cleaned.equals(new StringBuilder(cleaned).reverse().toString());
    }

    /**
     * Counts the number of times {@code sub} appears in {@code s}
     * (non-overlapping). Returns 0 if either argument is null or empty.
     */
    public static int countOccurrences(String s, String sub) {
        if (isBlank(s) || isBlank(sub)) return 0;
        int count = 0;
        int idx = 0;
        while ((idx = s.indexOf(sub, idx)) != -1) {
            count++;
            idx += sub.length();
        }
        return count;
    }

    /**
     * Truncates the string to at most {@code maxLen} characters.
     * If the string is longer, it is cut at {@code maxLen-3} and "..." is appended.
     */
    public static String truncate(String s, int maxLen) {
        if (s == null) return null;
        if (maxLen <= 3) return s.substring(0, Math.min(s.length(), maxLen));
        if (s.length() <= maxLen) return s;
        return s.substring(0, maxLen - 3) + "...";
    }
}
