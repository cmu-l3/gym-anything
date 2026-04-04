package com.example.taskmanager.repository

import com.example.taskmanager.model.Priority
import com.example.taskmanager.model.Task
import com.example.taskmanager.model.TaskStatus
import java.util.Date

/**
 * Repository managing task data (in-memory for this demo).
 *
 * In an MVVM architecture, Activities should NEVER directly hold or
 * interact with the repository. All repository access should go through
 * a ViewModel, which exposes state via LiveData or StateFlow.
 */
class TaskRepository {

    private val tasks = mutableListOf<Task>()

    init {
        // Seed with sample tasks
        tasks.addAll(listOf(
            Task("1", "Design authentication flow", "Create wireframes and spec for login/register", Priority.HIGH, TaskStatus.IN_PROGRESS),
            Task("2", "Write API documentation", "Document all REST endpoints with examples", Priority.MEDIUM, TaskStatus.PENDING),
            Task("3", "Fix login crash on Android 12", "NullPointerException in LoginActivity.onCreate", Priority.CRITICAL, TaskStatus.PENDING),
            Task("4", "Code review: payment module", "Review PR #247 for security issues", Priority.HIGH, TaskStatus.PENDING),
            Task("5", "Update dependencies to latest", "Check for security vulnerabilities", Priority.LOW, TaskStatus.PENDING),
            Task("6", "Performance profiling", "Profile app startup time and reduce to <2s", Priority.MEDIUM, TaskStatus.PENDING),
            Task("7", "Write unit tests for CartManager", "Target 80% coverage", Priority.HIGH, TaskStatus.IN_PROGRESS),
            Task("8", "Localize app for Spanish market", "Translate all strings.xml entries", Priority.MEDIUM, TaskStatus.PENDING)
        ))
    }

    fun getAllTasks(): List<Task> = tasks.toList()

    fun getTaskById(id: String): Task? = tasks.find { it.id == id }

    fun getTasksByStatus(status: TaskStatus): List<Task> =
        tasks.filter { it.status == status }

    fun getTasksByPriority(priority: Priority): List<Task> =
        tasks.filter { it.priority == priority }

    fun addTask(task: Task): Boolean {
        if (task.title.isBlank()) return false
        tasks.add(task)
        return true
    }

    fun updateTask(updated: Task): Boolean {
        val index = tasks.indexOfFirst { it.id == updated.id }
        if (index < 0) return false
        tasks[index] = updated
        return true
    }

    fun deleteTask(id: String): Boolean =
        tasks.removeAll { it.id == id }

    fun getOverdueTasks(): List<Task> =
        tasks.filter { it.isOverdue }

    fun getCompletionStats(): Map<TaskStatus, Int> =
        TaskStatus.values().associateWith { status ->
            tasks.count { it.status == status }
        }

    fun getTotalEstimatedHours(): Double =
        tasks.sumOf { it.estimatedHours }

    fun searchTasks(query: String): List<Task> =
        tasks.filter {
            it.title.contains(query, ignoreCase = true) ||
            it.description.contains(query, ignoreCase = true) ||
            it.tags.any { tag -> tag.contains(query, ignoreCase = true) }
        }
}
