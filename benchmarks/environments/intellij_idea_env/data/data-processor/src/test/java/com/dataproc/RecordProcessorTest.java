package com.dataproc;

import org.joda.time.DateTime;
import org.junit.Before;
import org.junit.Test;
import java.util.Arrays;
import java.util.List;
import static org.junit.Assert.*;

public class RecordProcessorTest {

    private RecordProcessor processor;
    private List<TextRecord> records;

    @Before
    public void setUp() {
        processor = new RecordProcessor();
        records = Arrays.asList(
            new TextRecord("rec-1", "Hello World",  "2023-01-01 10:00:00"),
            new TextRecord("rec-2", "Data Pipeline", "2023-06-15 12:00:00"),
            new TextRecord("rec-3", "hello again",   "2023-12-31 23:59:59")
        );
    }

    @Test
    public void testFilterExpiredRemovesOldRecords() {
        DateTime cutoff = new DateTime(2023, 6, 1, 0, 0, 0);
        List<TextRecord> result = processor.filterExpired(records, cutoff);
        assertEquals(2, result.size());
    }

    @Test
    public void testFilterExpiredKeepsAllWhenCutoffEarly() {
        DateTime cutoff = new DateTime(2022, 1, 1, 0, 0, 0);
        List<TextRecord> result = processor.filterExpired(records, cutoff);
        assertEquals(3, result.size());
    }

    @Test
    public void testNormalizeContent() {
        List<TextRecord> result = processor.normalizeContent(records);
        assertEquals("HELLO WORLD",   result.get(0).getContent());
        assertEquals("DATA PIPELINE", result.get(1).getContent());
        assertEquals("HELLO AGAIN",   result.get(2).getContent());
    }

    @Test
    public void testCountContaining() {
        assertEquals(2, processor.countContaining(records, "hello"));
    }

    @Test
    public void testCountContainingCaseInsensitive() {
        assertEquals(2, processor.countContaining(records, "HELLO"));
    }

    @Test
    public void testCountContainingNoMatch() {
        assertEquals(0, processor.countContaining(records, "xyz"));
    }
}
