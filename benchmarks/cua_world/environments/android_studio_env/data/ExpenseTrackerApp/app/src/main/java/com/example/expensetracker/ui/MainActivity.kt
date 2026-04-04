package com.example.expensetracker.ui

import android.content.Intent
import android.os.Bundle
import android.view.Menu
import android.view.MenuItem
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.example.expensetracker.R
import com.example.expensetracker.data.Expense
import com.example.expensetracker.data.ExpenseRepository
import com.example.expensetracker.services.CurrencyService
import com.example.expensetracker.services.NotificationService
import com.example.expensetracker.services.SettingsManager

/**
 * Main screen showing expense list and monthly summary.
 *
 * PROBLEM: This activity manually creates all dependencies.
 * After Hilt migration, these should be provided by the DI framework.
 */
class MainActivity : AppCompatActivity() {

    // All dependencies created manually — coupling to concrete implementations
    private val currencyService = CurrencyService.getInstance()
    private lateinit var repository: ExpenseRepository
    private lateinit var settingsManager: SettingsManager
    private lateinit var notificationService: NotificationService

    private lateinit var recyclerView: RecyclerView
    private lateinit var tvTotal: TextView
    private lateinit var tvCurrency: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        // Manual dependency creation — all of this should be managed by the DI framework
        repository = ExpenseRepository(applicationContext, currencyService)
        settingsManager = SettingsManager(applicationContext)
        notificationService = NotificationService(applicationContext)

        recyclerView = findViewById(R.id.rv_expenses)
        tvTotal = findViewById(R.id.tv_total)
        tvCurrency = findViewById(R.id.tv_currency)

        recyclerView.layoutManager = LinearLayoutManager(this)
        loadExpenses()
    }

    private fun loadExpenses() {
        val defaultCurrency = settingsManager.getDefaultCurrency()
        val expenses = repository.getAllExpenses()
        val total = expenses.sumOf { expense ->
            repository.convertExpenseAmount(expense, defaultCurrency)
        }

        tvTotal.text = "Total: ${String.format("%.2f", total)}"
        tvCurrency.text = defaultCurrency

        val budget = settingsManager.getMonthlyBudget()
        val threshold = settingsManager.getBudgetAlertThreshold()
        if (total > budget * threshold) {
            notificationService.sendBudgetAlert("Monthly", total, budget)
        }
    }

    override fun onCreateOptionsMenu(menu: Menu): Boolean {
        menuInflater.inflate(R.menu.main_menu, menu)
        return true
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        return when (item.itemId) {
            R.id.action_add -> {
                startActivity(Intent(this, AddExpenseActivity::class.java))
                true
            }
            R.id.action_settings -> {
                startActivity(Intent(this, SettingsActivity::class.java))
                true
            }
            else -> super.onOptionsItemSelected(item)
        }
    }

    override fun onResume() {
        super.onResume()
        loadExpenses()
    }
}
