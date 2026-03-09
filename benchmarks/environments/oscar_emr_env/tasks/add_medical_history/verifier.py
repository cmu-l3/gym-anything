#!/usr/bin/env python3
"""
Verifier for add_medical_history task (Oscar EMR).
Verifies that specific medical history entries were added to the patient's CPP.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_medical_history(traj, env_info, task_info):
    """
    Verify Maria Santos has new Medical History entries:
    1. Cholecystectomy 2018
    2. Pneumonia hospitalization 2020
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Required keywords
    REQ_1 = "cholecystectomy"
    REQ_2 = "pneumonia"
    
    score = 0
    feedback = []
    
    # Data from container
    new_pmh_entries = result.get('new_pmh_entries', [])
    new_keyword_notes = result.get('new_keyword_notes', [])
    cpp_notes = result.get('cpp_notes', [])
    patient_id = result.get('patient_id')
    
    # Helper to check lists
    def check_list_for_keyword(str_list, keyword):
        for s in str_list:
            if keyword.lower() in s.lower():
                return True
        return False

    # Helper to check if string contains keyword
    def check_str_for_keyword(s, keyword):
        return keyword.lower() in s.lower()

    # CRITERION 1: Patient ID Validity (10 pts)
    if patient_id and patient_id != "0" and patient_id != "":
        score += 10
        feedback.append(f"Patient Maria Santos identified (ID: {patient_id}).")
    else:
        feedback.append("Could not identify patient Maria Santos.")
        return {"passed": False, "score": 0, "feedback": "Patient not found in database."}

    # CRITERION 2: Cholecystectomy Entry (40 pts)
    # Check proper PMH entries first (High confidence)
    found_c_pmh = check_list_for_keyword(new_pmh_entries, REQ_1)
    
    # Check raw notes (Medium confidence - maybe wrong section)
    found_c_note = check_list_for_keyword(new_keyword_notes, REQ_1)
    
    # Check CPP table (Alternative storage)
    found_c_cpp = check_list_for_keyword(cpp_notes, REQ_1)

    if found_c_pmh:
        score += 40
        feedback.append(f"'{REQ_1}' found in Medical History section.")
    elif found_c_cpp:
        score += 40
        feedback.append(f"'{REQ_1}' found in CPP storage.")
    elif found_c_note:
        score += 20
        feedback.append(f"'{REQ_1}' found in notes, but possibly not in Medical History section (Partial credit).")
    else:
        feedback.append(f"MISSING: '{REQ_1}' entry not found.")

    # CRITERION 3: Pneumonia Entry (40 pts)
    found_p_pmh = check_list_for_keyword(new_pmh_entries, REQ_2)
    found_p_note = check_list_for_keyword(new_keyword_notes, REQ_2)
    found_p_cpp = check_list_for_keyword(cpp_notes, REQ_2)

    if found_p_pmh:
        score += 40
        feedback.append(f"'{REQ_2}' found in Medical History section.")
    elif found_p_cpp:
        score += 40
        feedback.append(f"'{REQ_2}' found in CPP storage.")
    elif found_p_note:
        score += 20
        feedback.append(f"'{REQ_2}' found in notes, but possibly not in Medical History section (Partial credit).")
    else:
        feedback.append(f"MISSING: '{REQ_2}' entry not found.")

    # CRITERION 4: Anti-Gaming / Timestamp (10 pts)
    # The SQL queries already filtered by timestamp. If we found entries in pmh/note lists, they are valid.
    # We double check if ANY entry was added.
    if len(new_pmh_entries) > 0 or len(new_keyword_notes) > 0:
        score += 10
        feedback.append("New entries were created during the task session.")
    else:
        feedback.append("No new entries detected during task session.")

    # Determine Pass/Fail
    # Need at least one correct entry in the correct section (or both in general notes) to pass (>50)
    passed = score >= 55

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }