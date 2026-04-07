package com.example.studyplanner.data.repository

import com.example.studyplanner.model.FlashCard
import com.example.studyplanner.model.StudySession
import com.example.studyplanner.model.Subject
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.Date
import java.util.UUID

class InMemoryStudyRepository : StudyRepository {

    private val _subjects = MutableStateFlow(
        listOf(
            Subject("math-101", "Mathematics", "#FF5722"),
            Subject("phys-201", "Physics", "#2196F3"),
            Subject("chem-301", "Chemistry", "#4CAF50")
        )
    )

    private val _sessions = MutableStateFlow<List<StudySession>>(
        listOf(
            StudySession(
                id = UUID.randomUUID().toString(),
                subjectId = "math-101",
                durationMinutes = 45,
                date = Date(),
                notes = "Reviewed calculus fundamentals"
            )
        )
    )

    private val _flashCards = MutableStateFlow<List<FlashCard>>(
        listOf(
            FlashCard(
                id = UUID.randomUUID().toString(),
                subjectId = "math-101",
                question = "What is the derivative of x^2?",
                answer = "2x",
                difficulty = 1
            )
        )
    )

    override fun getSubjects(): Flow<List<Subject>> = _subjects.asStateFlow()

    override fun getSessionsBySubject(subjectId: String): Flow<List<StudySession>> =
        MutableStateFlow(_sessions.value.filter { it.subjectId == subjectId }).asStateFlow()

    override fun getFlashCardsBySubject(subjectId: String): Flow<List<FlashCard>> =
        MutableStateFlow(_flashCards.value.filter { it.subjectId == subjectId }).asStateFlow()

    override suspend fun addSession(session: StudySession) {
        _sessions.value = _sessions.value + session
    }

    override suspend fun updateFlashCard(card: FlashCard) {
        _flashCards.value = _flashCards.value.map { if (it.id == card.id) card else it }
    }

    override suspend fun syncSessions(subjectId: String) {
    }

    override fun isCacheStale(lastSyncedAt: Long): Boolean = false
}
