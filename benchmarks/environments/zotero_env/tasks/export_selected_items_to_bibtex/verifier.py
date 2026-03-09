#!/usr/bin/env python3
"""
Verifier for export_selected_items_to_bibtex@1 task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_selected_items_to_bibtex(traj, env_info, task_info):
    """
    Verify that the agent exported the 3 specific papers to a BibTeX file.
    """
    # 1. Boilerplate: Copy result JSON from environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    file_exists = result.get("file_exists", False)
    created_during_task = result.get("file_created_during_task", False)
    is_bibtex = result.get("is_bibtex", False)
    entry_count = result.get("entry_count", 0)
    contains_shannon = result.get("contains_shannon", False)
    contains_huffman = result.get("contains_huffman", False)
    contains_turing = result.get("contains_turing", False)

    # 3. Scoring Logic
    score = 0
    feedback = []

    # Criterion 1: File Existence (20 pts)
    if file_exists:
        score += 20
        feedback.append("File 'info_theory_foundations.bib' exists.")
    else:
        feedback.append("Output file NOT found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Criterion 2: Anti-Gaming / Freshness (10 pts)
    if created_during_task:
        score += 10
        feedback.append("File created during task.")
    else:
        feedback.append("File timestamp indicates it was pre-existing or old.")

    # Criterion 3: Valid Format (10 pts)
    if is_bibtex:
        score += 10
        feedback.append("File appears to be valid BibTeX.")
    else:
        feedback.append("File does not start with standard BibTeX entries (@).")

    # Criterion 4: Entry Count (30 pts)
    # Exact match = 30, Partial (>=1) = 10
    if entry_count == 3:
        score += 30
        feedback.append("File contains exactly 3 entries.")
    elif entry_count > 0:
        score += 10
        feedback.append(f"File contains {entry_count} entries (expected 3).")
    else:
        feedback.append("File contains 0 entries.")

    # Criterion 5: Specific Content (10 pts each)
    if contains_shannon:
        score += 10
        feedback.append("Shannon paper found.")
    else:
        feedback.append("Shannon paper missing.")

    if contains_huffman:
        score += 10
        feedback.append("Huffman paper found.")
    else:
        feedback.append("Huffman paper missing.")

    if contains_turing:
        score += 10
        feedback.append("Turing paper found.")
    else:
        feedback.append("Turing paper missing.")

    # 4. Final Determination
    # Pass threshold: 70 points
    # Must have the file and at least 2/3 correct papers
    passed = (score >= 70) and file_exists

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }