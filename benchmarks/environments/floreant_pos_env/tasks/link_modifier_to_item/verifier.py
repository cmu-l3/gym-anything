#!/usr/bin/env python3
"""
Verifier for link_modifier_to_item task.

Verifies that:
1. The Menu Item (ID 9901) still exists.
2. The Modifier Group (ID 9901) still exists.
3. A link exists between them in the join table.
4. Uses VLM to confirm Back Office interaction via trajectory.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_link_modifier_to_item(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load DB Verification Results
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
    feedback = []

    # Criteria 1: Item and Group Integrity (20 pts)
    item_exists = int(result.get("item_exists", 0)) > 0
    group_exists = int(result.get("group_exists", 0)) > 0
    
    if item_exists:
        score += 10
        feedback.append("Menu Item exists.")
    else:
        feedback.append("Menu Item deleted or missing.")

    if group_exists:
        score += 10
        feedback.append("Modifier Group exists.")
    else:
        feedback.append("Modifier Group deleted or missing.")

    # Criteria 2: Link Established (50 pts)
    link_count = int(result.get("link_count", 0))
    if link_count >= 1:
        score += 50
        feedback.append("Modifier successfully linked to Item.")
    else:
        feedback.append("No link found between Item and Modifier Group.")

    # Criteria 3: VLM Trajectory Verification (30 pts)
    # Check if agent actually went to Back Office > Menu Items
    frames = sample_trajectory_frames(traj, n=4)
    if not frames:
        feedback.append("No trajectory frames available for visual verification.")
    else:
        prompt = """
        Review these screenshots of a Floreant POS session.
        The goal was to link a modifier group to a menu item in the Back Office.
        
        Look for:
        1. A form titled "Menu Item" or similar editor.
        2. A tab or section labeled "Modifier" or "Modifier Groups".
        3. A list of items including "Grilled Ribeye Steak".
        
        Return JSON:
        {
            "seen_editor": boolean,
            "seen_modifier_tab": boolean,
            "confidence": "low|medium|high"
        }
        """
        
        try:
            vlm_resp = query_vlm(images=frames, prompt=prompt)
            if vlm_resp.get("success"):
                parsed = vlm_resp.get("parsed", {})
                if parsed.get("seen_editor"):
                    score += 15
                    feedback.append("Visuals confirm Menu Item editor accessed.")
                if parsed.get("seen_modifier_tab"):
                    score += 15
                    feedback.append("Visuals confirm Modifier tab accessed.")
            else:
                # Fallback if VLM fails: award points if DB link is correct (assume they used UI)
                if link_count >= 1:
                    score += 30
                    feedback.append("Skipping visual check (DB link confirmed).")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            if link_count >= 1:
                score += 30

    passed = (score >= 70) and (link_count >= 1)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }