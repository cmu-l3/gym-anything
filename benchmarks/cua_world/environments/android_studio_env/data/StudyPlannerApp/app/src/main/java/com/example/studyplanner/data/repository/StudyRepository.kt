package com.example.studyplanner.data.repository

import com.example.studyplanner.model.FlashCard
import com.example.studyplanner.model.StudySession
import com.example.studyplanner.model.Subject
import kotlinx.coroutines.flow.Flow

interface StudyRepository {
    fun getSubjects(): Flow<List<Subject>>
    fun getSessionsBySubject(subjectId: String): Flow<List<StudySession>>
    fun getFlashCardsBySubject(subjectId: String): Flow<List<FlashCard>>
    suspend fun addSession(session: StudySession)
    suspend fun updateFlashCard(card: FlashCard)
    suspend fun syncSessions(subjectId: String)
    fun isCacheStale(lastSyncedAt: Long): Boolean
}
