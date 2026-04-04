#!/usr/bin/env python3
"""
Verifier for batch_delete_company_records task.

Criteria:
1. 'Apex Contractors' records count should be 0 (Target Deleted).
2. 'Summit Partners' records count should equal initial count (Preserved).
3. Database file should have been modified during task.
4. VLM verification of UI interaction (backup).
"""

import json
import os
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_batch_delete(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load programmatic results
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Data extraction
    final_apex = result.get("final_apex_count", -1)
    final_summit = result.get("final_summit_count", -1)
    initial_summit = result.get("initial_summit_count", 2)
    db_modified = result.get("db_modified", False)
    db_found = result.get("db_found", False)

    # --- CRITERION 1: Target Deletion (50 pts) ---
    if not db_found:
        feedback_parts.append("Database file not found for verification.")
    elif final_apex == 0:
        score += 50
        feedback_parts.append("Apex Contractors records successfully deleted.")
    elif final_apex > 0:
        feedback_parts.append(f"Failed: {final_apex} Apex records remain.")
    else:
        feedback_parts.append("Could not verify Apex record count.")

    # --- CRITERION 2: Preservation (30 pts) ---
    if final_summit == initial_summit:
        score += 30
        feedback_parts.append("Summit Partners records preserved.")
    elif final_summit < initial_summit:
        # Partial points if some preserved but some lost
        if final_summit > 0:
            score += 10
            feedback_parts.append(f"Warning: Some Summit records deleted ({final_summit}/{initial_summit} remain).")
        else:
            feedback_parts.append("Critical: All Summit records were accidentally deleted.")
    else:
        # If count increased, that's weird but acceptable for preservation (maybe duplicates?)
        score += 30
        feedback_parts.append("Summit Partners records preserved (count increased).")

    # --- CRITERION 3: Modification Check (10 pts) ---
    if db_modified:
        score += 10
        feedback_parts.append("Database file modification detected.")
    else:
        feedback_parts.append("No database modification timestamp update detected.")

    # --- CRITERION 4: VLM Verification (10 pts) ---
    # Used to verify intent if DB check is ambiguous, or to confirm UI usage
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = (
            "Did the user perform a delete operation on visitor records? "
            "Look for: 1. A list of visitors. 2. Selection of multiple records (highlighted). "
            "3. A delete confirmation dialog or clicking a 'Delete' button. "
            "Answer 'YES' if these actions are visible."
        )
        try:
            # We assume query_vlm returns a dict with 'answer' or text
            # Depending on framework, might need adjustment. 
            # Using generic pattern:
            vlm_response = query_vlm(frames, vlm_prompt)
            if vlm_response and "yes" in str(vlm_response).lower():
                score += 10
                feedback_parts.append("Visual confirmation of delete actions.")
            else:
                feedback_parts.append("Visual verification inconclusive.")
        except Exception:
            pass # VLM failure shouldn't fail task if DB check passed

    # Final Pass Determination
    # Must have deleted Apex (0) and kept Summit (>0)
    passed = (final_apex == 0) and (final_summit > 0) and (score >= 80)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }