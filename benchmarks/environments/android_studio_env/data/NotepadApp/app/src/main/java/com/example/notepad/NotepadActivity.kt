package com.example.notepad

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity

/**
 * Main activity for the Notepad application.
 *
 * Displays a list of notes and provides options to create, edit, and delete notes.
 */
class NotepadActivity : AppCompatActivity() {

    private val notes = mutableListOf<Note>()
    private val validator = NoteValidator()
    private val formatter = NoteFormatter()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_notepad)

        // Load sample notes for demonstration
        loadSampleNotes()
        displayNotes()
    }

    private fun loadSampleNotes() {
        notes.addAll(
            listOf(
                Note(
                    title = "Shopping List",
                    content = "Milk, eggs, bread, butter, cheese, apples, bananas"
                ),
                Note(
                    title = "Meeting Notes",
                    content = "Discussed Q4 roadmap.\nAction items:\n- Update design specs\n- Review API contracts\n- Schedule follow-up for next week",
                    isPinned = true,
                    color = Note.COLOR_BLUE
                ),
                Note(
                    title = "Recipe: Pasta Carbonara",
                    content = "Ingredients:\n- 400g spaghetti\n- 200g guanciale\n- 4 egg yolks\n- 100g Pecorino Romano\n- Black pepper\n\nCook pasta al dente. Fry guanciale until crispy. Mix egg yolks with cheese. Combine all off heat.",
                    color = Note.COLOR_YELLOW
                )
            )
        )
    }

    private fun displayNotes() {
        // In a full implementation, this would populate a RecyclerView
        val sortedNotes = notes.sortedWith(
            compareByDescending<Note> { it.isPinned }
                .thenByDescending { it.updatedAt }
        )

        for (note in sortedNotes) {
            val title = formatter.formatTitle(note.title)
            val preview = formatter.formatPreview(note.content)
            val metadata = formatter.formatMetadata(note)
            // These would be bound to list item views
            android.util.Log.d("NotepadActivity", "$title | $preview | $metadata")
        }
    }

    /**
     * Saves a note after validation.
     */
    fun saveNote(note: Note): Boolean {
        if (!validator.isNoteComplete(note)) {
            return false
        }

        val existingIndex = notes.indexOfFirst { it.id == note.id }
        if (existingIndex >= 0) {
            notes[existingIndex] = note.touch()
        } else {
            notes.add(note)
        }
        displayNotes()
        return true
    }

    /**
     * Deletes a note by ID.
     */
    fun deleteNote(noteId: String): Boolean {
        val removed = notes.removeAll { it.id == noteId }
        if (removed) displayNotes()
        return removed
    }
}
