package com.payments;

/**
 * Handles fund transfers between accounts. This service is called from multiple
 * threads concurrently and must be safe for simultaneous transfers in all directions.
 *
 * <p>Thread safety requirement: transfers between any pair of accounts must succeed
 * without deadlock, even when executed in opposite directions simultaneously.
 */
public class TransferService {

    private final AuditLogger auditLogger;

    public TransferService(AuditLogger auditLogger) {
        this.auditLogger = auditLogger;
    }

    /**
     * Transfers {@code amountCents} from {@code source} to {@code target}.
     *
     * <p>BUG: Locks are acquired in argument order (source first, then target).
     * If thread A calls {@code transfer(X, Y, ...)} while thread B simultaneously
     * calls {@code transfer(Y, X, ...)}, both threads will acquire one lock and
     * wait indefinitely for the other — a classic deadlock.
     *
     * <p>Fix: acquire locks in a canonical, consistent order regardless of argument
     * order. A common approach is to sort by account ID before locking.
     *
     * @param source       account to debit
     * @param target       account to credit
     * @param amountCents  amount in cents; must be positive
     */
    public void transfer(Account source, Account target, long amountCents) {
        if (source == null || target == null) {
            throw new IllegalArgumentException("Source and target accounts must not be null");
        }
        if (source.getAccountId().equals(target.getAccountId())) {
            throw new IllegalArgumentException("Cannot transfer to the same account");
        }
        if (amountCents <= 0) {
            throw new IllegalArgumentException("Transfer amount must be positive");
        }

        // BUG: lock ordering follows argument order → potential deadlock with reverse transfers
        synchronized (source) {
            synchronized (target) {
                source.withdraw(amountCents);
                target.deposit(amountCents);
                auditLogger.log(String.format(
                    "TRANSFER from=%s to=%s amount=%d cents",
                    source.getAccountId(), target.getAccountId(), amountCents
                ));
            }
        }
    }

    public AuditLogger getAuditLogger() {
        return auditLogger;
    }
}
