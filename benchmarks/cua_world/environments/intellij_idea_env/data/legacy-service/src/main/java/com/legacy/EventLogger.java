package com.legacy;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * Records application events (audit trail, errors, and operational events)
 * to an in-memory log.  Events are categorised by type and include a
 * detail message.
 *
 * <p>The contract is strict: all parameters must be non-null.  Callers that
 * pass {@code null} for the event type are making a programming error and
 * must receive a {@link NullPointerException} immediately rather than a
 * silent no-op that corrupts the audit trail.
 */
public class EventLogger {

    private final List<String> eventLog = new ArrayList<>();

    /**
     * Appends an event to the log in the format {@code "TYPE: details"}.
     *
     * <p>BUG: the method body is wrapped in a broad {@code catch (Exception e)}
     * block.  If {@code eventType} is {@code null}, the call to
     * {@code eventType.toUpperCase()} throws a {@link NullPointerException},
     * which is then silently swallowed.  The caller believes the event was
     * recorded, but the log contains no entry — the audit trail has a silent gap.
     *
     * <p>Fix: remove the {@code try/catch} wrapper entirely, or replace it with
     * a targeted {@code catch} for a specific checked exception.  Null arguments
     * must propagate as {@link NullPointerException} so callers find their bugs.
     *
     * @param eventType  a short uppercase category label such as {@code "LOGIN"},
     *                   {@code "TRANSFER"}, or {@code "ERROR"}; must not be null
     * @param details    a human-readable description of the event; must not be null
     * @throws NullPointerException if {@code eventType} or {@code details} is null
     *         <em>(currently swallowed — must be fixed)</em>
     */
    public void log(String eventType, String details) {
        try {
            String entry = eventType.toUpperCase() + ": " + details;  // NPE if eventType is null
            eventLog.add(entry);
        } catch (Exception e) {
            // BUG: any exception — including NullPointerException from a null eventType —
            // is silently discarded.  The audit entry is lost without any signal to the caller.
        }
    }

    /** Returns the number of events recorded. */
    public int getEventCount() {
        return eventLog.size();
    }

    /** Returns a read-only snapshot of all recorded events. */
    public List<String> getEvents() {
        return Collections.unmodifiableList(eventLog);
    }
}
