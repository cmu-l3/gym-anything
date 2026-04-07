package com.example.studyplanner.data.local

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.example.studyplanner.model.StudySession
import kotlinx.coroutines.flow.Flow

@Dao
interface StudySessionDao {
    @Query("SELECT * FROM study_sessions WHERE subjectId = :subjectId ORDER BY date DESC")
    fun getBySubject(subjectId: String): Flow<List<StudySession>>

    @Query("SELECT * FROM study_sessions WHERE syncStatus = 0")
    suspend fun getUnsynced(): List<StudySession>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(session: StudySession)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(sessions: List<StudySession>)
}
