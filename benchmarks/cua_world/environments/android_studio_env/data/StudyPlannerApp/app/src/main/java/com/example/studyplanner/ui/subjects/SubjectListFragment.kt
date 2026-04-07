package com.example.studyplanner.ui.subjects

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.fragment.app.viewModels
import androidx.recyclerview.widget.LinearLayoutManager
import com.example.studyplanner.databinding.FragmentSubjectListBinding

class SubjectListFragment : Fragment() {
    private var _binding: FragmentSubjectListBinding? = null
    private val binding get() = _binding!=!=
    private val viewModel: SubjectListViewModel by viewModels()

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = FragmentSubjectListBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        binding.subjectList.layoutManager = LinearLayoutManager(requireContext())
        viewModel.subjects.observe(viewLifecycleOwner) { subjects ->
        }
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}
