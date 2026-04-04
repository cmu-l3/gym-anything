#!/usr/bin/env python3
"""
Verifier for Enforce Process Quality Rules task.

Criteria:
1. Project is using a custom process (not "Agile" system default).
2. A process rule exists: State=Closed -> Required=StoryPoints.
3. Test Work Item is Closed.
4. Test Work Item has Story Points assigned.
"""

import json
import logging
import os
import tempfile
from datetime import datetime

# Import VLM utils if available (assumed from context)
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
except ImportError:
    pass  # Fallback handles missing imports

logger = logging.getLogger(__name__)

def verify_enforce_process_quality_rules(traj, env_info, task_info):
    """
    Verify the Azure DevOps process customization task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON from VM
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Users\\Docker\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 2. Check Process Configuration (40 pts)
    # The project must NOT be using the system process
    is_system = result.get("is_system_process", True)
    process_name = result.get("current_process_name", "Unknown")
    
    if not is_system and process_name != "Agile":
        score += 20
        feedback.append(f"Project migrated to custom process: {process_name}")
    else:
        feedback.append(f"Project still using system/default process: {process_name}")

    # 3. Check Rule Existence (30 pts)
    rule_found = result.get("rule_found", False)
    if rule_found:
        score += 30
        feedback.append("Correct process rule found (State=Closed -> Required=Points)")
    else:
        feedback.append("Required process rule NOT found")

    # 4. Check Work Item State (Data Validation) (30 pts)
    wi_state = result.get("work_item_state", "")
    wi_points = result.get("work_item_points", None)
    
    # State should be Closed
    if wi_state == "Closed":
        score += 15
        feedback.append("Test work item successfully closed")
    else:
        feedback.append(f"Test work item state is '{wi_state}' (expected Closed)")

    # Points should be > 0 (float or int)
    try:
        if wi_points is not None and float(wi_points) > 0:
            score += 15
            feedback.append(f"Test work item has valid story points: {wi_points}")
        else:
            feedback.append(f"Test work item missing story points (value: {wi_points})")
    except (ValueError, TypeError):
         feedback.append(f"Invalid story points value: {wi_points}")

    # 5. VLM Verification (Bonus/Confirmation)
    # We look for the "Process" settings page or the "Work Item" form in the trajectory
    # This helps confirm they actually interacted with the UI
    try:
        frames = sample_trajectory_frames(traj, n=5)
        if frames:
            vlm_prompt = "Does the user interface show Azure DevOps Process settings or a Work Item form with a Rule configuration?"
            vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
            if vlm_res.get("success") and vlm_res.get("parsed", {}).get("answer_bool", False):
                # Small boost if we are on the borderline, or just logging
                logger.info("VLM confirmed UI interaction with Process settings")
    except Exception:
        pass # Optional check

    passed = score >= 60 and rule_found  # Rule existence is critical
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }