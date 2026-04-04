package com.example.feedreader.ui

import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.view.MenuItem
import android.view.View
import android.widget.EditText
import android.widget.ProgressBar
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.example.feedreader.R
import com.example.feedreader.task.SearchArticlesTask

/**
 * Search screen — searches articles as user types.
 *
 * PROBLEM: Uses AsyncTask which cannot be cancelled when the user
 * types a new character. Results from stale searches may arrive
 * out of order, causing incorrect UI updates.
 *
 * Coroutine migration benefit: Job cancellation ensures only
 * the latest search results are displayed.
 */
class SearchActivity : AppCompatActivity() {

    private lateinit var etSearch: EditText
    private lateinit var recyclerView: RecyclerView
    private lateinit var progressBar: ProgressBar
    private lateinit var tvNoResults: TextView

    @Suppress("DEPRECATION")
    private var currentSearchTask: SearchArticlesTask? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_search)

        supportActionBar?.setDisplayHomeAsUpEnabled(true)
        supportActionBar?.title = "Search Articles"

        etSearch = findViewById(R.id.et_search)
        recyclerView = findViewById(R.id.rv_search_results)
        progressBar = findViewById(R.id.progress_bar)
        tvNoResults = findViewById(R.id.tv_no_results)

        recyclerView.layoutManager = LinearLayoutManager(this)

        etSearch.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
            override fun afterTextChanged(s: Editable?) {
                val query = s?.toString()?.trim() ?: ""
                if (query.length >= 2) {
                    performSearch(query)
                }
            }
        })
    }

    private fun performSearch(query: String) {
        // Cancel previous task — but this is unreliable with AsyncTask
        @Suppress("DEPRECATION")
        currentSearchTask?.cancel(true)

        progressBar.visibility = View.VISIBLE
        tvNoResults.visibility = View.GONE

        // DEPRECATED AsyncTask — replace with coroutine scope + Job cancellation
        @Suppress("DEPRECATION")
        currentSearchTask = SearchArticlesTask(
            onResults = { articles ->
                progressBar.visibility = View.GONE
                if (articles.isEmpty()) {
                    tvNoResults.visibility = View.VISIBLE
                    recyclerView.adapter = null
                } else {
                    recyclerView.adapter = ArticleAdapter(articles) {}
                }
            },
            onError = {
                progressBar.visibility = View.GONE
            }
        )
        @Suppress("DEPRECATION")
        currentSearchTask!!.execute(query)
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
