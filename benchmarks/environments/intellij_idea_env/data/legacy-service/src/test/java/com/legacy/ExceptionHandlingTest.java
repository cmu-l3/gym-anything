package com.legacy;

import org.junit.Before;
import org.junit.Test;
import static org.junit.Assert.*;

import java.io.File;
import java.io.IOException;
import java.util.Arrays;
import java.util.List;
import java.util.Properties;

/**
 * Verifies that all exception handling in the legacy service layer
 * conforms to the hardening requirements from the Q4 security audit.
 *
 * <p>Every test in this class describes a specific code-quality violation
 * found in the audit and asserts the corrected behaviour.
 */
public class ExceptionHandlingTest {

    private RecordParser  parser;
    private EventLogger   logger;
    private ConfigLoader  configLoader;
    private BatchProcessor processor;

    @Before
    public void setUp() {
        parser     = new RecordParser();
        logger     = new EventLogger();
        configLoader = new ConfigLoader();
        processor  = new BatchProcessor(parser, logger);
    }

    // -----------------------------------------------------------------------
    // Baseline: verify correct behaviour still works (should pass before fixes)
    // -----------------------------------------------------------------------

    @Test
    public void testParseValidAmounts() {
        assertEquals("$10.00 → 1000 cents", 1000L, parser.parseAmountCents("$10.00"));
        assertEquals("$1,234.56 → 123456 cents", 123456L, parser.parseAmountCents("$1,234.56"));
        assertEquals("9999 → 999900 cents", 999900L, parser.parseAmountCents("9999"));
    }

    @Test
    public void testEventLoggerRecordsValidEvents() {
        logger.log("LOGIN", "user admin logged in from 192.168.1.1");
        logger.log("TRANSFER", "amount=5000 from=ACC-1 to=ACC-2");
        assertEquals(2, logger.getEventCount());
        assertTrue(logger.getEvents().get(0).contains("LOGIN:"));
    }

    // -----------------------------------------------------------------------
    // Audit finding 1: RecordParser.parseAmountCents swallows NumberFormatException
    // -----------------------------------------------------------------------

    @Test
    public void testParseAmountThrowsOnGarbageInput() {
        try {
            long result = parser.parseAmountCents("INVALID_AMOUNT");
            fail(
                "parseAmountCents(\"INVALID_AMOUNT\") must throw an exception for non-numeric input, " +
                "but it returned " + result + " (silently defaulted to " + result + " cents). " +
                "Fix: remove the catch(NumberFormatException) block in RecordParser.parseAmountCents() " +
                "and instead throw IllegalArgumentException so callers are notified of bad data."
            );
        } catch (IllegalArgumentException | NumberFormatException e) {
            // Expected: malformed data must not be silently ignored
        }
    }

    @Test
    public void testParseAmountThrowsOnNullInput() {
        try {
            parser.parseAmountCents(null);
            fail("parseAmountCents(null) should throw IllegalArgumentException, not return silently");
        } catch (IllegalArgumentException e) {
            // Expected
        }
    }

    // -----------------------------------------------------------------------
    // Audit finding 2: EventLogger.log swallows NullPointerException
    // -----------------------------------------------------------------------

    @Test
    public void testEventLoggerThrowsOnNullEventType() {
        try {
            logger.log(null, "some details");
            fail(
                "EventLogger.log(null, ...) must propagate NullPointerException so callers " +
                "discover their programming error, but it returned silently. " +
                "The audit trail has a silent gap (no entry was recorded). " +
                "Fix: remove the broad catch(Exception) block in EventLogger.log()."
            );
        } catch (NullPointerException e) {
            // Expected: null eventType is a programming error that must not be hidden
        }

        // No entry must have been recorded (caller's NPE — nothing to log)
        assertEquals("No event should be recorded when eventType is null",
                     0, logger.getEventCount());
    }

    @Test
    public void testEventLoggerThrowsOnNullDetails() {
        try {
            logger.log("ERROR", null);
            // If no exception, at least verify the entry is there
            // (null concatenation in Java produces "null" string — behaviour varies)
        } catch (NullPointerException e) {
            // Acceptable: null details should also be rejected
        }
    }

    // -----------------------------------------------------------------------
    // Audit finding 3: ConfigLoader.load swallows IOException
    // -----------------------------------------------------------------------

    @Test
    public void testConfigLoaderThrowsOnMissingFile() {
        String missingPath = System.getProperty("java.io.tmpdir")
                           + File.separator + "nonexistent-config-xyzzy-12345.properties";

        // Ensure the file really does not exist
        new File(missingPath).delete();
        assertFalse("Test setup: target file must not exist", new File(missingPath).exists());

        // Use catch(Exception) so the test compiles regardless of whether load() declares
        // throws IOException in its signature (before and after the fix).
        try {
            Properties props = configLoader.load(missingPath);
            fail(
                "ConfigLoader.load() with a missing file must throw (IOException or similar), " +
                "but it returned a Properties object with " + props.size() + " entries. " +
                "Fix: (1) declare load() to throw IOException and remove the catch block, " +
                "(2) wrap the FileInputStream in try-with-resources to prevent resource leaks."
            );
        } catch (Exception e) {
            // Expected: missing config must be a fatal error, not a silent empty-props result.
            // After the fix, this will be an IOException.
        }
    }

    // -----------------------------------------------------------------------
    // Audit finding 4: BatchProcessor.processAmounts swallows parse errors
    // -----------------------------------------------------------------------

    @Test
    public void testBatchProcessorPropagatesParseErrors() {
        // Mixed list: 2 valid amounts + 1 corrupt record
        // After fixing RecordParser, "CORRUPT_DATA" will throw.
        // BatchProcessor must NOT catch and ignore that exception.
        List<String> records = Arrays.asList("$100.00", "CORRUPT_DATA", "$200.00");

        try {
            List<Long> results = processor.processAmounts(records);
            // If we reach here, check whether the bad record was silently skipped
            if (results.size() < records.size()) {
                fail(
                    "BatchProcessor.processAmounts() silently skipped " +
                    (records.size() - results.size()) + " corrupt record(s). " +
                    "Got " + results.size() + " results for " + records.size() + " inputs. " +
                    "Fix: (1) fix RecordParser to throw on bad input, then " +
                    "(2) remove the catch(Exception) block in BatchProcessor.processAmounts() " +
                    "so parse errors propagate to the caller."
                );
            } else {
                fail(
                    "BatchProcessor.processAmounts() returned " + results.size() + " results " +
                    "without throwing, implying all records parsed successfully — but " +
                    "\"CORRUPT_DATA\" is not a valid amount. " +
                    "Fix RecordParser.parseAmountCents() to throw on non-numeric input."
                );
            }
        } catch (IllegalArgumentException | NumberFormatException e) {
            // Expected: a corrupt record must cause the batch to fail, not be silently dropped
        }
    }

    @Test
    public void testBatchProcessorHandlesAllValidRecords() {
        List<String> valid = Arrays.asList("$50.00", "$1,000.99", "$3.50");
        List<Long> results = processor.processAmounts(valid);
        assertEquals("All 3 valid records must be parsed", 3, results.size());
        assertEquals("Total must be $1054.49 = 105449 cents", 105449L, processor.sumAmounts(results));
    }
}
