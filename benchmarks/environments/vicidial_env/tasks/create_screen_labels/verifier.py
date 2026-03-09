#!/usr/bin/env python3
"""
Verifier for create_screen_labels task.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_screen_labels(traj, env_info, task_info):
    """
    Verify the screen label was created with correct fields.
    
    Scoring:
    - Label Exists: 15 pts
    - Label Name Correct: 10 pts
    - Field Labels Correct: ~6-7 pts each (Total 70 pts)
    - VLM Verification: 5 pts (Check if agent navigated to Admin/Screen Labels)
    
    Total: 100 pts
    Pass Threshold: 60 pts
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

    # Get expected values
    metadata = task_info.get('metadata', {})
    expected_values = metadata.get('expected_values', {})
    
    score = 0
    feedback_parts = []
    
    # 1. Check Existence (15 pts)
    exists = result.get("exists", False)
    initial_count = result.get("initial_count", 1) # Default to 1 (fail) if missing
    
    if exists:
        if initial_count == 0:
            score += 15
            feedback_parts.append("Label HEALTH01 successfully created")
        else:
            feedback_parts.append("Label HEALTH01 exists but existed before task (Anti-gaming fail)")
            return {"passed": False, "score": 0, "feedback": "Label existed before task started"}
    else:
        feedback_parts.append("Label HEALTH01 NOT found")
        return {"passed": False, "score": 0, "feedback": "Label HEALTH01 was not created"}

    # 2. Check Data Fields (80 pts total distributed)
    data = result.get("data", {})
    
    # Map fields to points
    field_points = {
        "label_name": 10,
        "label_title": 8,
        "label_first_name": 7,
        "label_last_name": 7,
        "label_address1": 7,
        "label_address2": 5,
        "label_address3": 8,
        "label_city": 5,
        "label_state": 5,
        "label_alt_phone": 8,
        "label_email": 5,
        "label_comments": 5
    }
    
    fields_correct = 0
    
    for field, points in field_points.items():
        expected = expected_values.get(field, "").strip()
        actual = data.get(field, "").strip()
        
        if actual == expected:
            score += points
            fields_correct += 1
        else:
            feedback_parts.append(f"{field} mismatch (Exp: '{expected}', Got: '{actual}')")

    feedback_parts.append(f"{fields_correct}/12 fields correct")

    # 3. VLM Verification (5 pts)
    # Ensure the agent actually visited the Screen Labels page
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        vlm_prompt = """
        Analyze these screenshots of a user interacting with Vicidial Admin.
        Does the user verify navigate to the 'Admin' section and then to 'Screen Labels'?
        Look for headers like "ADMINISTRATION" or "SCREEN LABELS" or forms with fields like "Label ID", "Label Name", "Label Title".
        
        Return JSON:
        {
            "screen_labels_page_visited": true/false,
            "reasoning": "..."
        }
        """
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        if vlm_result and vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            if parsed.get("screen_labels_page_visited", False):
                vlm_score = 5
                feedback_parts.append("VLM verified Screen Labels page visit")
            else:
                feedback_parts.append("VLM did not observe Screen Labels page")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: give points if DB is correct, assuming they must have used UI
        if fields_correct >= 10:
            vlm_score = 5

    score += vlm_score

    # Final Result
    passed = (score >= 60) and exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }