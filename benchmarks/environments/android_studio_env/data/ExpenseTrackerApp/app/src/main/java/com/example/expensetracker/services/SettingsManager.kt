package com.example.expensetracker.services

import android.content.Context

/**
 * Manages user settings via SharedPreferences.
 *
 * Currently requires Context — after Hilt migration,
 * inject via @ApplicationContext and bind as singleton.
 */
class SettingsManager(private val context: Context) {

    private val prefs = context.getSharedPreferences("expense_tracker_prefs", Context.MODE_PRIVATE)

    fun getDefaultCurrency(): String = prefs.getString("default_currency", "USD") ?: "USD"

    fun setDefaultCurrency(currency: String) {
        prefs.edit().putString("default_currency", currency).apply()
    }

    fun getMonthlyBudget(): Double = prefs.getFloat("monthly_budget", 2000f).toDouble()

    fun setMonthlyBudget(budget: Double) {
        prefs.edit().putFloat("monthly_budget", budget.toFloat()).apply()
    }

    fun isDarkModeEnabled(): Boolean = prefs.getBoolean("dark_mode", false)

    fun setDarkModeEnabled(enabled: Boolean) {
        prefs.edit().putBoolean("dark_mode", enabled).apply()
    }

    fun getBudgetAlertThreshold(): Double = prefs.getFloat("alert_threshold", 0.8f).toDouble()

    fun setBudgetAlertThreshold(threshold: Double) {
        prefs.edit().putFloat("alert_threshold", threshold.toFloat()).apply()
    }

    fun clearAll() {
        prefs.edit().clear().apply()
    }
}
