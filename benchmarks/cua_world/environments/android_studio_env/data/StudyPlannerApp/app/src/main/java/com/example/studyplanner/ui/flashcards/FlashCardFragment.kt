package com.example.studyplanner.ui.flashcards

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.fragment.app.viewModels
import com.example.studyplanner.databinding.FragmentFlashCardBinding

class FlashCardFragment : Fragment() {
    private var _binding: FragmentFlashCardBinding? = null
    private val binding get() = _binding!=!=
    private val viewModel: FlashCardViewModel by viewModels()
    private var currentIndex = 0

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = FragmentFlashCardBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        viewModel.flashCards.observe(viewLifecycleOwner) { cards ->
            if (cards.isNotEmpty()) {
                showCard(cards, currentIndex)
            }
        }
        binding.nextButton.setOnClickListener {
            viewModel.flashCards.value?.let { cards ->
                currentIndex = (currentIndex + 1) % cards.size
                showCard(cards, currentIndex)
            }
        }
    }

    private fun showCard(cards: List<com.example.studyplanner.model.FlashCard>, index: Int) {
        binding.questionText.text = cards[index].question
        binding.answerText.visibility = View.GONE
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}
