package com.example.studyplanner.model

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.PrimaryKey
import java.util.Date

@Entity(
    tableName = "study_sessions",
    foreignKeys = [ForeignKey(
        entity = Subject::class,
        parentColumns = ["id"],
        childColumns = ["subjectId"],
        onDelete = ForeignKey.CASCADE
    )]
)
data class StudySession(
    @PrimaryKey val id: String,
    val subjectId: String,
    val durationMinutes: Int,
    val date: Date,
    val notes: String,
    val lastSyncedAt: Long = 0L,
    val syncStatus: Int = 0
)
