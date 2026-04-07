#!/usr/bin/env python3
"""
Verifier for create_encounter_role task.
Verifies that the Encounter Role was created in the database with correct details.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_encounter_role(traj, env_info, task_info):
    """
    Verifies the creation of the 'Medical Scribe' encounter role.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Expected values
    expected_name = task_info.get('metadata', {}).get('expected_name', 'Medical Scribe')
    expected_desc = task_info.get('metadata', {}).get('expected_description', 'Assists with documentation')

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check if role exists (40 pts)
    if result.get('role_found'):
        score += 40
        feedback_parts.append("Role 'Medical Scribe' found in database")
    else:
        feedback_parts.append("Role 'Medical Scribe' NOT found in database")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Check description (20 pts)
    actual_desc = result.get('role_description', '')
    if actual_desc.strip() == expected_desc:
        score += 20
        feedback_parts.append("Description matches exactly")
    elif expected_desc in actual_desc:
        score += 10
        feedback_parts.append(f"Description partial match (Got: '{actual_desc}')")
    else:
        feedback_parts.append(f"Description mismatch (Expected: '{expected_desc}', Got: '{actual_desc}')")

    # 3. Check retired status (10 pts)
    # retired should be 0 or false
    retired = str(result.get('role_retired', '1')).lower()
    if retired in ['0', 'false']:
        score += 10
        feedback_parts.append("Role is active")
    else:
        feedback_parts.append("Role is retired/inactive")

    # 4. Anti-gaming: Created timestamp check (20 pts)
    # The role must have been created AFTER the task started
    created_ts = int(result.get('role_created_timestamp', 0))
    start_ts = int(result.get('task_start_timestamp', 0))
    
    # Allow small clock skew (e.g. 5 seconds), but generally created > start
    if created_ts >= start_ts - 5:
        score += 20
        feedback_parts.append("Role created during task session")
    else:
        feedback_parts.append(f"Role creation time ({created_ts}) is before task start ({start_ts}) - pre-existing data detected?")
        score = 0 # Fail if data was pre-existing

    # 5. VLM Navigation Check (10 pts)
    # We want to see if the agent visited the Administration page
    # This distinguishes between "I used a script" vs "I navigated the UI"
    # though for this task, script usage is unlikely given the env constraints.
    frames = sample_trajectory_frames(traj, n=5)
    
    # Simple check: do we see "Administration" or "Role" in the frames?
    # Since we don't have a VLM available in this strict python verifier block without importing external tools,
    # we will rely on the implicit "App Running" check as a proxy for basic engagement,
    # OR if the framework supports the `query_vlm` utility, we use that.
    
    # Assuming standard framework availability:
    try:
        from gym_anything.vlm import query_vlm
        vlm_score = 0
        prompt = "Does the user navigate to an Administration or Settings screen to manage roles? Look for 'Administration', 'Encounter Roles', or forms to add a role."
        vlm_res = query_vlm(images=frames, prompt=prompt)
        
        if vlm_res.get('success') and vlm_res.get('parsed', {}).get('answer', False):
             score += 10
             feedback_parts.append("Visual verification passed")
        else:
             # Fallback points if query fails but app was running
             if result.get('app_running'):
                 score += 5
                 feedback_parts.append("App was running (Visual verify skipped)")
    except ImportError:
        # Fallback if VLM module not present
        if result.get('app_running'):
            score += 10
            feedback_parts.append("App interaction detected")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }