package com.example.taskmanager.ui

import android.content.Intent
import android.os.Bundle
import android.view.Menu
import android.view.MenuItem
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.example.taskmanager.R
import com.example.taskmanager.model.Priority
import com.example.taskmanager.model.Task
import com.example.taskmanager.model.TaskStatus
import com.example.taskmanager.repository.TaskRepository
import com.google.android.material.floatingactionbutton.FloatingActionButton

/**
 * Main task list screen — God Activity anti-pattern.
 *
 * PROBLEMS with current implementation:
 * 1. Holds TaskRepository directly (should be in presentation layer component)
 * 2. Business logic (filtering, sorting, stats) is in the Activity
 * 3. State is lost on configuration change (rotation destroys activity)
 * 4. No separation of concerns — UI and data logic are mixed
 * 5. Not testable without starting the full Activity
 *
 * REQUIRED REFACTORING:
 * - Create TaskListpresentation layer component extending presentation layer component
 * - Move repository interactions to presentation layer component
 * - Expose task list as observable data<List<Task>> from presentation layer component
 * - Move filtering/sorting logic to presentation layer component
 * - Observe observable data in onCreate with lifecycle awareness
 * - Use presentation layer componentProvider or by presentation component provider to obtain presentation layer component
 */
class TaskListActivity : AppCompatActivity() {

    // PROBLEM: Repository held directly in Activity
    private val repository = TaskRepository()

    private lateinit var recyclerView: RecyclerView
    private lateinit var tvStats: TextView
    private lateinit var fab: FloatingActionButton

    private var currentFilter: TaskStatus? = null
    private var sortByPriority = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_task_list)

        recyclerView = findViewById(R.id.rv_tasks)
        tvStats = findViewById(R.id.tv_stats)
        fab = findViewById(R.id.fab_add_task)

        recyclerView.layoutManager = LinearLayoutManager(this)

        fab.setOnClickListener {
            startActivity(Intent(this, AddTaskActivity::class.java))
        }

        // PROBLEM: All business logic in Activity
        loadAndDisplayTasks()
    }

    private fun loadAndDisplayTasks() {
        // PROBLEM: Business logic in Activity — should be in presentation layer component
        var tasks = if (currentFilter != null) {
            repository.getTasksByStatus(currentFilter!!)
        } else {
            repository.getAllTasks()
        }

        if (sortByPriority) {
            tasks = tasks.sortedByDescending { it.priority.ordinal }
        }

        // PROBLEM: Stats computation in Activity
        val stats = repository.getCompletionStats()
        val completed = stats[TaskStatus.COMPLETED] ?: 0
        val total = repository.getAllTasks().size
        val overdue = repository.getOverdueTasks().size
        val totalHours = repository.getTotalEstimatedHours()

        tvStats.text = "Tasks: $total | Done: $completed | Overdue: $overdue | Est: ${totalHours}h"

        recyclerView.adapter = TaskAdapter(tasks) { task ->
            openTaskDetail(task)
        }
    }

    private fun openTaskDetail(task: Task) {
        val intent = Intent(this, TaskDetailActivity::class.java)
        intent.putExtra("task_id", task.id)
        startActivity(intent)
    }

    override fun onResume() {
        super.onResume()
        // PROBLEM: Re-querying repository directly in Activity lifecycle
        loadAndDisplayTasks()
    }

    override fun onCreateOptionsMenu(menu: Menu): Boolean {
        menuInflater.inflate(R.menu.task_list_menu, menu)
        return true
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        return when (item.itemId) {
            R.id.action_filter_pending -> {
                currentFilter = TaskStatus.PENDING
                loadAndDisplayTasks()
                true
            }
            R.id.action_filter_progress -> {
                currentFilter = TaskStatus.IN_PROGRESS
                loadAndDisplayTasks()
                true
            }
            R.id.action_filter_all -> {
                currentFilter = null
                loadAndDisplayTasks()
                true
            }
            R.id.action_sort_priority -> {
                sortByPriority = !sortByPriority
                loadAndDisplayTasks()
                true
            }
            else -> super.onOptionsItemSelected(item)
        }
    }
}
