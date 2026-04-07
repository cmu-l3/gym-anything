#!/usr/bin/env python3
"""
Verifier for terminate_employee task.

Scoring Criteria:
1. Employee Status (25 pts): Employee must have a termination ID in the database.
2. Anti-Gaming (15 pts): Status changed DURING the task (was not terminated at start).
3. Termination Date (20 pts): Must be '2025-01-31'.
4. Termination Reason (20 pts): Must be 'Resignation'.
5. Note Content (20 pts): Must contain 'formal resignation' and 'January 31, 2025'.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_terminate_employee(traj, env_info, task_info):
    # 1. Setup access to result file
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract metadata and results
    metadata = task_info.get('metadata', {})
    expected = metadata.get('termination_details', {})
    
    score = 0
    feedback_parts = []
    
    # --- Criterion 1: Termination Record Exists (25 pts) ---
    is_terminated = result.get('is_terminated', False)
    if is_terminated:
        score += 25
        feedback_parts.append("✅ Employee termination record created.")
    else:
        feedback_parts.append("❌ Employee was NOT terminated.")
        # If not terminated, other checks fail automatically
        return {
            "passed": False, 
            "score": score, 
            "feedback": " ".join(feedback_parts)
        }

    # --- Criterion 2: Anti-Gaming / State Change (15 pts) ---
    was_already_terminated = result.get('was_already_terminated', False)
    if not was_already_terminated:
        score += 15
        feedback_parts.append("✅ New termination record generated (fresh state).")
    else:
        feedback_parts.append("⚠️ Warning: Employee was already terminated before task started (State not clean).")

    # --- Criterion 3: Date Accuracy (20 pts) ---
    actual_date = result.get('actual_date', '').strip()
    expected_date = expected.get('date', '2025-01-31')
    if actual_date == expected_date:
        score += 20
        feedback_parts.append(f"✅ Correct date: {actual_date}.")
    else:
        feedback_parts.append(f"❌ Incorrect date: Found '{actual_date}', expected '{expected_date}'.")

    # --- Criterion 4: Reason Accuracy (20 pts) ---
    actual_reason = result.get('actual_reason', '').strip()
    expected_reason = expected.get('reason', 'Resignation')
    if actual_reason == expected_reason:
        score += 20
        feedback_parts.append(f"✅ Correct reason: {actual_reason}.")
    else:
        feedback_parts.append(f"❌ Incorrect reason: Found '{actual_reason}', expected '{expected_reason}'.")

    # --- Criterion 5: Note Content (20 pts) ---
    actual_note = result.get('actual_note', '').lower()
    keywords = expected.get('note_keywords', ["formal resignation", "january 31, 2025"])
    
    # Check for keywords (case-insensitive)
    found_keywords = [k for k in keywords if k.lower() in actual_note]
    
    if len(found_keywords) == len(keywords):
        score += 20
        feedback_parts.append("✅ Note contains all required details.")
    elif len(found_keywords) > 0:
        score += 10
        feedback_parts.append(f"⚠️ Note partially correct. Missing keywords. Found: {actual_note}")
    else:
        feedback_parts.append("❌ Note missing required details.")

    # 3. Final Determination
    passed = (score >= 65)  # Requires existence + date + reason (approx)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }