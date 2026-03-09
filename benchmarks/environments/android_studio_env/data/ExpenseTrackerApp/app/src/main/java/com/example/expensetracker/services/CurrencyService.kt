package com.example.expensetracker.services

import javax.inject.Inject
import javax.inject.Singleton

/**
 * Service for currency conversion operations.
 *
 * Currently implemented as a manual singleton (getInstance pattern).
 * After Hilt migration, use @Singleton and @Inject constructor.
 */
class CurrencyService {

    companion object {
        @Volatile
        private var instance: CurrencyService? = null

        /**
         * Manual singleton getter — replace with Hilt @Singleton injection.
         */
        fun getInstance(): CurrencyService =
            instance ?: synchronized(this) {
                instance ?: CurrencyService().also { instance = it }
            }
    }

    // Exchange rates relative to USD (simplified for demo)
    private val rates = mapOf(
        "USD" to 1.0,
        "EUR" to 0.92,
        "GBP" to 0.79,
        "JPY" to 149.5,
        "CAD" to 1.36,
        "AUD" to 1.53,
        "CHF" to 0.88,
        "INR" to 83.1
    )

    fun convert(amount: Double, fromCurrency: String, toCurrency: String): Double {
        val fromRate = rates[fromCurrency] ?: return amount
        val toRate = rates[toCurrency] ?: return amount
        return amount / fromRate * toRate
    }

    fun getSupportedCurrencies(): List<String> = rates.keys.sorted()

    fun getExchangeRate(from: String, to: String): Double {
        val fromRate = rates[from] ?: 1.0
        val toRate = rates[to] ?: 1.0
        return toRate / fromRate
    }
}
