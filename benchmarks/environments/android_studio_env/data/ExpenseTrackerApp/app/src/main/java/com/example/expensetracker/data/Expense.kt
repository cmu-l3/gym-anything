package com.example.expensetracker.data

import java.util.Date
import java.util.UUID

/**
 * Data model representing a financial expense entry.
 */
data class Expense(
    val id: String = UUID.randomUUID().toString(),
    val description: String,
    val amount: Double,
    val category: String,
    val currency: String = "USD",
    val date: Date = Date(),
    val notes: String = ""
) {
    val isLargeExpense: Boolean get() = amount > 500.0

    fun amountInCurrency(targetCurrency: String, exchangeRate: Double): Double {
        return if (currency == targetCurrency) amount else amount * exchangeRate
    }
}
