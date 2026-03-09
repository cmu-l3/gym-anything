package com.example.expensetracker.ui

import android.os.Bundle
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.Spinner
import android.widget.Switch
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.example.expensetracker.R
import com.example.expensetracker.services.CurrencyService
import com.example.expensetracker.services.SettingsManager

/**
 * Settings screen for app preferences.
 *
 * PROBLEM: Third activity manually creating the same dependencies.
 * SettingsManager and CurrencyService instances are not shared
 * because there is no DI framework managing lifecycle.
 */
class SettingsActivity : AppCompatActivity() {

    // Yet another manual instantiation of the same services
    private val currencyService = CurrencyService.getInstance()
    private lateinit var settingsManager: SettingsManager

    private lateinit var spinnerCurrency: Spinner
    private lateinit var switchDarkMode: Switch
    private lateinit var btnSave: Button

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_settings)

        // Should be @DI_inject — but currently created manually
        settingsManager = SettingsManager(applicationContext)

        spinnerCurrency = findViewById(R.id.spinner_currency)
        switchDarkMode = findViewById(R.id.switch_dark_mode)
        btnSave = findViewById(R.id.btn_save_settings)

        val currencies = currencyService.getSupportedCurrencies()
        spinnerCurrency.adapter = ArrayAdapter(
            this, android.R.layout.simple_spinner_item, currencies
        ).apply { setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item) }

        // Restore saved settings
        val savedCurrency = settingsManager.getDefaultCurrency()
        val currencyIndex = currencies.indexOf(savedCurrency)
        if (currencyIndex >= 0) spinnerCurrency.setSelection(currencyIndex)

        switchDarkMode.isChecked = settingsManager.isDarkModeEnabled()

        btnSave.setOnClickListener { saveSettings() }
    }

    private fun saveSettings() {
        val selectedCurrency = spinnerCurrency.selectedItem?.toString() ?: "USD"
        settingsManager.setDefaultCurrency(selectedCurrency)
        settingsManager.setDarkModeEnabled(switchDarkMode.isChecked)
        Toast.makeText(this, "Settings saved", Toast.LENGTH_SHORT).show()
        finish()
    }
}
