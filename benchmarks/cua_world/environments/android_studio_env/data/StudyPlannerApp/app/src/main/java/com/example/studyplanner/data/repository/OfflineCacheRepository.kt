package com.example.studyplanner.data.repository

import com.example.studyplanner.data.local.AppDatabase
import com.example.studyplanner.data.remote.ApiClient
import com.example.studyplanner.data.remote.StudyApiService
import com.example.studyplanner.model.FlashCard
import com.example.studyplanner.model.StudySession
import com.example.studyplanner.model.Subject
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.withContext

class OfflineCacheRepository(
    private val database: AppDatabase,
    private val apiService: StudyApiService = ApiClient.apiService
) : StudyRepository {

    private val subjectDao = database.subjectDao()
    private val sessionDao = database.studySessionDao()
    private val flashCardDao = database.flashCardDao()

    override fun getSubjects(): Flow<List<Subject>> {
        return subjectDao.getAll()
    }

    override fun getSessionsBySubject(subjectId: String): Flow<List<StudySession>> {
        return sessionDao.getBySubject(subjectId)
    }

    override fun getFlashCardsBySubject(subjectId: String): Flow<List<FlashCard>> {
        return flashCardDao.getBySubject(subjectId)
    }

    override suspend fun addSession(session: StudySession) {
        withContext(Dispatchers.IO) {
            sessionDao.insert(session)
        }
    }

    override suspend fun updateFlashCard(card: FlashCard) {
        withContext(Dispatchers.IO) {
            flashCardDao.update(card)
        }
    }

    override suspend fun syncSessions(subjectId: String) {
        withContext(Dispatchers.IO) {
            // Upload unsynced local sessions
            val unsynced = sessionDao.getUnsynced()
            for (session in unsynced) {
                val dto = com.example.studyplanner.data.remote.StudySessionDto(
                    id = session.id,
                    subjectId = session.subjectId,
                    durationMinutes = session.durationMinutes,
                    date = session.date.time,
                    notes = session.notes,
                    lastSyncedAt = session.lastSyncedAt,
                    syncStatus = session.syncStatus
                )
                apiService.postSession(dto)
            }

            // Fetch latest sessions from API
            // BUG: Wrong method name — should be getSessionsBySubject
            val remoteSessions = apiService.getStudySessions(subjectId)
            val domainSessions = remoteSessions.map { it.toDomainModel() }
            sessionDao.insertAll(domainSessions)
        }
    }

    override fun isCacheStale(lastSyncedAt: Long): Boolean {
        val maxAge = 3600 // 1 hour in seconds
        // BUG: System.currentTimeMillis() returns milliseconds,
        // but lastSyncedAt is stored as Unix timestamp in seconds
        // and maxAge is also in seconds. This comparison mixes units.
        return System.currentTimeMillis() - lastSyncedAt > maxAge
    }
}
