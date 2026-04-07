package com.example.studyplanner.data.remote

import com.example.studyplanner.model.Subject
import com.google.gson.annotations.SerializedName

data class SubjectDto(
    @SerializedName("id") val id: String,
    @SerializedName("name") val name: String,
    @SerializedName("color_hex") val colorHex: String
) {
    fun toDomainModel(): Subject = Subject(
        id = id,
        name = name,
        colorHex = colorHex
    )
}
