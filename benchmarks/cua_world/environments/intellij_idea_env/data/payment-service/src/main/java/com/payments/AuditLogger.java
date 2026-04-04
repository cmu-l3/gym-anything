package com.payments;

import java.util.ArrayList;
import java.util.List;

/**
 * Records all payment events and manages pending alert entries.
 * Instances of this class are used across multiple threads.
 *
 * <p>Log entries prefixed with "ALERT" represent items requiring human review.
 * The {@link #processPendingAlerts()} method is called periodically to drain
 * and handle those entries.
 */
public class AuditLogger {

    private final List<String> entries = new ArrayList<>();

    /**
     * Appends a log message.
     *
     * @param message log text; typically contains event type and relevant IDs
     */
    public synchronized void log(String message) {
        if (message == null || message.isBlank()) {
            throw new IllegalArgumentException("Log message must not be blank");
        }
        entries.add(message);
    }

    /** Returns the total number of log entries currently stored. */
    public synchronized int getLogCount() {
        return entries.size();
    }

    /** Returns a snapshot copy of all log entries. */
    public synchronized List<String> getEntries() {
        return new ArrayList<>(entries);
    }

    /**
     * Processes and removes all ALERT-prefixed entries from the log.
     *
     * <p>ALERT entries are dispatched to the on-call team and then removed
     * so they are not processed again. Non-ALERT entries are preserved.
     *
     * <p>BUG: This method iterates over {@code entries} using a for-each loop
     * while simultaneously calling {@code entries.remove()} inside the loop body.
     * This causes a {@link java.util.ConcurrentModificationException} at runtime
     * because the ArrayList's structural-modification counter is incremented by
     * {@code remove()}, which invalidates the iterator.
     *
     * <p>Fix: collect entries to remove first (e.g., via {@code removeIf}), or
     * use an explicit {@code Iterator} and call {@code Iterator.remove()}.
     */
    public synchronized void processPendingAlerts() {
        for (String entry : entries) {              // BUG: iterating over list
            if (entry.startsWith("ALERT")) {
                entries.remove(entry);              // BUG: modifying list during iteration → ConcurrentModificationException
            }
        }
    }
}
