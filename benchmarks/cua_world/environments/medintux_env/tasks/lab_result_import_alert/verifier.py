#!/usr/bin/env python3
"""
Verifier for lab_result_import_alert task.

Scoring Criteria:
1. DUBOIS (High Potassium): Note exists with correct value AND title starts with "ALERT"
2. LEROY (Normal Ferritin): Note exists with correct value AND title starts with "Lab"
3. MOREAU (Normal Glucose): Note exists with correct value AND title starts with "Lab"
4. PETIT (Low Hemoglobin): Note exists with correct value AND title starts with "ALERT"

Points: 25 per patient (10 for existence/value, 15 for correct triage title)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_lab_result_import_alert(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env missing"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_entries = metadata.get('expected_entries', [])

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Parse DB results
    notes = result_data.get("db_data", {}).get("notes", [])
    
    score = 0
    max_score = 100
    feedback_lines = []
    
    # Process each expected patient
    for expected in expected_entries:
        last_name = expected['name']
        test_val = expected['value']
        expected_prefix = expected['expected_title_prefix'] # ALERT or Lab
        
        # Find matching note
        # Allow case-insensitive name match
        matches = [
            n for n in notes 
            if n['last_name'].upper() == last_name.upper()
        ]
        
        if not matches:
            feedback_lines.append(f"MISSING: No note found for patient {last_name}")
            continue
            
        # Check content and title for the *best* match (in case of multiple notes)
        # We look for ANY note that satisfies the criteria
        best_match_score = 0
        match_feedback = ""
        
        patient_passed = False
        
        for note in matches:
            current_note_score = 0
            note_content = note.get('content', '')
            note_title = note.get('title', '')
            
            # Check 1: Value presence (10 pts)
            if test_val in note_content:
                current_note_score += 10
            
            # Check 2: Title Logic (15 pts)
            # Case insensitive check for "ALERT" or "Lab" at start
            clean_title = note_title.strip().upper()
            if clean_title.startswith(expected_prefix.upper()):
                current_note_score += 15
            
            if current_note_score > best_match_score:
                best_match_score = current_note_score
                # Generate specific feedback for the best attempt
                status_fb = "Found" if test_val in note_content else f"Value {test_val} missing"
                title_fb = "Title OK" if clean_title.startswith(expected_prefix.upper()) else f"Title '{note_title}' incorrect (expected {expected_prefix}...)"
                match_feedback = f"{last_name}: {status_fb}, {title_fb}"

        score += best_match_score
        feedback_lines.append(match_feedback)

    # Final check
    passed = score >= 75  # Allow one minor title error or partial misses
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_lines)
    }