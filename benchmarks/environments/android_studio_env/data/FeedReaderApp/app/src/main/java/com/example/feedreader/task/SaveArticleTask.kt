package com.example.feedreader.task

import android.os.AsyncTask
import com.example.feedreader.model.Article
import com.example.feedreader.repository.ArticleRepository

/**
 * AsyncTask for saving an article to local storage.
 *
 * DEPRECATED: Must be replaced with Kotlin coroutines.
 * Use: coroutine scope(background dispatcher) { repository.saveArticle(article) }
 */
@Suppress("DEPRECATION")
class SaveArticleTask(
    private val onComplete: (Boolean) -> Unit = {}
) : AsyncTask<Article, Void, Boolean>() {

    override fun doInBackground(vararg params: Article?): Boolean {
        val article = params.firstOrNull() ?: return false
        return try {
            ArticleRepository.getInstance().saveArticle(article)
        } catch (e: Exception) {
            false
        }
    }

    override fun onPostExecute(result: Boolean) {
        onComplete(result)
    }
}
