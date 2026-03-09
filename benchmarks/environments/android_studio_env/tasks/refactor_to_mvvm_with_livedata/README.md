# Task: Refactor to MVVM with LiveData

## Overview
Refactor TaskManagerApp from the "God Activity" anti-pattern to MVVM architecture using Android ViewModel and LiveData.

## Current Problem
Each Activity instantiates its own `TaskRepository` and contains business logic:
```kotlin
// TaskListActivity.kt — God Activity
private val repository = TaskRepository()  // not shared

private fun loadAndDisplayTasks() {
    // filtering in Activity
    var tasks = if (currentFilter != null) {
        repository.getTasksByStatus(currentFilter!!)
    } else {
        repository.getAllTasks()
    }
    // sorting in Activity
    if (sortByPriority) tasks = tasks.sortedByDescending { it.priority.ordinal }
    // stats in Activity
    val stats = repository.getCompletionStats()
    ...
}
```

## Required Changes

### 1. app/build.gradle.kts
```kotlin
implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.7.0")
implementation("androidx.lifecycle:lifecycle-livedata-ktx:2.7.0")
implementation("androidx.activity:activity-ktx:1.8.2")
```

### 2. viewmodel/TaskListViewModel.kt
```kotlin
class TaskListViewModel : ViewModel() {
    private val repository = TaskRepository()
    private val _tasks = MutableLiveData<List<Task>>()
    val tasks: LiveData<List<Task>> = _tasks
    // move filtering, sorting, stats logic here
}
```

### 3. viewmodel/AddTaskViewModel.kt
```kotlin
class AddTaskViewModel : ViewModel() {
    private val repository = TaskRepository()
    private val _errorMessage = MutableLiveData<String?>()
    val errorMessage: LiveData<String?> = _errorMessage
    // move validation logic here
    fun addTask(title: String, description: String, priority: Priority, ...): Boolean
}
```

### 4. viewmodel/TaskDetailViewModel.kt
```kotlin
class TaskDetailViewModel : ViewModel() {
    private val repository = TaskRepository()
    private val _task = MutableLiveData<Task?>()
    val task: LiveData<Task?> = _task
    fun loadTask(id: String)
    fun updateStatus(id: String, newStatus: TaskStatus)
}
```

### 5. Activities — use ViewModel
```kotlin
// TaskListActivity.kt
private val viewModel: TaskListViewModel by viewModels()

override fun onCreate(...) {
    viewModel.tasks.observe(this) { tasks ->
        recyclerView.adapter = TaskAdapter(tasks) { openTaskDetail(it) }
    }
    viewModel.loadTasks()
}
```

## Scoring
- ViewModel deps in build.gradle.kts: 10 pts
- At least one ViewModel class created: 20 pts
- LiveData<> fields exposed from ViewModel: 20 pts
- Activities observe() LiveData: 15 pts
- Repository NOT directly instantiated in Activities: 20 pts
- Project compiles: 15 pts

Pass threshold: 70/100
