package com.example.expensetracker.data

import android.content.Context
import com.example.expensetracker.services.CurrencyService

/**
 * Repository for managing expense data.
 *
 * Currently requires manual construction with Context and CurrencyService.
 * After Hilt migration, this should use constructor injection (@Inject).
 */
class ExpenseRepository(
    private val context: Context,
    private val currencyService: CurrencyService
) {
    private val expenses = mutableListOf<Expense>()

    fun getAllExpenses(): List<Expense> = expenses.toList()

    fun getExpensesByCategory(category: String): List<Expense> =
        expenses.filter { it.category.equals(category, ignoreCase = true) }

    fun addExpense(expense: Expense): Boolean {
        if (expense.amount <= 0 || expense.description.isBlank()) return false
        expenses.add(expense)
        return true
    }

    fun removeExpense(id: String): Boolean =
        expenses.removeAll { it.id == id }

    fun getTotalByCategory(): Map<String, Double> =
        expenses.groupBy { it.category }
            .mapValues { (_, list) -> list.sumOf { it.amount } }

    fun convertExpenseAmount(expense: Expense, targetCurrency: String): Double =
        currencyService.convert(expense.amount, expense.currency, targetCurrency)

    fun clearAll() = expenses.clear()
}
