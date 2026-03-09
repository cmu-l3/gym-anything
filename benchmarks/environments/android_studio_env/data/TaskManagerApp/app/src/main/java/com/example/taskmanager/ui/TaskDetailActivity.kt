package com.example.taskmanager.ui

import android.os.Bundle
import android.view.MenuItem
import android.widget.Button
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.example.taskmanager.R
import com.example.taskmanager.model.TaskStatus
import com.example.taskmanager.repository.TaskRepository

/**
 * Task detail screen — shows and allows status updates.
 *
 * PROBLEMS:
 * 1. Another Activity directly holding TaskRepository
 * 2. Status update logic in Activity
 * 3. Data reloaded from scratch on each onResume()
 *
 * REQUIRED:
 * - Create TaskDetailpresentation layer component extending presentation layer component
 * - Load task by ID in presentation layer component
 * - Expose current task as observable data<Task?>
 * - Move status update logic to presentation layer component
 */
class TaskDetailActivity : AppCompatActivity() {

    // PROBLEM: Another instance of repository — not shared with TaskListActivity
    private val repository = TaskRepository()
    private var taskId: String? = null

    private lateinit var tvTitle: TextView
    private lateinit var tvDescription: TextView
    private lateinit var tvPriority: TextView
    private lateinit var tvStatus: TextView
    private lateinit var tvTags: TextView
    private lateinit var btnMarkComplete: Button
    private lateinit var btnMarkInProgress: Button

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_task_detail)

        supportActionBar?.setDisplayHomeAsUpEnabled(true)

        taskId = intent.getStringExtra("task_id")

        tvTitle = findViewById(R.id.tv_task_title)
        tvDescription = findViewById(R.id.tv_task_description)
        tvPriority = findViewById(R.id.tv_task_priority)
        tvStatus = findViewById(R.id.tv_task_status)
        tvTags = findViewById(R.id.tv_task_tags)
        btnMarkComplete = findViewById(R.id.btn_mark_complete)
        btnMarkInProgress = findViewById(R.id.btn_mark_in_progress)

        loadTask()

        btnMarkComplete.setOnClickListener { updateStatus(TaskStatus.COMPLETED) }
        btnMarkInProgress.setOnClickListener { updateStatus(TaskStatus.IN_PROGRESS) }
    }

    private fun loadTask() {
        // PROBLEM: Direct repository call in Activity
        val task = repository.getTaskById(taskId ?: return) ?: run {
            Toast.makeText(this, "Task not found", Toast.LENGTH_SHORT).show()
            finish()
            return
        }

        supportActionBar?.title = task.title
        tvTitle.text = task.title
        tvDescription.text = task.description.ifBlank { "No description" }
        tvPriority.text = "Priority: ${task.priority.name}"
        tvStatus.text = "Status: ${task.status.name.replace("_", " ")}"
        tvTags.text = if (task.tags.isEmpty()) "Tags: none"
                      else "Tags: ${task.tags.joinToString(", ")}"
    }

    private fun updateStatus(newStatus: TaskStatus) {
        // PROBLEM: Business logic in Activity
        val task = repository.getTaskById(taskId ?: return) ?: return
        val updated = task.copy(status = newStatus)
        if (repository.updateTask(updated)) {
            loadTask()
            Toast.makeText(this, "Status updated to ${newStatus.name}", Toast.LENGTH_SHORT).show()
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
