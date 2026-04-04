package com.example.feedreader.ui

import android.os.Bundle
import android.view.MenuItem
import android.widget.Button
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.example.feedreader.R
import com.example.feedreader.model.Article
import com.example.feedreader.repository.ArticleRepository
import com.example.feedreader.task.SaveArticleTask
import java.util.UUID

/**
 * Article detail view with save functionality.
 *
 * PROBLEM: Uses deprecated AsyncTask for save operation.
 */
class ArticleDetailActivity : AppCompatActivity() {

    private lateinit var tvTitle: TextView
    private lateinit var tvAuthor: TextView
    private lateinit var tvContent: TextView
    private lateinit var btnSave: Button

    private var currentArticle: Article? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_article_detail)

        supportActionBar?.setDisplayHomeAsUpEnabled(true)

        tvTitle = findViewById(R.id.tv_title)
        tvAuthor = findViewById(R.id.tv_author)
        tvContent = findViewById(R.id.tv_content)
        btnSave = findViewById(R.id.btn_save_article)

        val title = intent.getStringExtra("article_title") ?: "Unknown"
        val content = intent.getStringExtra("article_content") ?: ""
        val author = intent.getStringExtra("article_author") ?: "Unknown"
        val id = intent.getStringExtra("article_id") ?: UUID.randomUUID().toString()

        currentArticle = Article(id, title, "Summary", content, author, "general")

        tvTitle.text = title
        tvAuthor.text = "By: $author"
        tvContent.text = content

        btnSave.setOnClickListener {
            saveCurrentArticle()
        }
    }

    private fun saveCurrentArticle() {
        val article = currentArticle ?: return
        btnSave.isEnabled = false

        // DEPRECATED AsyncTask — replace with lifecycleScope.launch
        @Suppress("DEPRECATION")
        SaveArticleTask { success ->
            btnSave.isEnabled = true
            val message = if (success) "Saved to reading list" else "Already in reading list"
            Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
        }.execute(article)
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        return when (item.itemId) {
            android.R.id.home -> {
                onBackPressedDispatcher.onBackPressed()
                true
            }
            else -> super.onOptionsItemSelected(item)
        }
    }
}
