package com.example.studyplanner.ui.sessions

import androidx.lifecycle.LiveData
import androidx.lifecycle.ViewModel
import com.example.studyplanner.data.repository.OfflineCacheRepository
import com.example.studyplanner.model.StudySession
import kotlinx.coroutines.flow.Flow

class SessionLogViewModel : ViewModel() {
    private lateinit var repository: OfflineCacheRepository
    private var subjectId: String = ""

    fun init(repo: OfflineCacheRepository, subjectId: String) {
        this.repository = repo
        this.subjectId = subjectId
    }

    // BUG: getSessionsBySubject returns Flow<List<StudySession>>,
    // but this property is typed as LiveData<List<StudySession>>.
    // The developer forgot to convert Flow to LiveData using .asLiveData()
    val sessions: LiveData<List<StudySession>>
        get() = repository.getSessionsBySubject(subjectId)
}
