package com.example.studyplanner.data.remote

import com.example.studyplanner.model.StudySession
import com.google.gson.annotations.SerializedName
import java.util.Date

data class StudySessionDto(
    @SerializedName("id") val id: String,
    @SerializedName("subject_id") val subjectId: String,
    @SerializedName("duration_minutes") val durationMinutes: Int,
    @SerializedName("date") val date: Long,
    @SerializedName("notes") val notes: String,
    @SerializedName("last_synced_at") val lastSyncedAt: Long = 0L,
    @SerializedName("sync_status") val syncStatus: Int = 0
) {
    fun toDomainModel(): StudySession = StudySession(
        id = id,
        subjectId = subjectId,
        durationMinutes = durationMinutes,
        date = Date(date),
        notes = notes,
        lastSyncedAt = lastSyncedAt,
        syncStatus = syncStatus
    )
}
