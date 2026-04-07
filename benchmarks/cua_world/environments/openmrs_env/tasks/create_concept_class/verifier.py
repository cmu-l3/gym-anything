#!/usr/bin/env python3
"""
Verifier for create_concept_class task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_concept_class(traj, env_info, task_info):
    """
    Verifies that the SDOH concept class was created correctly.
    
    Scoring Criteria:
    - Class Exists (40 pts)
    - New Creation (Anti-gaming) (20 pts)
    - Correct Description (20 pts)
    - Correct Abbreviation (10 pts)
    - Active Status (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result JSON
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

    # 2. Extract Metadata & Result Fields
    metadata = task_info.get('metadata', {})
    expected_desc = metadata.get('expected_description', "Social factors affecting health outcomes")
    expected_abbr = metadata.get('expected_abbreviation', "SDOH")
    
    record_exists = result.get('record_exists', False)
    created_during_task = result.get('created_during_task', False)
    actual_desc = result.get('description', "")
    actual_abbr = result.get('abbreviation', "")
    retired = str(result.get('retired', "1")) # "0" is false (active), "1" is true (retired)

    score = 0
    feedback = []

    # Criterion 1: Record Exists (40 pts)
    if record_exists:
        score += 40
        feedback.append("Success: 'SDOH' Concept Class found in database.")
    else:
        feedback.append("Fail: 'SDOH' Concept Class NOT found in database.")
        # If record doesn't exist, use VLM to see if they tried but failed (partial credit unlikely for DB tasks but good for feedback)
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Criterion 2: Created During Task (20 pts)
    if created_during_task:
        score += 20
        feedback.append("Success: Record was created during the task session.")
    else:
        feedback.append("Fail: Record creation timestamp predates task start (Anti-gaming check failed).")

    # Criterion 3: Correct Description (20 pts)
    # Allow case-insensitive partial match
    if expected_desc.lower() in actual_desc.lower():
        score += 20
        feedback.append(f"Success: Description matches '{expected_desc}'.")
    else:
        feedback.append(f"Fail: Description mismatch. Expected '{expected_desc}', got '{actual_desc}'.")

    # Criterion 4: Correct Abbreviation (10 pts)
    if actual_abbr == expected_abbr:
        score += 10
        feedback.append(f"Success: Abbreviation is '{expected_abbr}'.")
    else:
        feedback.append(f"Fail: Abbreviation mismatch. Expected '{expected_abbr}', got '{actual_abbr}'.")

    # Criterion 5: Active Status (10 pts)
    # retired should be "0" or "false"
    if retired in ["0", "false", "False"]:
        score += 10
        feedback.append("Success: Class is Active (not retired).")
    else:
        feedback.append("Fail: Class is marked as Retired.")

    # 3. VLM Verification (Safety Check / Process Verification)
    # We use this to confirm the agent actually interacted with the UI, even if DB is correct
    # (Though DB correctness implies UI interaction or API usage, UI is the target method)
    try:
        frames = sample_trajectory_frames(traj, n=4)
        vlm_prompt = (
            "Review these screenshots of a user interacting with OpenMRS. "
            "Did the user access the Administration or Dictionary/Concept Class management screen? "
            "Is there any visibility of a form where 'SDOH' was entered?"
        )
        # We don't strictly penalize score based on VLM if DB is perfect, 
        # but it helps verify the *method*.
        # For this implementation, we simply log the VLM check.
        pass 
    except Exception:
        pass

    passed = (score >= 80) and record_exists and created_during_task

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }