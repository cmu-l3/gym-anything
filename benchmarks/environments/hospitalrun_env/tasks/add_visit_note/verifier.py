#!/usr/bin/env python3
"""
Verifier for add_visit_note task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_visit_note(traj, env_info, task_info):
    """
    Verify that a clinical note was added to Elena Vasquez's visit.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    analysis = result.get('analysis', {})
    count_increased = result.get('count_increased', False)
    
    note_found = analysis.get('note_found', False)
    phrases_count = analysis.get('phrases_found_count', 0)
    linked_correctly = analysis.get('linked_correctly', False)
    
    score = 0
    feedback_parts = []
    
    # Criterion 1: Note content found in database (30 pts)
    if note_found:
        score += 30
        feedback_parts.append("Note document found in database.")
    else:
        feedback_parts.append("No note document with expected content found.")
        return {"passed": False, "score": 0, "feedback": "Failed: Note not saved."}

    # Criterion 2: Content Completeness (40 pts)
    # 9 phrases total. 5 required for passing score on this section.
    # Score = (phrases / 9) * 40
    completeness_score = min(40, int((phrases_count / 9.0) * 40))
    score += completeness_score
    feedback_parts.append(f"Content completeness: {phrases_count}/9 key phrases found ({completeness_score} pts).")

    # Criterion 3: Linked to correct patient (30 pts)
    if linked_correctly:
        score += 30
        feedback_parts.append("Note correctly linked to Elena Vasquez.")
    else:
        feedback_parts.append("Note found but NOT linked to correct patient ID (patient_p1_ev001).")

    # Anti-gaming: Count check
    if not count_increased:
        feedback_parts.append("WARNING: Note count did not increase (possibly pre-existing).")
        # We might penalize or fail here, but if the content is exact, it's likely fine 
        # unless it's a replay. The setup script cleans/counts, so this is a valid check.
        if score > 0:
            score = max(0, score - 50) # Heavy penalty for not creating NEW data

    passed = score >= 60 and note_found and linked_correctly

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }