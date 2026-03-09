#!/usr/bin/env python3
"""
Verifier for bulk_checkin_expected_group task.

Task: Check in 3 pre-registered visitors (Elena Fisher, Victor Sullivan, Chloe Frazer).

Verification Strategy:
1. Primary: VLM analysis of the final screenshot.
   - Must show the "Active" or "Signed In" list.
   - Must see all three names in the list.
   - Must see "Time In" populated.
2. Secondary: VLM Trajectory analysis.
   - Confirm agent navigated to "Expected" list (vs creating new records).
3. Tertiary: Database file modification check.
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_FINAL_STATE_PROMPT = """You are verifying a Visitor Management System task.
The goal was to check in three specific visitors: Elena Fisher, Victor Sullivan, and Chloe Frazer.

Look at this final screenshot of the Jolly Lobby Track application.
1. Does the screen show an "Active Visitors", "Signed In", or "Log" list?
2. Are the following names visible in the list:
   - Elena Fisher
   - Victor Sullivan
   - Chloe Frazer
3. Do these records appear to be "Signed In" (e.g., have a "Time In" timestamp, status is "In", or similar)?

Respond in JSON format:
{
    "is_visitor_list": true/false,
    "names_found": ["list", "of", "names", "found"],
    "all_visitors_present": true/false,
    "status_is_signed_in": true/false,
    "confidence": "low/medium/high",
    "reasoning": "brief explanation"
}
"""

VLM_TRAJECTORY_PROMPT = """You are analyzing the workflow of a user in a Visitor Management System.
The user was supposed to FIND existing pre-registered visitors and check them in, NOT create new ones.

Look at these screenshots from the session.
Did the user:
1. Navigate to a list of "Expected", "Pre-registered", or "Scheduled" visitors?
2. Select existing records from a list?
3. Click a "Check In" or "Sign In" button?

Or did they:
1. Open a "New Visitor" form and type the names manually? (This is WRONG).

Respond in JSON format:
{
    "used_existing_records": true/false,
    "created_new_records": true/false,
    "workflow_description": "brief description of actions",
    "confidence": "low/medium/high"
}
"""

def verify_bulk_checkin(traj, env_info, task_info):
    """
    Verify that the group was checked in correctly using existing records.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_visitors = set(metadata.get('visitors', []))

    # 1. Load basic file-based results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            file_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Check Database Modification (Anti-gaming / Sanity check)
    if file_result.get('db_modified', False):
        score += 10
        feedback_parts.append("Database updated")
    else:
        feedback_parts.append("Warning: Database not modified")

    # 3. VLM Final State Verification (CRITICAL)
    final_screenshot = get_final_screenshot(traj)
    if not final_screenshot:
        return {"passed": False, "score": score, "feedback": "No final screenshot available"}

    vlm_final = query_vlm(prompt=VLM_FINAL_STATE_PROMPT, image=final_screenshot)
    
    if not vlm_final.get("success"):
        return {"passed": False, "score": score, "feedback": f"VLM verification failed: {vlm_final.get('error')}"}
    
    final_parsed = vlm_final.get("parsed", {})
    
    # Score Final State
    found_names = set(final_parsed.get("names_found", []))
    # Normalize for comparison
    found_names_norm = {n.lower() for n in found_names}
    expected_norm = {n.lower() for n in expected_visitors}
    
    matches = len(found_names_norm.intersection(expected_norm))
    
    if final_parsed.get("is_visitor_list"):
        score += 10
    
    if matches == 3:
        score += 40
        feedback_parts.append("All 3 visitors found in active list")
    elif matches > 0:
        score += (matches * 10)
        feedback_parts.append(f"Found {matches}/3 visitors in active list")
    else:
        feedback_parts.append("No expected visitors found in active list")

    if final_parsed.get("status_is_signed_in"):
        score += 10
        feedback_parts.append("Status confirmed as Signed In")

    # 4. VLM Trajectory Verification (Process Check)
    # Sample frames to check if they used existing records
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_traj = query_vlm(prompt=VLM_TRAJECTORY_PROMPT, images=frames)
        traj_parsed = vlm_traj.get("parsed", {}) if vlm_traj.get("success") else {}
        
        if traj_parsed.get("used_existing_records"):
            score += 30
            feedback_parts.append("Correctly used existing records")
        elif traj_parsed.get("created_new_records"):
            score -= 20  # Penalty for creating new records instead of checking in
            feedback_parts.append("Incorrectly created new records (duplicates)")
        else:
            # Neutral if unclear
            pass

    # Final Pass Determination
    # Must have found all 3 visitors AND database modified
    passed = (matches == 3) and file_result.get('db_modified', False) and (score >= 70)

    return {
        "passed": passed,
        "score": min(100, max(0, score)),
        "feedback": " | ".join(feedback_parts),
        "details": {
            "vlm_final": final_parsed,
            "db_modified": file_result.get('db_modified')
        }
    }