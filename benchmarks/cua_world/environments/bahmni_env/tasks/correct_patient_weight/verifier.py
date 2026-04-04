#!/usr/bin/env python3
"""
Verifier for correct_patient_weight task.

Criteria:
1. Patient must have an active weight observation of 85 kg (+/- tolerance).
2. Patient must NOT have an active weight observation > 200 kg (erroneous 850kg must be gone).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_correct_patient_weight(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    correct_weight = metadata.get('correct_weight', 85.0)
    erroneous_threshold = 200.0  # Anything above this is considered the error or a new error
    tolerance = 0.5

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if 'error' in result:
        return {"passed": False, "score": 0, "feedback": f"Export script error: {result['error']}"}

    active_weights = result.get('active_weights', [])
    app_running = result.get('app_running', False)
    
    feedback_parts = []
    score = 0
    
    # Check 1: Is the correct weight present? (50 pts)
    correct_found = False
    for w in active_weights:
        if abs(w - correct_weight) <= tolerance:
            correct_found = True
            break
            
    if correct_found:
        score += 50
        feedback_parts.append(f"✅ Correct weight ({correct_weight} kg) found.")
    else:
        feedback_parts.append(f"❌ Correct weight ({correct_weight} kg) NOT found in active observations.")

    # Check 2: Is the erroneous weight gone? (50 pts)
    # The error was 850. We check if anything unrealistic (>200) exists.
    error_still_present = False
    for w in active_weights:
        if w > erroneous_threshold:
            error_still_present = True
            break
            
    if not error_still_present:
        score += 50
        feedback_parts.append("✅ Erroneous weight removed/corrected.")
    else:
        feedback_parts.append("❌ Erroneous weight (or extreme value) still present.")

    # Penalize if app closed (optional, but good practice)
    if not app_running:
        feedback_parts.append("⚠️ Browser was closed (minor warning).")

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts),
        "details": {
            "active_weights": active_weights,
            "correct_found": correct_found,
            "error_removed": not error_still_present
        }
    }