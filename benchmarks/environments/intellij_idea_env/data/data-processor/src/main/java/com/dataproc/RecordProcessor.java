package com.dataproc;

import org.joda.time.DateTime;
import java.util.ArrayList;
import java.util.List;

/**
 * Processes collections of TextRecords: filters expired records,
 * normalizes content, and counts records matching criteria.
 *
 * Adapted from real data-processing utility patterns.
 */
public class RecordProcessor {

    /**
     * Filters out records whose timestamp is before the given cutoff.
     *
     * @param records list of records to filter
     * @param cutoff  records before this time are excluded
     * @return new list containing only non-expired records
     */
    public List<TextRecord> filterExpired(List<TextRecord> records, DateTime cutoff) {
        List<TextRecord> result = new ArrayList<>();
        for (TextRecord record : records) {
            if (!record.isExpired(cutoff)) {
                result.add(record);
            }
        }
        return result;
    }

    /**
     * Normalizes the content of each record: trims whitespace, converts to uppercase.
     *
     * @param records list of records to normalize
     * @return new list with normalized content
     */
    public List<TextRecord> normalizeContent(List<TextRecord> records) {
        List<TextRecord> result = new ArrayList<>();
        for (TextRecord record : records) {
            String normalized = record.getContent().trim().toUpperCase();
            result.add(record.withContent(normalized));
        }
        return result;
    }

    /**
     * Counts records whose content contains the given keyword (case-insensitive).
     *
     * @param records list of records to search
     * @param keyword keyword to look for
     * @return count of matching records
     */
    public int countContaining(List<TextRecord> records, String keyword) {
        if (keyword == null || keyword.isEmpty()) {
            return 0;
        }
        int count = 0;
        String lowerKeyword = keyword.toLowerCase();
        for (TextRecord record : records) {
            if (record.getContent().toLowerCase().contains(lowerKeyword)) {
                count++;
            }
        }
        return count;
    }
}
