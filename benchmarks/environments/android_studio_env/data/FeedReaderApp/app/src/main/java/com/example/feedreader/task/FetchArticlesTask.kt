package com.example.feedreader.task

import android.os.AsyncTask
import com.example.feedreader.model.Article
import com.example.feedreader.repository.ArticleRepository

/**
 * AsyncTask for fetching articles by category from the repository.
 *
 * DEPRECATED: AsyncTask is deprecated since API 30.
 * This entire class must be replaced with Kotlin coroutines:
 *   - The Activity should use coroutine scope { ... }
 *   - ArticleRepository.fetchByCategory() must become asynchronous function
 *   - background dispatcher should wrap the blocking call
 */
@Suppress("DEPRECATION")
class FetchArticlesTask(
    private val onSuccess: (List<Article>) -> Unit,
    private val onError: (String) -> Unit = {}
) : AsyncTask<String, Void, List<Article>?>() {

    private var errorMessage: String? = null

    override fun doInBackground(vararg params: String?): List<Article>? {
        return try {
            val category = params.firstOrNull() ?: "all"
            ArticleRepository.getInstance().fetchByCategory(category)
        } catch (e: Exception) {
            errorMessage = e.message ?: "Unknown error"
            null
        }
    }

    override fun onPostExecute(result: List<Article>?) {
        if (result != null) {
            onSuccess(result)
        } else {
            onError(errorMessage ?: "Failed to fetch articles")
        }
    }
}
