#!/usr/bin/env python3
"""
Verifier for edit_patient_name task.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_edit_patient_name(traj, env_info, task_info):
    """
    Verifies that the patient name was corrected from "Jonh Smithe" to "John Smith".
    
    Scoring:
    - 30 pts: Given name is "John" (Database verified)
    - 30 pts: Family name is "Smith" (Database verified)
    - 20 pts: Modification happened during task (Anti-gaming check)
    - 20 pts: VLM visual confirmation of "John Smith" on the screen
    """
    
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_given = metadata.get('target_given', 'John')
    target_family = metadata.get('target_family', 'Smith')

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

    db_state = result.get("db_state", {})
    
    score = 0
    feedback_parts = []
    
    # 2. Database Verification (Primary Signal)
    actual_given = db_state.get("given_name", "").strip()
    actual_family = db_state.get("family_name", "").strip()
    was_modified = db_state.get("was_modified_during_task", False)

    # Check Given Name (30 pts)
    if actual_given.lower() == target_given.lower():
        score += 30
        feedback_parts.append(f"Given name corrected to '{actual_given}'")
    else:
        feedback_parts.append(f"Given name incorrect (Found: '{actual_given}', Expected: '{target_given}')")

    # Check Family Name (30 pts)
    if actual_family.lower() == target_family.lower():
        score += 30
        feedback_parts.append(f"Family name corrected to '{actual_family}'")
    else:
        feedback_parts.append(f"Family name incorrect (Found: '{actual_family}', Expected: '{target_family}')")

    # Check Anti-Gaming Timestamp (20 pts)
    # Verification only counts if the database record was actually touched during the task
    if was_modified:
        score += 20
        feedback_parts.append("Database record updated during task session")
    else:
        feedback_parts.append("No database modification detected during task timeframe")

    # 3. VLM Verification (Secondary Signal - 20 pts)
    # We look for the corrected name in the final UI state
    vlm_score = 0
    final_screenshot = get_final_screenshot(traj)
    
    if final_screenshot:
        prompt = (
            f"Look at this screenshot of an Electronic Health Record system. "
            f"Does the patient header or banner clearly display the name '{target_given} {target_family}'? "
            f"Ignore other text. Answer with JSON: {{'name_visible': true/false, 'observed_name': '...'}}"
        )
        
        try:
            vlm_resp = query_vlm(prompt=prompt, image=final_screenshot)
            if vlm_resp.get("success"):
                parsed = vlm_resp.get("parsed", {})
                if parsed.get("name_visible", False):
                    vlm_score = 20
                    feedback_parts.append("Visual verification passed")
                else:
                    feedback_parts.append(f"Visual check failed: Observed '{parsed.get('observed_name', 'unknown')}'")
            else:
                feedback_parts.append("VLM query failed")
        except Exception:
            feedback_parts.append("VLM error")
    
    score += vlm_score

    # 4. Final Determination
    # Pass if score >= 80 (Meaning at least names correct + timestamp valid OR names correct + visual valid)
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }