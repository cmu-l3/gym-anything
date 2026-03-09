package com.dataproc;

import org.joda.time.DateTime;
import org.joda.time.format.DateTimeFormat;
import org.joda.time.format.DateTimeFormatter;

/**
 * Represents a text record with an ID, content, and timestamp.
 * Used for batch processing pipelines where records need to be
 * normalized, filtered, and transformed.
 *
 * Adapted from Apache Commons / real data-processing patterns.
 */
public class TextRecord {

    private final String id;
    private final String content;
    private final DateTime timestamp;

    private static final DateTimeFormatter FORMATTER =
            DateTimeFormat.forPattern("yyyy-MM-dd HH:mm:ss");

    public TextRecord(String id, String content, String timestampStr) {
        if (id == null || id.trim().isEmpty()) {
            throw new IllegalArgumentException("Record ID must not be null or empty");
        }
        this.id = id.trim();
        this.content = content == null ? "" : content;
        this.timestamp = DateTime.parse(timestampStr, FORMATTER);
    }

    public String getId() {
        return id;
    }

    public String getContent() {
        return content;
    }

    public DateTime getTimestamp() {
        return timestamp;
    }

    public boolean isExpired(DateTime cutoff) {
        return timestamp.isBefore(cutoff);
    }

    public TextRecord withContent(String newContent) {
        return new TextRecord(id, newContent, FORMATTER.print(timestamp));
    }

    @Override
    public String toString() {
        return "TextRecord{id='" + id + "', timestamp=" + FORMATTER.print(timestamp) + "}";
    }
}
