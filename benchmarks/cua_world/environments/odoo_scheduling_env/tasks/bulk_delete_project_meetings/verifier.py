#!/usr/bin/env python3
"""
Verifier for bulk_delete_project_meetings task.

Criteria:
1. All "Project Phoenix" events deleted (0 remaining).
2. Non-Phoenix events preserved (minimal collateral damage).
3. Evidence of state change (anti-gaming).
4. VLM verification of trajectory (search/select actions).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bulk_delete_project_meetings(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task metadata
    metadata = task_info.get('metadata', {})
    expected_deleted = metadata.get('expected_deleted_count', 4)
    preservation_threshold = metadata.get('preservation_threshold', 0.9)

    # 1. Retrieve Programmatic Result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Evaluate Programmatic Criteria
    
    # Criterion 1: Phoenix events deleted (Max 50 pts)
    phoenix_remaining = result.get('phoenix_remaining', 999)
    deleted_phoenix = result.get('deleted_phoenix_count', 0)
    
    if phoenix_remaining == 0:
        score += 50
        feedback_parts.append("All Project Phoenix events deleted")
    elif phoenix_remaining <= 2:
        # Partial credit if some were deleted
        score += 25
        feedback_parts.append(f"Partially deleted Phoenix events ({deleted_phoenix}/{expected_deleted} deleted)")
    else:
        feedback_parts.append(f"Failed to delete Phoenix events ({phoenix_remaining} remain)")

    # Criterion 2: Non-Phoenix events preserved (Max 20 pts)
    # We want to ensure the agent didn't just 'delete all'
    baseline = result.get('baseline', {})
    baseline_non_phoenix = baseline.get('non_phoenix_events', 0)
    non_phoenix_remaining = result.get('non_phoenix_remaining', 0)
    
    preservation_ratio = 1.0
    if baseline_non_phoenix > 0:
        preservation_ratio = non_phoenix_remaining / baseline_non_phoenix

    if preservation_ratio >= preservation_threshold:
        score += 20
        feedback_parts.append(f"Non-target events preserved ({int(preservation_ratio*100)}%)")
    elif preservation_ratio >= 0.7:
        score += 10
        feedback_parts.append(f"Some non-target events lost ({int(preservation_ratio*100)}% preserved)")
    else:
        feedback_parts.append(f"Too many non-target events deleted ({int(preservation_ratio*100)}% preserved)")

    # Criterion 3: Anti-Gaming / State Change (Max 15 pts)
    if result.get('state_changed', False) and deleted_phoenix > 0:
        score += 15
        feedback_parts.append("Calendar state successfully modified")
    else:
        feedback_parts.append("No meaningful change detected in calendar")

    # 3. VLM Verification (Max 15 pts)
    # We verify the workflow: did they search? select?
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    vlm_prompt = """
    You are verifying an agent's workflow in Odoo Calendar.
    The task was to search for 'Project Phoenix' events and delete them.
    
    Look at the sequence of images and the final state.
    1. Is there evidence of a search operation? (e.g., text 'Phoenix' in search bar, or filtered list)
    2. Is there evidence of selecting multiple items or deleting items?
    3. Does the final state look like a calendar or list view?
    
    Answer JSON:
    {
        "search_visible": true/false,
        "selection_or_delete_action": true/false,
        "final_view_valid": true/false,
        "explanation": "..."
    }
    """
    
    vlm_score = 0
    try:
        vlm_res = query_vlm(prompt=vlm_prompt, images=frames + [final_frame])
        if vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('search_visible'):
                vlm_score += 5
            if parsed.get('selection_or_delete_action'):
                vlm_score += 5
            if parsed.get('final_view_valid'):
                vlm_score += 5
            
            feedback_parts.append(f"VLM verification: {vlm_score}/15 pts")
        else:
            # Fallback if VLM fails: give points if programmatic success is high
            if score >= 70:
                vlm_score = 15
                feedback_parts.append("VLM skipped (programmatic pass)")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        if score >= 70:
            vlm_score = 15

    score += vlm_score

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }