#!/usr/bin/env python3
"""
Verifier for correct_medication_dosage task.

Criteria:
1. Medication order for Amoxicillin exists for patient Arthur Dent.
2. Dosage is corrected to "500mg".
3. PREFERRED: The original document ID is preserved (indicating an edit, not delete+create).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_correct_medication_dosage(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result from container
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

    # Extract data
    target_id = result.get("target_doc_id", "")
    target_exists = result.get("target_doc_exists", False)
    target_dosage = result.get("target_doc_dosage", "").strip()
    all_matches = result.get("all_med_matches", [])

    feedback = []
    score = 0
    
    # Metadata expectations
    expected_dosage = "500mg"
    
    # logic
    final_dosage = None
    is_original_doc = False
    
    # Check if original doc still exists
    if target_exists:
        final_dosage = target_dosage
        is_original_doc = True
        feedback.append(f"Original document {target_id} found (Edit operation detected).")
    elif all_matches:
        # If original is gone, look at the first match (Delete+Recreate case)
        # We take the most likely candidate (e.g., last created) but here just the first
        match = all_matches[0]
        final_dosage = match.get("dosage", "").strip()
        is_original_doc = False
        feedback.append("Original document not found, but a new matching medication order exists.")
    else:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No Amoxicillin medication order found for patient Arthur Dent."
        }

    # Scoring
    # 1. Record Found (20 pts)
    score += 20
    
    # 2. Dosage Check (60 pts)
    # Normalize: remove spaces, lowercase
    norm_final = final_dosage.lower().replace(" ", "")
    norm_expected = expected_dosage.lower().replace(" ", "")
    
    if norm_final == norm_expected:
        score += 60
        feedback.append(f"Dosage correctly updated to '{final_dosage}'.")
    elif "500" in norm_final:
        # Partial credit if they got the number but messed up the unit format slightly differently than expected
        # typically HospitalRun is a text field, so "500 mg" vs "500mg" is handled by normalization above
        # This catches things like "500" (missing unit)
        score += 30
        feedback.append(f"Dosage '{final_dosage}' contains '500' but format differs from expected '{expected_dosage}'.")
    else:
        feedback.append(f"Incorrect dosage: '{final_dosage}'. Expected '{expected_dosage}'.")

    # 3. Method Check (20 pts)
    if is_original_doc:
        score += 20
        feedback.append("Bonus: Correctly edited existing record instead of creating a new one.")
    else:
        feedback.append("Method: Re-created record (acceptable, but editing is preferred).")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }