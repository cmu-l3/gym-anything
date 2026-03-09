#!/usr/bin/env python3
"""
Verifier for Add Waiting List task in OSCAR EMR.
"""

import json
import os
import tempfile
import logging
import time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_waiting_list(traj, env_info, task_info):
    """
    Verify the agent created the waiting list and added the patient.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result Data
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    max_score = 100
    feedback_parts = []
    
    metadata = task_info.get('metadata', {})
    expected_keywords = metadata.get('note_keywords', ["hip replacement", "left side", "osteoarthritis", "2025"])

    # --- Criterion 1: Waiting List Created (25 pts) ---
    if result.get('wl_name_exists', False):
        score += 25
        feedback_parts.append("Waiting list 'Orthopedic Surgery' created.")
    else:
        feedback_parts.append("Failed to create 'Orthopedic Surgery' waiting list.")

    # --- Criterion 2: Patient Added to A List (30 pts) ---
    if result.get('patient_on_list', False):
        score += 30
        feedback_parts.append("Patient Margaret Wilson added to a waiting list.")
    else:
        feedback_parts.append("Patient Margaret Wilson NOT found on any waiting list.")

    # --- Criterion 3: Patient on CORRECT List (15 pts) ---
    if result.get('on_correct_list', False):
        score += 15
        feedback_parts.append("Patient is on the correct 'Orthopedic Surgery' list.")
    elif result.get('patient_on_list', False):
        feedback_parts.append("Patient is on WRONG waiting list (not Orthopedic Surgery).")

    # --- Criterion 4: Note Content (20 pts) ---
    note_content = result.get('note_content', "").lower()
    keywords_found = 0
    if note_content:
        for keyword in expected_keywords:
            if keyword.lower() in note_content:
                keywords_found += 1
        
        # Scale score based on keywords found (5 pts per keyword, max 20)
        note_score = min(20, keywords_found * 5)
        score += note_score
        
        if note_score == 20:
            feedback_parts.append("Note content correct.")
        elif note_score > 0:
            feedback_parts.append(f"Note partially correct ({keywords_found}/{len(expected_keywords)} keywords).")
        else:
            feedback_parts.append("Note found but missing key clinical details.")
    else:
        if result.get('patient_on_list', False):
            feedback_parts.append("No note content found.")

    # --- Criterion 5: Anti-Gaming (10 pts) ---
    # Ensure new rows were actually added to tables during the task
    wl_diff = result.get('current_wl_count', 0) - result.get('initial_wl_count', 0)
    wln_diff = result.get('current_wln_count', 0) - result.get('initial_wln_count', 0)
    
    if wl_diff > 0 and wln_diff > 0:
        score += 10
        feedback_parts.append("Database changes verified.")
    elif wl_diff > 0 or wln_diff > 0:
        score += 5
        feedback_parts.append("Partial database changes verified.")
    else:
        feedback_parts.append("No new database records detected (suspicious).")

    # --- Success Determination ---
    # Must have created list AND added patient to pass
    passed = result.get('wl_name_exists', False) and result.get('patient_on_list', False) and score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }