package com.example.feedreader.model

import java.util.Date

/**
 * Represents a news article from the feed.
 */
data class Article(
    val id: String,
    val title: String,
    val summary: String,
    val content: String,
    val author: String,
    val category: String,
    val publishedAt: Date = Date(),
    val imageUrl: String = "",
    val sourceUrl: String = "",
    var isSaved: Boolean = false
)
