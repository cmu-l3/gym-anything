package com.example.notepad

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

/**
 * Represents a note in the notepad application.
 *
 * @property id Unique identifier for the note
 * @property title Title of the note
 * @property content Body text of the note
 * @property createdAt Timestamp when the note was created
 * @property updatedAt Timestamp when the note was last updated
 * @property isPinned Whether the note is pinned to the top
 * @property color Background color resource for the note
 */
data class Note(
    val id: String = UUID.randomUUID().toString(),
    val title: String,
    val content: String,
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis(),
    val isPinned: Boolean = false,
    val color: Int = COLOR_DEFAULT
) {
    /**
     * Returns the word count of the note's content.
     */
    fun wordCount(): Int {
        if (content.isBlank()) return 0
        return content.trim().split("\\s+".toRegex()).size
    }

    /**
     * Returns the character count of the note's content (excluding whitespace).
     */
    fun charCount(): Int {
        return content.replace("\\s".toRegex(), "").length
    }

    /**
     * Returns a formatted creation date string.
     */
    fun formattedCreatedDate(): String {
        val sdf = SimpleDateFormat("MMM dd, yyyy HH:mm", Locale.getDefault())
        return sdf.format(Date(createdAt))
    }

    /**
     * Returns a formatted last-updated date string.
     */
    fun formattedUpdatedDate(): String {
        val sdf = SimpleDateFormat("MMM dd, yyyy HH:mm", Locale.getDefault())
        return sdf.format(Date(updatedAt))
    }

    /**
     * Returns true if the note has been modified since creation.
     */
    fun isModified(): Boolean {
        return updatedAt > createdAt
    }

    /**
     * Returns a copy of this note with an updated timestamp.
     */
    fun touch(): Note {
        return copy(updatedAt = System.currentTimeMillis())
    }

    companion object {
        const val COLOR_DEFAULT = 0xFFFFFFFF.toInt()
        const val COLOR_RED = 0xFFFFCDD2.toInt()
        const val COLOR_BLUE = 0xFFBBDEFB.toInt()
        const val COLOR_GREEN = 0xFFC8E6C9.toInt()
        const val COLOR_YELLOW = 0xFFFFF9C4.toInt()

        const val MAX_TITLE_LENGTH = 100
        const val MAX_CONTENT_LENGTH = 10000
    }
}
