#!/usr/bin/env python3
"""Verifier for search_flag_security_incident task."""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_search_flag_security_incident(traj, env_info, task_info):
    """
    Verify the security triage task.
    
    Criteria:
    1. 'Security Alert' tag created (10 pts)
    2. Correct conversation tagged (30 pts)
    3. Assigned to Admin (20 pts)
    4. Internal note added (20 pts)
    5. Distractors NOT tagged (20 pts)
    """

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Programmatic Verification
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Criterion 1: Tag Exists
    if result.get('tag_exists'):
        score += 10
        feedback_parts.append("Tag 'Security Alert' created")
    else:
        feedback_parts.append("Tag 'Security Alert' NOT found")

    # Criterion 2: Target Tagged
    if result.get('target_tagged'):
        score += 30
        feedback_parts.append("Correct conversation tagged")
    else:
        feedback_parts.append("Target conversation NOT tagged")

    # Criterion 3: Assigned to Admin
    if result.get('assigned_to_admin'):
        score += 20
        feedback_parts.append("Assigned to Admin")
    else:
        feedback_parts.append("Not assigned to Admin")

    # Criterion 4: Note Added
    if result.get('note_found'):
        score += 20
        feedback_parts.append("Internal note added")
    else:
        feedback_parts.append("Internal note missing or incorrect content")

    # Criterion 5: Distractors (Negative check)
    distractors_tagged = result.get('distractors_tagged_count', 0)
    if distractors_tagged == 0:
        score += 20
        feedback_parts.append("No distractors tagged")
    else:
        feedback_parts.append(f"Penalty: {distractors_tagged} distractor(s) incorrectly tagged")

    # 2. VLM Verification (Trajectory Check)
    # Ensure the user actually used the interface
    try:
        frames = sample_trajectory_frames(traj, n=3)
        final_shot = get_final_screenshot(traj)
        
        # Simple check: did they visit the conversation view?
        vlm_prompt = "Does this sequence show a user interacting with a help desk ticket interface, specifically adding a tag or note?"
        vlm_result = query_vlm(images=frames + [final_shot], prompt=vlm_prompt)
        
        if "yes" in vlm_result.lower():
            logger.info("VLM confirmed interaction")
        else:
            logger.warning("VLM could not confirm interaction")
            # We don't deduct points here as the DB check is authoritative, 
            # but this log helps with debugging "magic" solutions
            
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }