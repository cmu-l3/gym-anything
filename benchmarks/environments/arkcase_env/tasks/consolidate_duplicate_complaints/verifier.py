#!/usr/bin/env python3
"""
Verifier for consolidate_duplicate_complaints task.
Checks if data was preserved, cases linked, and duplicate closed.
"""

import json
import os
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_consolidate_duplicate_complaints(traj, env_info, task_info):
    """
    Verify consolidation workflow.
    
    Criteria:
    1. Note Preserved (30 pts): Master case has note with text from duplicate.
    2. Link Established (30 pts): Cases are associated in the system.
    3. Duplicate Closed (30 pts): Duplicate case status is CLOSED.
    4. Master Active (10 pts): Master case status is still ACTIVE.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Check 1: Note Preserved
    if result.get('note_preserved', False):
        score += 30
        feedback_parts.append("Data preserved in note")
    else:
        feedback_parts.append("FAIL: Description not copied to Master Case note")

    # Check 2: Link Established
    if result.get('link_established', False):
        score += 30
        feedback_parts.append("Association link created")
    else:
        feedback_parts.append("FAIL: Cases not linked/associated")

    # Check 3: Duplicate Closed
    dup_status = result.get('duplicate_status', '').upper()
    if 'CLOSE' in dup_status:
        score += 30
        feedback_parts.append("Duplicate case closed")
    else:
        feedback_parts.append(f"FAIL: Duplicate case status is {dup_status} (expected CLOSED)")

    # Check 4: Master Active
    master_status = result.get('master_status', '').upper()
    if 'ACTIVE' in master_status or 'NEW' in master_status:
        score += 10
        feedback_parts.append("Master case remains active")
    else:
        feedback_parts.append(f"Master case status is {master_status} (expected ACTIVE)")

    # VLM Sanity Check (if score is high but not perfect, or to catch false positives)
    # We only use VLM if we have partial success to confirm intent, or for debug
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    
    # We rely primarily on API verification for this task as it's definitive.
    # If API checks pass, we trust them. VLM is supplementary here.
    
    passed = score >= 70 and result.get('link_established', False) and 'CLOSE' in dup_status
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }