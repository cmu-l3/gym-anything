package com.example.notepad

/**
 * Validates note data before saving or displaying.
 *
 * This class provides validation methods for note fields to ensure data integrity.
 * All validation methods return true if the input is valid, false otherwise.
 */
class NoteValidator {

    /**
     * Validates a note title.
     *
     * A valid title must:
     * - Not be null or blank
     * - Not exceed [Note.MAX_TITLE_LENGTH] characters
     * - Not contain only whitespace
     * - Not start or end with whitespace (after trimming, must match original)
     *
     * @param title The title to validate
     * @return true if the title is valid
     */
    fun isValidTitle(title: String?): Boolean {
        if (title.isNullOrBlank()) return false
        if (title.length > Note.MAX_TITLE_LENGTH) return false
        if (title.trim() != title) return false
        return true
    }

    /**
     * Validates note content.
     *
     * Valid content must:
     * - Not be null
     * - Not exceed [Note.MAX_CONTENT_LENGTH] characters
     * - Note: empty content IS allowed (a note can have just a title)
     *
     * @param content The content to validate
     * @return true if the content is valid
     */
    fun isValidContent(content: String?): Boolean {
        if (content == null) return false
        if (content.length > Note.MAX_CONTENT_LENGTH) return false
        return true
    }

    /**
     * Checks if a note is complete and ready to save.
     *
     * A note is complete if:
     * - It has a valid title
     * - It has valid content
     * - The content is not empty (must have at least some text)
     *
     * @param note The note to validate
     * @return true if the note is complete and valid
     */
    fun isNoteComplete(note: Note): Boolean {
        if (!isValidTitle(note.title)) return false
        if (!isValidContent(note.content)) return false
        if (note.content.isBlank()) return false
        return true
    }

    /**
     * Validates a note ID format.
     *
     * A valid ID must be a non-empty string matching UUID format.
     *
     * @param id The ID to validate
     * @return true if the ID is valid
     */
    fun isValidId(id: String?): Boolean {
        if (id.isNullOrBlank()) return false
        val uuidRegex = "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$".toRegex()
        return uuidRegex.matches(id)
    }

    /**
     * Validates a note color value.
     *
     * @param color The color to validate
     * @return true if the color is one of the predefined note colors
     */
    fun isValidColor(color: Int): Boolean {
        return color in listOf(
            Note.COLOR_DEFAULT,
            Note.COLOR_RED,
            Note.COLOR_BLUE,
            Note.COLOR_GREEN,
            Note.COLOR_YELLOW
        )
    }
}
