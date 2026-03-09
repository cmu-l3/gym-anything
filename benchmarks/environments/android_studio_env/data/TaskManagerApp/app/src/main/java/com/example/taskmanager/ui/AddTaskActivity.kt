package com.example.taskmanager.ui

import android.os.Bundle
import android.view.MenuItem
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.EditText
import android.widget.Spinner
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.example.taskmanager.R
import com.example.taskmanager.model.Priority
import com.example.taskmanager.model.Task
import com.example.taskmanager.repository.TaskRepository

/**
 * Screen for adding new tasks — God Activity pattern.
 *
 * PROBLEMS:
 * 1. Validation logic in Activity (should be in presentation layer component)
 * 2. Repository directly referenced in Activity
 * 3. No presentation layer component for state preservation on rotation
 *
 * REQUIRED:
 * - Create AddTaskpresentation layer component extending presentation layer component
 * - Move validation logic (isValidTitle, etc.) to presentation layer component
 * - Expose validation errors as observable data
 * - Move repository call to presentation layer component
 */
class AddTaskActivity : AppCompatActivity() {

    // PROBLEM: Repository directly in Activity
    private val repository = TaskRepository()

    private lateinit var etTitle: EditText
    private lateinit var etDescription: EditText
    private lateinit var spinnerPriority: Spinner
    private lateinit var etEstimatedHours: EditText
    private lateinit var etTags: EditText
    private lateinit var btnSave: Button

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_add_task)

        supportActionBar?.setDisplayHomeAsUpEnabled(true)
        supportActionBar?.title = "New Task"

        etTitle = findViewById(R.id.et_title)
        etDescription = findViewById(R.id.et_description)
        spinnerPriority = findViewById(R.id.spinner_priority)
        etEstimatedHours = findViewById(R.id.et_hours)
        etTags = findViewById(R.id.et_tags)
        btnSave = findViewById(R.id.btn_save_task)

        spinnerPriority.adapter = ArrayAdapter(
            this,
            android.R.layout.simple_spinner_item,
            Priority.values().map { it.name }
        ).apply { setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item) }
        spinnerPriority.setSelection(1) // Default MEDIUM

        btnSave.setOnClickListener { saveTask() }
    }

    private fun saveTask() {
        // PROBLEM: Validation logic in Activity
        val title = etTitle.text.toString().trim()
        if (title.isBlank()) {
            etTitle.error = "Title is required"
            return
        }
        if (title.length < 3) {
            etTitle.error = "Title must be at least 3 characters"
            return
        }
        if (title.length > 100) {
            etTitle.error = "Title must not exceed 100 characters"
            return
        }

        val description = etDescription.text.toString().trim()
        val priority = Priority.values()[spinnerPriority.selectedItemPosition]
        val hoursStr = etEstimatedHours.text.toString().trim()
        val hours = hoursStr.toDoubleOrNull() ?: 0.0
        val tagsInput = etTags.text.toString().trim()
        val tags = if (tagsInput.isBlank()) emptyList()
                   else tagsInput.split(",").map { it.trim() }.filter { it.isNotBlank() }

        // PROBLEM: Repository call in Activity
        val task = Task(
            title = title,
            description = description,
            priority = priority,
            estimatedHours = hours,
            tags = tags
        )

        if (repository.addTask(task)) {
            Toast.makeText(this, "Task created", Toast.LENGTH_SHORT).show()
            finish()
        } else {
            Toast.makeText(this, "Failed to create task", Toast.LENGTH_SHORT).show()
        }
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        return when (item.itemId) {
            android.R.id.home -> {
                onBackPressedDispatcher.onBackPressed()
                true
            }
            else -> super.onOptionsItemSelected(item)
        }
    }
}
