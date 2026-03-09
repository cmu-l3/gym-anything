package com.example.calculator

import android.os.Bundle
import android.widget.Button
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

/**
 * Main activity for the calculator application.
 *
 * Provides a simple calculator UI with basic arithmetic operations.
 * Uses [CalcEngine] for all calculations.
 */
class CalcActivity : AppCompatActivity() {

    private lateinit var calcEngine: CalcEngine
    private lateinit var displayView: TextView
    private lateinit var historyView: TextView

    private var currentInput: String = ""
    private var firstOperand: Double? = null
    private var pendingOperation: String? = null
    private var clearOnNextInput: Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_calc)

        calcEngine = CalcEngine()
        displayView = findViewById(R.id.display)
        historyView = findViewById(R.id.history)

        setupNumberButtons()
        setupOperatorButtons()
        setupSpecialButtons()

        updateDisplay("0")
    }

    private fun setupNumberButtons() {
        val numberButtonIds = listOf(
            R.id.btn_0, R.id.btn_1, R.id.btn_2, R.id.btn_3, R.id.btn_4,
            R.id.btn_5, R.id.btn_6, R.id.btn_7, R.id.btn_8, R.id.btn_9
        )

        for ((index, buttonId) in numberButtonIds.withIndex()) {
            findViewById<Button>(buttonId).setOnClickListener {
                onNumberPressed(index.toString())
            }
        }

        findViewById<Button>(R.id.btn_decimal).setOnClickListener {
            onDecimalPressed()
        }
    }

    private fun setupOperatorButtons() {
        findViewById<Button>(R.id.btn_add).setOnClickListener { onOperatorPressed("+") }
        findViewById<Button>(R.id.btn_subtract).setOnClickListener { onOperatorPressed("-") }
        findViewById<Button>(R.id.btn_multiply).setOnClickListener { onOperatorPressed("×") }
        findViewById<Button>(R.id.btn_divide).setOnClickListener { onOperatorPressed("÷") }
        findViewById<Button>(R.id.btn_equals).setOnClickListener { onEqualsPressed() }
    }

    private fun setupSpecialButtons() {
        findViewById<Button>(R.id.btn_clear).setOnClickListener { onClearPressed() }
        findViewById<Button>(R.id.btn_negate).setOnClickListener { onNegatePressed() }
        findViewById<Button>(R.id.btn_percent).setOnClickListener { onPercentPressed() }
    }

    private fun onNumberPressed(digit: String) {
        if (clearOnNextInput) {
            currentInput = ""
            clearOnNextInput = false
        }
        currentInput += digit
        updateDisplay(currentInput)
    }

    private fun onDecimalPressed() {
        if (clearOnNextInput) {
            currentInput = "0"
            clearOnNextInput = false
        }
        if (!currentInput.contains(".")) {
            if (currentInput.isEmpty()) {
                currentInput = "0"
            }
            currentInput += "."
            updateDisplay(currentInput)
        }
    }

    private fun onOperatorPressed(operator: String) {
        if (currentInput.isNotEmpty()) {
            if (firstOperand != null && pendingOperation != null) {
                onEqualsPressed()
            }
            firstOperand = currentInput.toDoubleOrNull()
            pendingOperation = operator
            clearOnNextInput = true
        }
    }

    private fun onEqualsPressed() {
        val second = currentInput.toDoubleOrNull() ?: return
        val first = firstOperand ?: return
        val operation = pendingOperation ?: return

        try {
            val result = when (operation) {
                "+" -> calcEngine.doAdd(first, second)
                "-" -> calcEngine.doSub(first, second)
                "×" -> calcEngine.doMul(first, second)
                "÷" -> calcEngine.doDiv(first, second)
                else -> return
            }

            currentInput = formatResult(result)
            updateDisplay(currentInput)
            updateHistory()
            firstOperand = null
            pendingOperation = null
            clearOnNextInput = true
        } catch (e: ArithmeticException) {
            updateDisplay("Error")
            currentInput = ""
            firstOperand = null
            pendingOperation = null
            clearOnNextInput = true
        }
    }

    private fun onClearPressed() {
        currentInput = ""
        firstOperand = null
        pendingOperation = null
        clearOnNextInput = false
        calcEngine.doReset()
        updateDisplay("0")
        historyView.text = ""
    }

    private fun onNegatePressed() {
        val value = currentInput.toDoubleOrNull() ?: return
        val negated = calcEngine.doNeg(value)
        currentInput = formatResult(negated)
        updateDisplay(currentInput)
    }

    private fun onPercentPressed() {
        val value = currentInput.toDoubleOrNull() ?: return
        val result = calcEngine.doDiv(value, 100.0)
        currentInput = formatResult(result)
        updateDisplay(currentInput)
    }

    private fun updateDisplay(text: String) {
        displayView.text = text
    }

    private fun updateHistory() {
        val history = calcEngine.getHist()
        historyView.text = history.takeLast(5).joinToString("\n")
    }

    private fun formatResult(value: Double): String {
        return if (value == value.toLong().toDouble()) {
            value.toLong().toString()
        } else {
            String.format("%.8g", value)
        }
    }
}
