package com.example.feedreader.ui

import android.content.Intent
import android.os.Bundle
import android.view.Menu
import android.view.MenuItem
import android.view.View
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.example.feedreader.R
import com.example.feedreader.model.Article
import com.example.feedreader.task.FetchArticlesTask
import com.example.feedreader.task.SaveArticleTask

/**
 * Main feed screen showing articles by category.
 *
 * PROBLEM: Uses deprecated AsyncTask for all async operations.
 * - FetchArticlesTask is started in onCreate (blocks if rotated mid-fetch)
 * - No lifecycle awareness — tasks may call back into destroyed activities
 * - Cannot cancel ongoing tasks when user navigates away
 *
 * Migration target: Use coroutine scope + asynchronous functionctions.
 */
class FeedActivity : AppCompatActivity() {

    private lateinit var recyclerView: RecyclerView
    private lateinit var progressBar: ProgressBar
    private lateinit var tvEmpty: TextView

    private var currentCategory = "all"

    // Hold reference to detect if task completed after activity destroyed
    @Suppress("DEPRECATION")
    private var fetchTask: FetchArticlesTask? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_feed)

        recyclerView = findViewById(R.id.rv_articles)
        progressBar = findViewById(R.id.progress_bar)
        tvEmpty = findViewById(R.id.tv_empty)

        recyclerView.layoutManager = LinearLayoutManager(this)

        loadArticles(currentCategory)
    }

    private fun loadArticles(category: String) {
        progressBar.visibility = View.VISIBLE
        tvEmpty.visibility = View.GONE

        // DEPRECATED AsyncTask usage — replace with coroutine scope
        @Suppress("DEPRECATION")
        fetchTask = FetchArticlesTask(
            onSuccess = { articles ->
                progressBar.visibility = View.GONE
                if (articles.isEmpty()) {
                    tvEmpty.visibility = View.VISIBLE
                } else {
                    recyclerView.adapter = ArticleAdapter(articles) { article ->
                        openArticle(article)
                    }
                }
            },
            onError = { error ->
                progressBar.visibility = View.GONE
                Toast.makeText(this, "Error: $error", Toast.LENGTH_LONG).show()
            }
        )
        @Suppress("DEPRECATION")
        fetchTask!!.execute(category)
    }

    private fun saveArticle(article: Article) {
        // DEPRECATED AsyncTask usage — replace with coroutine scope
        @Suppress("DEPRECATION")
        SaveArticleTask { success ->
            val msg = if (success) "Article saved" else "Already saved"
            Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()
        }.execute(article)
    }

    private fun openArticle(article: Article) {
        val intent = Intent(this, ArticleDetailActivity::class.java).apply {
            putExtra("article_id", article.id)
            putExtra("article_title", article.title)
            putExtra("article_content", article.content)
            putExtra("article_author", article.author)
        }
        startActivity(intent)
    }

    override fun onDestroy() {
        super.onDestroy()
        // Must cancel task — but AsyncTask cancellation is unreliable
        @Suppress("DEPRECATION")
        fetchTask?.cancel(true)
    }

    override fun onCreateOptionsMenu(menu: Menu): Boolean {
        menuInflater.inflate(R.menu.feed_menu, menu)
        return true
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        return when (item.itemId) {
            R.id.action_search -> {
                startActivity(Intent(this, SearchActivity::class.java))
                true
            }
            else -> super.onOptionsItemSelected(item)
        }
    }
}
