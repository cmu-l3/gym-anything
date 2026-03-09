#!/usr/bin/env python3
"""
Verifier for create_custom_ci_type task.

Verifies:
1. CI Type 'Delivery Drone' exists in database.
2. CI Type has a valid parent (is part of hierarchy).
3. Attribute 'Max Range' exists and is text-based.
4. Attribute 'Battery Cycles' exists and is numeric.
5. VLM trajectory check for UI interaction.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_custom_ci_type(traj, env_info, task_info):
    """
    Verify creation of Custom CI Type and Attributes.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check CI Type Existence (40 pts)
    if result.get("citype_exists"):
        score += 40
        feedback_parts.append("CI Type 'Delivery Drone' created successfully")
    else:
        feedback_parts.append("CI Type 'Delivery Drone' NOT found in database")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Check Parent Hierarchy (20 pts)
    # parentcitypeid should be non-empty and not '0' (if root is 0, typically Assets is not root)
    parent_id = result.get("citype_parent_id", "")
    if parent_id and parent_id != "0" and parent_id != "":
        score += 20
        feedback_parts.append("CI Type is correctly nested in hierarchy")
    else:
        feedback_parts.append("CI Type missing parent/hierarchy (is it a root node?)")

    # 3. Check Attributes (40 pts split)
    attributes = result.get("attributes", [])
    
    # Normalize attribute names for comparison
    attrs_map = {a['name'].lower(): a['type'].upper() for a in attributes}
    
    # Check Max Range (Text)
    if "max range" in attrs_map:
        dtype = attrs_map["max range"]
        if any(x in dtype for x in ["CHAR", "TEXT", "STRING", "ALPHA"]):
            score += 20
            feedback_parts.append("'Max Range' attribute correct")
        else:
            score += 10 # Partial for correct name, wrong type
            feedback_parts.append(f"'Max Range' attribute has wrong type: {dtype}")
    else:
        feedback_parts.append("'Max Range' attribute missing")

    # Check Battery Cycles (Numeric)
    if "battery cycles" in attrs_map:
        dtype = attrs_map["battery cycles"]
        if any(x in dtype for x in ["INT", "BIGINT", "NUMERIC", "LONG", "DECIMAL"]):
            score += 20
            feedback_parts.append("'Battery Cycles' attribute correct")
        else:
            score += 10 # Partial for correct name, wrong type
            feedback_parts.append(f"'Battery Cycles' attribute has wrong type: {dtype}")
    else:
        feedback_parts.append("'Battery Cycles' attribute missing")

    # 4. VLM Verification (Safety check)
    # If score is high, verify via VLM that it wasn't just SQL injection (unlikely but good practice)
    # and to confirm UI interaction.
    if score >= 60:
        frames = sample_trajectory_frames(traj, n=4)
        final_scr = get_final_screenshot(traj)
        if frames:
            vlm_prompt = (
                "Review these screenshots of a user creating a CI Type in ServiceDesk Plus. "
                "Did the user create a CI Type named 'Delivery Drone' and add attributes? "
                "Answer yes/no."
            )
            vlm_res = query_vlm(images=frames + [final_scr], prompt=vlm_prompt).get("parsed", {})
            # We don't deduct points heavily here as DB is truth, but we use it for sanity
            if not vlm_res.get("answer_bool", True):
                feedback_parts.append("(VLM could not visually confirm workflow)")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }