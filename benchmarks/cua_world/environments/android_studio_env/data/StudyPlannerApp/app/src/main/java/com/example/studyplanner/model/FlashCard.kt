package com.example.studyplanner.model

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.PrimaryKey
import java.util.Date

@Entity(
    tableName = "flash_cards",
    foreignKeys = [ForeignKey(
        entity = Subject::class,
        parentColumns = ["id"],
        childColumns = ["subjectId"],
        onDelete = ForeignKey.CASCADE
    )]
)
data class FlashCard(
    @PrimaryKey val id: String,
    val subjectId: String,
    val question: String,
    val answer: String,
    val difficulty: Int = 1,
    val lastReviewedAt: Date? = null
)
