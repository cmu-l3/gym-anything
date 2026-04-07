package com.example.studyplanner.ui.flashcards

import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.ViewModel
import androidx.lifecycle.asLiveData
import androidx.lifecycle.viewModelScope
import com.example.studyplanner.data.repository.OfflineCacheRepository
import com.example.studyplanner.model.FlashCard
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

class FlashCardViewModel : ViewModel() {
    private lateinit var repository: OfflineCacheRepository
    private var subjectId: String = ""

    private val _currentCard = MutableLiveData<FlashCard?>()
    val currentCard: LiveData<FlashCard?> = _currentCard

    private var cardIndex = 0

    fun init(repo: OfflineCacheRepository, subjectId: String) {
        this.repository = repo
        this.subjectId = subjectId
    }

    val cards: LiveData<List<FlashCard>> =
        MutableLiveData(emptyList())

    fun loadCards() {
        viewModelScope.launch {
            repository.getFlashCardsBySubject(subjectId).collect { cardList ->
                (cards as MutableLiveData).value = cardList
                if (cardList.isNotEmpty()) {
                    _currentCard.value = cardList[0]
                }
            }
        }
    }

    fun nextCard() {
        val cardList = cards.value ?: return
        if (cardList.isNotEmpty()) {
            cardIndex = (cardIndex + 1) % cardList.size
            _currentCard.value = cardList[cardIndex]
        }
    }
}
