package com.example.financialcalc

import android.os.Bundle
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {

    private val loanCalculator = LoanCalculator()
    private val investmentAnalyzer = InvestmentAnalyzer()
    private val budgetPlanner = BudgetPlanner()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        val etPrincipal = findViewById<EditText>(R.id.et_principal)
        val etRate = findViewById<EditText>(R.id.et_rate)
        val etMonths = findViewById<EditText>(R.id.et_months)
        val tvResult = findViewById<TextView>(R.id.tv_result)
        val btnCalculate = findViewById<Button>(R.id.btn_calculate)

        btnCalculate.setOnClickListener {
            try {
                val principal = etPrincipal.text.toString().toDouble()
                val rate = etRate.text.toString().toDouble()
                val months = etMonths.text.toString().toInt()

                val monthly = loanCalculator.calculateMonthlyPayment(principal, rate, months)
                val totalInterest = loanCalculator.calculateTotalInterest(principal, rate, months)

                tvResult.text = buildString {
                    appendLine("Monthly Payment: $${String.format("%.2f", monthly)}")
                    appendLine("Total Interest: $${String.format("%.2f", totalInterest)}")
                    appendLine("Total Cost: $${String.format("%.2f", monthly * months)}")
                }
            } catch (e: Exception) {
                tvResult.text = "Error: ${e.message}"
            }
        }
    }
}
