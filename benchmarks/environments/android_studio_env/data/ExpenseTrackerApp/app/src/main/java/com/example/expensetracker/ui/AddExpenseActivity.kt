package com.example.expensetracker.ui

import android.os.Bundle
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.EditText
import android.widget.Spinner
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.example.expensetracker.R
import com.example.expensetracker.data.Expense
import com.example.expensetracker.data.ExpenseRepository
import com.example.expensetracker.services.CurrencyService
import com.example.expensetracker.services.SettingsManager

/**
 * Screen for adding new expenses.
 *
 * PROBLEM: Creates the same dependencies that MainActivity already created.
 * No shared instances — each Activity creates its own copy.
 * Hilt would ensure a single shared instance is injected everywhere.
 */
class AddExpenseActivity : AppCompatActivity() {

    // Duplicate dependency creation — same as MainActivity
    private val currencyService = CurrencyService.getInstance()
    private lateinit var repository: ExpenseRepository
    private lateinit var settingsManager: SettingsManager

    private lateinit var etDescription: EditText
    private lateinit var etAmount: EditText
    private lateinit var spinnerCategory: Spinner
    private lateinit var spinnerCurrency: Spinner
    private lateinit var etNotes: EditText
    private lateinit var btnSave: Button

    private val categories = listOf(
        "Food & Dining", "Transportation", "Housing", "Entertainment",
        "Healthcare", "Education", "Shopping", "Travel", "Utilities", "Other"
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_add_expense)

        // Again, manual creation — these should be @DI_inject annotated fields
        repository = ExpenseRepository(applicationContext, currencyService)
        settingsManager = SettingsManager(applicationContext)

        etDescription = findViewById(R.id.et_description)
        etAmount = findViewById(R.id.et_amount)
        spinnerCategory = findViewById(R.id.spinner_category)
        spinnerCurrency = findViewById(R.id.spinner_currency)
        etNotes = findViewById(R.id.et_notes)
        btnSave = findViewById(R.id.btn_save)

        spinnerCategory.adapter = ArrayAdapter(
            this, android.R.layout.simple_spinner_item, categories
        ).apply { setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item) }

        val currencies = currencyService.getSupportedCurrencies()
        spinnerCurrency.adapter = ArrayAdapter(
            this, android.R.layout.simple_spinner_item, currencies
        ).apply { setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item) }

        val defaultCurrency = settingsManager.getDefaultCurrency()
        val defaultIndex = currencies.indexOf(defaultCurrency)
        if (defaultIndex >= 0) spinnerCurrency.setSelection(defaultIndex)

        btnSave.setOnClickListener { saveExpense() }
    }

    private fun saveExpense() {
        val description = etDescription.text.toString().trim()
        val amountStr = etAmount.text.toString().trim()
        val category = spinnerCategory.selectedItem?.toString() ?: ""
        val currency = spinnerCurrency.selectedItem?.toString() ?: "USD"
        val notes = etNotes.text.toString().trim()

        if (description.isBlank()) {
            etDescription.error = "Description is required"
            return
        }

        val amount = amountStr.toDoubleOrNull()
        if (amount == null || amount <= 0) {
            etAmount.error = "Enter a valid positive amount"
            return
        }

        val expense = Expense(
            description = description,
            amount = amount,
            category = category,
            currency = currency,
            notes = notes
        )

        if (repository.addExpense(expense)) {
            Toast.makeText(this, "Expense saved successfully", Toast.LENGTH_SHORT).show()
            finish()
        } else {
            Toast.makeText(this, "Failed to save expense", Toast.LENGTH_SHORT).show()
        }
    }
}
