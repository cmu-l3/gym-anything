package com.example.studyplanner.data.remote

import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Query

interface StudyApiService {
    @GET("subjects")
    suspend fun getSubjects(): List<SubjectDto>

    @GET("sessions")
    suspend fun getSessionsBySubject(@Query("subjectId") subjectId: String): List<StudySessionDto>

    @GET("flashcards")
    suspend fun getFlashCardsBySubject(@Query("subjectId") subjectId: String): List<FlashCardDto>

    @POST("sessions")
    suspend fun postSession(@Body session: StudySessionDto): StudySessionDto
}
