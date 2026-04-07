#!/usr/bin/env python3
"""
Verifier for Bulk User Import Task in Rocket.Chat.

Verifies:
1. Users exist in the system (API check).
2. User details (Name, Email) match the CSV source.
3. Users were created *during* the task (anti-gaming).
4. VLM verifies the Import UI was used (optional/secondary).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bulk_user_import(traj, env_info, task_info):
    """
    Verify the bulk user import task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected data from metadata
    expected_users = task_info.get('metadata', {}).get('expected_users', [])
    if not expected_users:
        return {"passed": False, "score": 0, "feedback": "Task metadata missing expected users"}

    # Retrieve result JSON
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
    
    # --- Criteria 1: User Existence & Accuracy (80 points total) ---
    user_results = result.get('user_results', [])
    users_passed = 0
    total_users = len(expected_users)
    
    # Create lookup for results
    result_map = {u.get('username'): u for u in user_results}

    for expected in expected_users:
        username = expected['username']
        res = result_map.get(username)
        
        if not res or not res.get('found'):
            feedback_parts.append(f"User {username}: Not found.")
            continue

        # Points for existence (8 pts per user)
        p_score = 8
        details_correct = True

        # Check Name (4 pts)
        if res.get('actual_name') == expected['name']:
            p_score += 4
        else:
            feedback_parts.append(f"User {username}: Name mismatch (Expected '{expected['name']}', Got '{res.get('actual_name')}')")
            details_correct = False

        # Check Email (4 pts)
        if res.get('actual_email') == expected['email']:
            p_score += 4
        else:
            feedback_parts.append(f"User {username}: Email mismatch (Expected '{expected['email']}', Got '{res.get('actual_email')}')")
            details_correct = False
            
        # Check Creation Time (Anti-gaming check)
        if not res.get('created_during_task'):
            feedback_parts.append(f"User {username}: Was not created during this task session.")
            p_score = 0 # Invalidate this user if pre-existing
        
        score += p_score
        if p_score == 16: # Full points for this user
            users_passed += 1

    feedback_parts.append(f"Correctly imported {users_passed}/{total_users} users.")

    # --- Criteria 2: VLM Trajectory Check (20 points) ---
    # We want to verify they used the "Import" UI and didn't just script an API call or add manually
    frames = sample_trajectory_frames(traj, n=8)
    vlm_prompt = """
    You are verifying a Rocket.Chat bulk import task.
    Look at these screenshots of the user's workflow.
    
    Did the user:
    1. Access the "Administration" panel?
    2. Click on "Import" or "CSV"?
    3. Show the "Import" screen with mapping options?
    
    Answer JSON: {"import_ui_seen": true/false, "confidence": "high/medium/low"}
    """
    
    vlm_score = 0
    try:
        vlm_resp = query_vlm(images=frames, prompt=vlm_prompt)
        if vlm_resp.get("success"):
            parsed = vlm_resp.get("parsed", {})
            if parsed.get("import_ui_seen"):
                vlm_score = 20
                feedback_parts.append("VLM Verification: Import UI usage detected.")
            else:
                feedback_parts.append("VLM Verification: Import UI NOT detected (manual entry?).")
        else:
            # Fallback if VLM fails: If API data is perfect, give benefit of doubt
            if users_passed == total_users:
                vlm_score = 20
                feedback_parts.append("VLM skipped, assuming success based on data accuracy.")
    except Exception:
        # Ignore VLM errors
        pass
        
    score += vlm_score

    # Final Verdict
    # Pass if at least 4/5 users are perfect AND score >= 80
    passed = (score >= 80) and (users_passed >= 4)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }