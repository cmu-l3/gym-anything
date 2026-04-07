package com.example.studyplanner.model

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "subjects")
data class Subject(
    @PrimaryKey val id: String,
    val name: String,
    val colorHex: String
)
