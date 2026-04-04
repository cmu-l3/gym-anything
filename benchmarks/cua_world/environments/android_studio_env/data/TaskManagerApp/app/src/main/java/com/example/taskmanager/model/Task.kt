package com.example.taskmanager.model

import java.util.Date
import java.util.UUID

enum class Priority { LOW, MEDIUM, HIGH, CRITICAL }
enum class TaskStatus { PENDING, IN_PROGRESS, COMPLETED, CANCELLED }

/**
 * Represents a task in the task management system.
 */
data class Task(
    val id: String = UUID.randomUUID().toString(),
    val title: String,
    val description: String = "",
    val priority: Priority = Priority.MEDIUM,
    val status: TaskStatus = TaskStatus.PENDING,
    val dueDate: Date? = null,
    val createdAt: Date = Date(),
    val tags: List<String> = emptyList(),
    val estimatedHours: Double = 0.0
) {
    val isOverdue: Boolean
        get() = dueDate != null && dueDate.before(Date()) && status != TaskStatus.COMPLETED

    val isComplete: Boolean
        get() = status == TaskStatus.COMPLETED
}
