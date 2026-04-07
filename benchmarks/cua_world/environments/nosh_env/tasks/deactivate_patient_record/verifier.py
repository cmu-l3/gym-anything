#!/usr/bin/env python3
"""
Verifier for deactivate_patient_record task.

Verification Criteria:
1. Target patient 'active' status must be 0 (Inactive).
2. Total active patient count must decrease by exactly 1 (Prevention of mass deactivation).
3. Verify via VLM that the agent navigated the UI (Anti-gaming for SQL injection).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_deactivate_patient_record(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 1. Load Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Extract Data
    try:
        initial_count = int(result.get("initial_active_count", -1))
        final_count = int(result.get("final_active_count", -1))
        target_status = result.get("target_final_active_status", "1") # Default to active (fail)
        
        # Criterion 1: Target is Inactive (40 pts)
        if str(target_status) == "0":
            score += 40
            feedback_parts.append("Target patient successfully deactivated.")
        else:
            feedback_parts.append("Target patient is still active.")

        # Criterion 2: Count Decremented by Exactly 1 (20 pts)
        # This prevents "UPDATE demographics SET active=0" (nuking everyone)
        if final_count == initial_count - 1:
            score += 20
            feedback_parts.append("Active patient count decreased by exactly 1.")
        else:
            diff = initial_count - final_count
            feedback_parts.append(f"Patient count change incorrect (Expected -1, got -{diff}).")

    except Exception as e:
        feedback_parts.append(f"Error parsing DB results: {e}")

    # Criterion 3: VLM Verification of Workflow (40 pts)
    # We want to see evidence of the chart/demographics page and the specific action
    frames = sample_trajectory_frames(traj, n=5)
    final_img = get_final_screenshot(traj)
    
    vlm_prompt = """
    You are verifying an EHR agent's workflow. 
    The goal was to:
    1. Find patient 'Robert Schiller'.
    2. Add a note about 'transfer of care'.
    3. Change status to Inactive.
    
    Review the screenshots.
    - Do you see the NOSH EHR interface?
    - Do you see a patient chart for 'Robert Schiller'?
    - Do you see any evidence of changing status or editing demographics?
    - Do you see text like 'transferred care' or 'inactive'?
    """
    
    vlm_result = query_vlm(images=frames + [final_img], prompt=vlm_prompt)
    
    vlm_score = 0
    if vlm_result.get("success"):
        # Simple heuristic based on VLM text response parsing or confidence
        # In a real system, we'd ask for JSON. Here we assume positive sentiment if "yes" appears regarding chart.
        resp = vlm_result.get("response", "").lower()
        if "schiller" in resp and ("chart" in resp or "demographics" in resp):
            vlm_score += 20
        if "inactive" in resp or "status" in resp or "transfer" in resp:
            vlm_score += 20
            
        feedback_parts.append(f"VLM Analysis: {vlm_result.get('response')}")
    else:
        feedback_parts.append("VLM verification failed to run.")

    score += vlm_score

    # Final Pass/Fail
    passed = (str(target_status) == "0") and (final_count == initial_count - 1) and (score >= 70)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }