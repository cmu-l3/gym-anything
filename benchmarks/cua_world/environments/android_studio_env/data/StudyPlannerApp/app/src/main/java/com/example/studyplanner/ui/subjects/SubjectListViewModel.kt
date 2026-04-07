package com.example.studyplanner.ui.subjects

import androidx.lifecycle.LiveData
import androidx.lifecycle.ViewModel
import androidx.lifecycle.asLiveData
import com.example.studyplanner.data.repository.InMemoryStudyRepository
import com.example.studyplanner.model.Subject

class SubjectListViewModel : ViewModel() {
    // BUG: Should use OfflineCacheRepository instead of InMemoryStudyRepository
    private val repository = InMemoryStudyRepository()

    val subjects: LiveData<List<Subject>> = repository.getSubjects().asLiveData()
}
