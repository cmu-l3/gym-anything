#!/usr/bin/env python3
"""
Verifier for create_encounter_type task in OpenMRS.

Criteria:
1. Encounter Type "Telehealth Intake" exists and is active (not retired).
2. Description matches the requirement EXACTLY.
3. Creation timestamp is after task start (prevents using pre-existing data).
4. VLM verification of the administrative workflow.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_encounter_type(traj, env_info, task_info):
    """
    Verifies that the agent created the specific Encounter Type in OpenMRS.
    """
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', "Telehealth Intake")
    expected_desc = metadata.get('expected_description', "Initial patient assessment conducted via remote video connection.")

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Scoring Logic
    score = 0
    feedback = []
    
    found = result.get('found', False)
    actual_name = result.get('actual_name', '')
    actual_desc = result.get('actual_description', '')
    is_retired = result.get('is_retired', False)
    created_ts = result.get('created_timestamp', 0)
    task_start_ts = result.get('task_start_timestamp', 0)

    # Criterion 1: Record Exists & Name Match (40 pts)
    if found and actual_name == expected_name:
        score += 40
        feedback.append(f"Success: Encounter Type '{actual_name}' found.")
    elif found:
        score += 20
        feedback.append(f"Partial: Found Encounter Type but name mismatch ('{actual_name}').")
    else:
        feedback.append("Failed: Encounter Type 'Telehealth Intake' not found in database.")
        # Critical failure
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Criterion 2: Description Match (30 pts)
    # We allow slight whitespace flexibility but strictly require content match
    if actual_desc.strip() == expected_desc.strip():
        score += 30
        feedback.append("Success: Description matches exactly.")
    else:
        feedback.append(f"Failed: Description mismatch.\nExpected: '{expected_desc}'\nGot: '{actual_desc}'")

    # Criterion 3: Active Status (10 pts)
    if not is_retired:
        score += 10
        feedback.append("Success: Record is active (not retired).")
    else:
        feedback.append("Failed: The Encounter Type is marked as retired.")

    # Criterion 4: Anti-Gaming Timestamp Check (20 pts)
    if created_ts > task_start_ts:
        score += 20
        feedback.append("Success: Record was created during the task window.")
    else:
        feedback.append("Failed: Record appears to be stale (created before task started).")
        score = 0 # Hard fail for potential pre-caching gaming

    # 3. VLM Verification (Bonus/Confirmation)
    # Checks if they actually accessed the admin UI
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = """
        Review these screenshots of an agent using OpenMRS.
        Did the agent access the 'Administration' or 'Legacy Administration' pages?
        Does any screenshot show a form for 'Manage Encounter Types' or 'Encounter Type Management'?
        Answer YES or NO and briefly explain.
        """
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        feedback.append(f"VLM Analysis: {vlm_res.get('result', 'No analysis')}")

    # Final tally
    passed = score >= 100 # Strict pass: exact configuration required
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }