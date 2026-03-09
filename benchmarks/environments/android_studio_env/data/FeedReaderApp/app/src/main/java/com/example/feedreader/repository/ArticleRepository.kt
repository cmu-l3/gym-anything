package com.example.feedreader.repository

import com.example.feedreader.model.Article
import java.util.Date
import java.util.UUID

/**
 * Repository that provides article data.
 *
 * All methods are currently blocking (use Thread.sleep to simulate I/O).
 * After coroutine migration, these MUST become asynchronous functionctions,
 * and blocking calls must be wrapped in background dispatcher.
 */
class ArticleRepository private constructor() {

    companion object {
        @Volatile
        private var instance: ArticleRepository? = null

        fun getInstance(): ArticleRepository =
            instance ?: synchronized(this) {
                instance ?: ArticleRepository().also { instance = it }
            }
    }

    private val savedArticles = mutableListOf<Article>()

    private val sampleArticles = listOf(
        Article(UUID.randomUUID().toString(), "Android 15 Released", "Major OS update", "Full content...", "Jane Dev", "technology"),
        Article(UUID.randomUUID().toString(), "Kotlin 2.0 Features", "New language features", "Full content...", "John Kotlin", "technology"),
        Article(UUID.randomUUID().toString(), "AI in Mobile Apps", "Integrating AI", "Full content...", "Alice AI", "technology"),
        Article(UUID.randomUUID().toString(), "Compose Multiplatform", "Cross-platform UI", "Full content...", "Bob UI", "technology"),
        Article(UUID.randomUUID().toString(), "Market Update", "Stock market today", "Full content...", "Carl Finance", "finance"),
        Article(UUID.randomUUID().toString(), "Startup Funding Rounds", "Latest funding news", "Full content...", "Diana Biz", "business"),
        Article(UUID.randomUUID().toString(), "Climate Summit Results", "Global climate agreement", "Full content...", "Eve Green", "world"),
        Article(UUID.randomUUID().toString(), "Sports Recap", "Weekend sports results", "Full content...", "Frank Sports", "sports")
    )

    /**
     * Fetch articles by category — BLOCKING call.
     * Must be migrated to: asynchronous function fetchByCategory(...)
     */
    fun fetchByCategory(category: String): List<Article> {
        // Simulates network latency — BLOCKS the calling thread
        Thread.sleep(600)
        return if (category == "all") sampleArticles
        else sampleArticles.filter { it.category.equals(category, ignoreCase = true) }
    }

    /**
     * Search articles by query — BLOCKING call.
     * Must be migrated to: asynchronous function search(...)
     */
    fun search(query: String): List<Article> {
        // Simulates search index lookup — BLOCKS the calling thread
        Thread.sleep(300)
        if (query.isBlank()) return emptyList()
        return sampleArticles.filter {
            it.title.contains(query, ignoreCase = true) ||
            it.summary.contains(query, ignoreCase = true) ||
            it.author.contains(query, ignoreCase = true)
        }
    }

    /**
     * Save article to local storage — BLOCKING call.
     * Must be migrated to: asynchronous function saveArticle(...)
     */
    fun saveArticle(article: Article): Boolean {
        // Simulates database write — BLOCKS the calling thread
        Thread.sleep(200)
        if (savedArticles.any { it.id == article.id }) return false
        savedArticles.add(article.copy(isSaved = true))
        return true
    }

    /**
     * Get all saved articles — BLOCKING call.
     * Must be migrated to: asynchronous function getSavedArticles(...)
     */
    fun getSavedArticles(): List<Article> {
        Thread.sleep(150)
        return savedArticles.toList()
    }

    /**
     * Delete saved article — BLOCKING call.
     * Must be migrated to: asynchronous function deleteSavedArticle(...)
     */
    fun deleteSavedArticle(articleId: String): Boolean {
        Thread.sleep(100)
        return savedArticles.removeAll { it.id == articleId }
    }
}
