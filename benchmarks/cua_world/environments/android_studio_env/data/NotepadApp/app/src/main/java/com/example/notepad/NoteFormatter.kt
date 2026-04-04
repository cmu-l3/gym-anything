package com.example.notepad

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.TimeUnit

/**
 * Formats note data for display in the UI.
 *
 * Provides methods to format note titles, content previews, and dates
 * for consistent display across the application.
 */
class NoteFormatter {

    /**
     * Formats a note title for display.
     *
     * If the title exceeds [maxLength], it is truncated and suffixed with an ellipsis.
     * Leading and trailing whitespace is trimmed.
     * If the title is null or blank, returns a default placeholder.
     *
     * @param title The title to format
     * @param maxLength Maximum display length (default 50)
     * @return The formatted title string
     */
    fun formatTitle(title: String?, maxLength: Int = 50): String {
        if (title.isNullOrBlank()) return "Untitled Note"
        val trimmed = title.trim()
        return if (trimmed.length > maxLength) {
            "${trimmed.take(maxLength)}..."
        } else {
            trimmed
        }
    }

    /**
     * Formats note content as a preview snippet.
     *
     * Creates a single-line preview from the content by:
     * - Replacing newlines with spaces
     * - Collapsing multiple spaces into one
     * - Truncating to [maxLength] characters with ellipsis
     * - Returning a placeholder if content is empty
     *
     * @param content The content to create a preview from
     * @param maxLength Maximum preview length (default 100)
     * @return The formatted preview string
     */
    fun formatPreview(content: String?, maxLength: Int = 100): String {
        if (content.isNullOrBlank()) return "No content"
        val singleLine = content
            .replace("\n", " ")
            .replace("\\s+".toRegex(), " ")
            .trim()
        return if (singleLine.length > maxLength) {
            "${singleLine.take(maxLength)}..."
        } else {
            singleLine
        }
    }

    /**
     * Formats a timestamp into a human-readable date string.
     *
     * Uses relative formatting for recent dates:
     * - "Just now" for timestamps less than 1 minute ago
     * - "X minutes ago" for timestamps less than 1 hour ago
     * - "X hours ago" for timestamps less than 24 hours ago
     * - "Yesterday" for timestamps from the previous day
     * - Full date format (e.g., "Jan 15, 2024") for older timestamps
     *
     * @param timestamp The timestamp in milliseconds
     * @return The formatted date string
     */
    fun formatDate(timestamp: Long): String {
        val now = System.currentTimeMillis()
        val diff = now - timestamp

        return when {
            diff < TimeUnit.MINUTES.toMillis(1) -> "Just now"
            diff < TimeUnit.HOURS.toMillis(1) -> {
                val minutes = TimeUnit.MILLISECONDS.toMinutes(diff)
                if (minutes == 1L) "1 minute ago" else "$minutes minutes ago"
            }
            diff < TimeUnit.DAYS.toMillis(1) -> {
                val hours = TimeUnit.MILLISECONDS.toHours(diff)
                if (hours == 1L) "1 hour ago" else "$hours hours ago"
            }
            diff < TimeUnit.DAYS.toMillis(2) -> "Yesterday"
            else -> {
                val sdf = SimpleDateFormat("MMM dd, yyyy", Locale.getDefault())
                sdf.format(Date(timestamp))
            }
        }
    }

    /**
     * Formats a word count into a display string.
     *
     * @param wordCount The number of words
     * @return Formatted string like "42 words" or "1 word"
     */
    fun formatWordCount(wordCount: Int): String {
        return when (wordCount) {
            0 -> "Empty"
            1 -> "1 word"
            else -> "$wordCount words"
        }
    }

    /**
     * Formats a note's metadata line for list display.
     *
     * Combines the date and word count into a single metadata string.
     *
     * @param note The note to format metadata for
     * @return Formatted metadata string
     */
    fun formatMetadata(note: Note): String {
        val date = formatDate(note.updatedAt)
        val words = formatWordCount(note.wordCount())
        return "$date  |  $words"
    }
}
