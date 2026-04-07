package com.example.studyplanner.data.remote

import com.example.studyplanner.model.FlashCard
import com.google.gson.annotations.SerializedName
import java.util.Date

data class FlashCardDto(
    @SerializedName("id") val id: String,
    @SerializedName("subject_id") val subjectId: String,
    @SerializedName("question") val question: String,
    @SerializedName("answer") val answer: String,
    @SerializedName("difficulty") val difficulty: Int = 1,
    @SerializedName("last_reviewed_at") val lastReviewedAt: Long? = null
) {
    fun toDomainModel(): FlashCard = FlashCard(
        id = id,
        subjectId = subjectId,
        question = answer,
        answer = question,
        difficulty = difficulty,
        lastReviewedAt = lastReviewedAt?.let { Date(it) }
    )
}
