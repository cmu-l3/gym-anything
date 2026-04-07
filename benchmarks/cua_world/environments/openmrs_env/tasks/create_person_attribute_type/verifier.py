#!/usr/bin/env python3
"""
Verifier for create_person_attribute_type task.

Verification Criteria:
1. Database record exists for "Driver's License Number" (40 pts)
2. Format is 'java.lang.String' (20 pts)
3. Description matches expected (10 pts)
4. Record is not retired (10 pts)
5. Created AFTER task start time (Anti-gaming) (20 pts)
6. VLM Trajectory Verification (Secondary validation of UI interaction)
"""

import json
import tempfile
import os
import logging
import time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Import VLM utils provided by the framework
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

def verify_create_person_attribute_type(traj, env_info, task_info):
    """
    Verify that the Person Attribute Type was created correctly in the database.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', "Driver's License Number")
    expected_format = metadata.get('expected_format', "java.lang.String")
    expected_desc = metadata.get('expected_description', "Government issued driver license ID")

    # 1. Load result JSON
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

    score = 0
    feedback_parts = []
    
    # 2. Evaluate Database State
    exists = result.get('exists', False)
    actual_name = result.get('actual_name', "")
    actual_format = result.get('actual_format', "")
    actual_desc = result.get('actual_description', "")
    actual_retired = result.get('actual_retired', False)
    date_created_ts = result.get('date_created_ts', 0)
    task_start_ts = result.get('task_start_ts', 0)

    # Criterion 1: Exists (40 pts)
    if exists:
        score += 40
        feedback_parts.append("Attribute type record found.")
    else:
        feedback_parts.append("Attribute type record NOT found.")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed: No 'Driver's License Number' attribute type found in database."
        }

    # Criterion 2: Correct Format (20 pts)
    # Check exact match or acceptable variants if any (though java.lang.String is precise)
    if actual_format == expected_format:
        score += 20
        feedback_parts.append(f"Format correct ({actual_format}).")
    else:
        feedback_parts.append(f"Format incorrect: expected '{expected_format}', got '{actual_format}'.")

    # Criterion 3: Description (10 pts)
    # Allow partial match or case insensitivity
    if expected_desc.lower() in actual_desc.lower():
        score += 10
        feedback_parts.append("Description correct.")
    else:
        feedback_parts.append(f"Description mismatch: expected '{expected_desc}', got '{actual_desc}'.")

    # Criterion 4: Not Retired (10 pts)
    if not actual_retired:
        score += 10
        feedback_parts.append("Record is active (not retired).")
    else:
        feedback_parts.append("Record is retired/voided.")

    # Criterion 5: Anti-Gaming Timestamp Check (20 pts)
    # Allow a small buffer (e.g. 5 seconds) for clock skew between containers
    if date_created_ts >= (task_start_ts - 5):
        score += 20
        feedback_parts.append("Created during task session.")
    else:
        feedback_parts.append(f"Creation time ({date_created_ts}) predates task start ({task_start_ts}).")

    # 3. VLM Trajectory Verification (Bonus/Confirmation)
    # We check if the agent actually visited the Admin UI
    try:
        frames = sample_trajectory_frames(traj, n=4)
        vlm_prompt = """
        Analyze these screenshots from an OpenMRS Electronic Health Record task.
        The user is supposed to be configuring a 'Person Attribute Type'.
        
        Look for:
        1. The 'Administration' or 'Legacy Administration' screen.
        2. A list or table titled 'Person Attribute Types'.
        3. A form where 'Name', 'Format', and 'Description' are being entered.
        
        Does the user appear to be performing system administration/configuration?
        """
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        # We don't modify score based on VLM here to keep it deterministic based on DB,
        # but we append the observation to feedback.
        if vlm_result.get('success'):
            feedback_parts.append(f"VLM Analysis: {vlm_result.get('parsed', {}).get('answer', 'Workflow observed')}")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")

    # Final Pass Determination
    # Must exist, be correct format, and be new work.
    passed = (score >= 80) and (actual_format == expected_format) and (date_created_ts >= (task_start_ts - 5))

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }