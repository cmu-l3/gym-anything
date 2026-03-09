# Task: Migrate AsyncTask to Kotlin Coroutines

## Overview
The FeedReaderApp uses the deprecated `AsyncTask` API for all background work. Migrate all four `AsyncTask` implementations to Kotlin Coroutines.

## Current Problem
```kotlin
// FeedActivity.kt — deprecated pattern
FetchArticlesTask(repository) { articles ->
    displayArticles(articles)
}.execute(currentCategory)

// FetchArticlesTask.kt — deprecated class
@Suppress("DEPRECATION")
class FetchArticlesTask(
    private val repository: ArticleRepository,
    private val callback: (List<Article>) -> Unit
) : AsyncTask<String, Void, List<Article>?>() {
    override fun doInBackground(vararg params: String): List<Article>? = ...
    override fun onPostExecute(result: List<Article>?) { callback(result ?: emptyList()) }
}
```

## Required Changes

### 1. app/build.gradle.kts
Add coroutines dependency:
```kotlin
implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
```

### 2. ArticleRepository.kt
Convert blocking methods to suspend functions:
```kotlin
suspend fun fetchArticles(category: String): List<Article> {
    return withContext(Dispatchers.IO) { /* network call */ }
}
```

### 3. Remove/Replace AsyncTask classes
- FetchArticlesTask, SaveArticleTask, SearchArticlesTask, LoadSavedTask
- Each should become a coroutine launch in the Activity or a suspend function

### 4. Activity call sites (FeedActivity, SearchActivity)
```kotlin
// Replace execute() with coroutines
lifecycleScope.launch {
    val articles = withContext(Dispatchers.IO) { repository.fetchArticles(category) }
    displayArticles(articles)
}
```

## Scoring
- Coroutines dependency in build.gradle.kts: 15 pts
- AsyncTask classes removed/replaced: 25 pts
- lifecycleScope.launch or similar coroutine launch in Activities: 20 pts
- Repository methods are suspend or use withContext: 20 pts
- Project compiles: 20 pts

Pass threshold: 70/100
