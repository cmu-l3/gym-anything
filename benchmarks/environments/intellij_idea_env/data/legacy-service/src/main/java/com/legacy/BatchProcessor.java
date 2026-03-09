package com.legacy;

import java.util.ArrayList;
import java.util.List;

/**
 * Processes batches of raw record strings by parsing each record and
 * accumulating the results.
 *
 * <p>A batch job processes thousands of records per run.  Any record that
 * cannot be parsed must result in an exception being propagated so the
 * operator knows which batch file is corrupt and can fix it.  Silently
 * skipping bad records causes downstream totals to be wrong and is
 * unacceptable in a financial context.
 */
public class BatchProcessor {

    private final RecordParser parser;
    private final EventLogger  logger;

    public BatchProcessor(RecordParser parser, EventLogger logger) {
        this.parser = parser;
        this.logger = logger;
    }

    /**
     * Parses each raw amount string and returns the list of parsed cent values.
     *
     * <p>BUG: the method wraps {@code parser.parseAmountCents()} in a broad
     * {@code catch (Exception e)} block and silently continues to the next record
     * when parsing fails.  Bad records are dropped without any signal to the caller.
     * The returned list will be shorter than the input list, and totals computed
     * downstream will be silently incorrect.
     *
     * <p>Note: this bug is compounded by the bug in {@link RecordParser#parseAmountCents},
     * which already returns {@code 0L} instead of throwing on bad input.  After
     * fixing {@code RecordParser}, this method must also be fixed to propagate
     * (not swallow) the exceptions that {@code RecordParser} will then throw.
     *
     * <p>Fix: remove the {@code catch} block so that any
     * {@link IllegalArgumentException} from {@code parseAmountCents()} propagates
     * to the caller unchanged.
     *
     * @param rawAmounts list of raw monetary strings to parse
     * @return list of parsed cent values (one entry per input record)
     * @throws IllegalArgumentException if any record fails to parse
     *         <em>(currently swallowed — must be fixed)</em>
     */
    public List<Long> processAmounts(List<String> rawAmounts) {
        List<Long> results = new ArrayList<>();
        for (String raw : rawAmounts) {
            try {
                long cents = parser.parseAmountCents(raw);
                logger.log("PROCESSED", "Parsed amount: " + cents + " cents from '" + raw + "'");
                results.add(cents);
            } catch (Exception e) {
                // BUG: any parse failure is silently swallowed — the bad record is simply skipped
                // Missing: throw new IllegalArgumentException("Failed to process record '" + raw + "'", e);
            }
        }
        return results;
    }

    /**
     * Returns the sum of all amounts in a processed result list.
     *
     * @param amounts list of cent values (output from {@link #processAmounts})
     * @return total in cents
     */
    public long sumAmounts(List<Long> amounts) {
        return amounts.stream().mapToLong(Long::longValue).sum();
    }
}
