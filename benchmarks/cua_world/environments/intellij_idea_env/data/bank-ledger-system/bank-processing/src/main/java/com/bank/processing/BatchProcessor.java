package com.bank.processing;

import com.bank.commons.Transaction;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * Processes batches of transactions, collecting results and providing summaries.
 * Delegates individual transaction processing to TransactionProcessor.
 */
public class BatchProcessor {

    private final TransactionProcessor processor;

    public BatchProcessor(TransactionProcessor processor) {
        this.processor = processor;
    }

    /**
     * Processes a batch of transactions and returns a summary of results.
     *
     * @param transactions the list of transactions to process
     * @return a BatchResult with counts and details of successes and failures
     */
    public BatchResult processBatch(List<Transaction> transactions) {
        int succeeded = 0;
        int failed = 0;
        List<String> failedIds = new ArrayList<>();

        for (Transaction tx : transactions) {
            boolean result;
            switch (tx.getType()) {
                case DEPOSIT:
                    result = processor.processDeposit(tx);
                    break;
                case WITHDRAWAL:
                    result = processor.processWithdrawal(tx);
                    break;
                case TRANSFER:
                    result = processor.processTransfer(tx);
                    break;
                default:
                    result = false;
            }

            if (result) {
                succeeded++;
            } else {
                failed++;
                failedIds.add(tx.getTransactionId());
            }
        }

        return new BatchResult(succeeded, failed, failedIds);
    }

    /**
     * Summary of a batch processing run.
     */
    public static class BatchResult {
        private final int succeeded;
        private final int failed;
        private final List<String> failedTransactionIds;

        public BatchResult(int succeeded, int failed, List<String> failedTransactionIds) {
            this.succeeded = succeeded;
            this.failed = failed;
            this.failedTransactionIds = Collections.unmodifiableList(new ArrayList<>(failedTransactionIds));
        }

        public int getSucceeded() { return succeeded; }
        public int getFailed() { return failed; }
        public List<String> getFailedTransactionIds() { return failedTransactionIds; }

        @Override
        public String toString() {
            return String.format("BatchResult{succeeded=%d, failed=%d}", succeeded, failed);
        }
    }
}
