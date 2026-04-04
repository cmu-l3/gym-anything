package com.example.taskmanager.ui

import android.graphics.Color
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import com.example.taskmanager.R
import com.example.taskmanager.model.Priority
import com.example.taskmanager.model.Task
import com.example.taskmanager.model.TaskStatus

class TaskAdapter(
    private val tasks: List<Task>,
    private val onTaskClick: (Task) -> Unit
) : RecyclerView.Adapter<TaskAdapter.TaskViewHolder>() {

    class TaskViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val tvTitle: TextView = view.findViewById(R.id.tv_task_item_title)
        val tvPriority: TextView = view.findViewById(R.id.tv_task_item_priority)
        val tvStatus: TextView = view.findViewById(R.id.tv_task_item_status)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): TaskViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_task, parent, false)
        return TaskViewHolder(view)
    }

    override fun onBindViewHolder(holder: TaskViewHolder, position: Int) {
        val task = tasks[position]
        holder.tvTitle.text = task.title
        holder.tvPriority.text = task.priority.name
        holder.tvStatus.text = task.status.name.replace("_", " ")

        val priorityColor = when (task.priority) {
            Priority.CRITICAL -> Color.parseColor("#D32F2F")
            Priority.HIGH -> Color.parseColor("#F57C00")
            Priority.MEDIUM -> Color.parseColor("#1976D2")
            Priority.LOW -> Color.parseColor("#388E3C")
        }
        holder.tvPriority.setTextColor(priorityColor)

        if (task.status == TaskStatus.COMPLETED) {
            holder.tvTitle.alpha = 0.5f
        }

        holder.itemView.setOnClickListener { onTaskClick(task) }
    }

    override fun getItemCount() = tasks.size
}
