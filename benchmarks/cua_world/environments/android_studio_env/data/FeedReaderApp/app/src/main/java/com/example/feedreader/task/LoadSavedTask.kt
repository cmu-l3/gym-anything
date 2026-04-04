package com.example.feedreader.task

import android.os.AsyncTask
import com.example.feedreader.model.Article
import com.example.feedreader.repository.ArticleRepository

/**
 * AsyncTask for loading saved articles from local storage.
 *
 * DEPRECATED: Must be replaced with Kotlin coroutines.
 */
@Suppress("DEPRECATION")
class LoadSavedTask(
    private val onLoaded: (List<Article>) -> Unit
) : AsyncTask<Void, Void, List<Article>>() {

    override fun doInBackground(vararg params: Void?): List<Article> {
        return try {
            ArticleRepository.getInstance().getSavedArticles()
        } catch (e: Exception) {
            emptyList()
        }
    }

    override fun onPostExecute(result: List<Article>) {
        onLoaded(result)
    }
}
