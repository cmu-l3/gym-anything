package com.example.feedreader.task

import android.os.AsyncTask
import com.example.feedreader.model.Article
import com.example.feedreader.repository.ArticleRepository

/**
 * AsyncTask for searching articles by a query string.
 *
 * DEPRECATED: Must be replaced with Kotlin coroutines.
 * Use: coroutine scope { results = repository.search(query) }
 * Cancel previous search when new query arrives using Job cancellation.
 */
@Suppress("DEPRECATION")
class SearchArticlesTask(
    private val onResults: (List<Article>) -> Unit,
    private val onError: (String) -> Unit = {}
) : AsyncTask<String, Void, List<Article>?>() {

    private var errorMessage: String? = null

    override fun doInBackground(vararg params: String?): List<Article>? {
        return try {
            val query = params.firstOrNull() ?: return emptyList()
            ArticleRepository.getInstance().search(query)
        } catch (e: Exception) {
            errorMessage = e.message
            null
        }
    }

    override fun onPostExecute(result: List<Article>?) {
        if (result != null) {
            onResults(result)
        } else {
            onError(errorMessage ?: "Search failed")
        }
    }
}
