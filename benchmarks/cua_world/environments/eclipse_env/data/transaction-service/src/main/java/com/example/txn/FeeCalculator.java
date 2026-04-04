package com.example.txn;

import com.example.txn.model.Account;
import com.example.txn.model.AccountType;
import com.example.txn.model.TransactionType;

import java.math.BigDecimal;
import java.math.RoundingMode;

/**
 * Calculates transaction fees based on account type and transaction type.
 */
public class FeeCalculator {

    private static final BigDecimal TRANSFER_FEE_RATE_CHECKING = new BigDecimal("0.005");  // 0.5%
    private static final BigDecimal TRANSFER_FEE_RATE_SAVINGS  = new BigDecimal("0.002");  // 0.2%
    private static final BigDecimal WITHDRAWAL_FEE_CHECKING    = new BigDecimal("1.50");
    private static final BigDecimal WITHDRAWAL_FEE_SAVINGS     = new BigDecimal("0.00");
    private static final BigDecimal MIN_FEE                    = new BigDecimal("0.00");
    private static final BigDecimal MAX_TRANSFER_FEE           = new BigDecimal("25.00");

    /**
     * Calculate the fee for a given transaction.
     *
     * @param account     The source account
     * @param txnType     Type of transaction
     * @param amount      Transaction amount
     * @return Fee amount (>= 0)
     */
    public BigDecimal calculateFee(Account account, TransactionType txnType, BigDecimal amount) {
        if (account == null || txnType == null || amount == null) return BigDecimal.ZERO;

        AccountType accountType = account.getType();

        switch (txnType) {
            case TRANSFER:
                return calculateTransferFee(accountType, amount);
            case WITHDRAWAL:
                return calculateWithdrawalFee(accountType);
            case DEPOSIT:
            case FEE_CHARGE:
                return BigDecimal.ZERO;
            default:
                return BigDecimal.ZERO;
        }
    }

    private BigDecimal calculateTransferFee(AccountType type, BigDecimal amount) {
        BigDecimal rate = (type == AccountType.SAVINGS)
            ? TRANSFER_FEE_RATE_SAVINGS
            : TRANSFER_FEE_RATE_CHECKING;
        BigDecimal fee = amount.multiply(rate).setScale(2, RoundingMode.HALF_UP);
        // Cap fee at maximum
        if (fee.compareTo(MAX_TRANSFER_FEE) > 0) return MAX_TRANSFER_FEE;
        return fee.compareTo(MIN_FEE) < 0 ? MIN_FEE : fee;
    }

    private BigDecimal calculateWithdrawalFee(AccountType type) {
        return (type == AccountType.SAVINGS) ? WITHDRAWAL_FEE_SAVINGS : WITHDRAWAL_FEE_CHECKING;
    }
}
