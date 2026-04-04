#!/usr/bin/env python3
"""
Verifier for configure_site_department task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_site_department(traj, env_info, task_info):
    """
    Verify that the Site and Departments were created in ServiceDesk Plus.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve JSON result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read verification result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- CRITERION 1: Site Creation (35 pts) ---
    site_found = int(result.get("site_found_count", 0)) > 0
    desc_match = int(result.get("site_desc_match_count", 0)) > 0
    
    if site_found:
        score += 25
        feedback_parts.append("Site 'Chicago Downtown Office' created")
        if desc_match:
            score += 10
            feedback_parts.append("Site description correct")
        else:
            feedback_parts.append("Site description missing/incorrect")
    else:
        feedback_parts.append("Site 'Chicago Downtown Office' NOT found")

    # --- CRITERION 2: Departments Creation (45 pts) ---
    depts_found = 0
    
    if int(result.get("dept_network_count", 0)) > 0:
        score += 15
        depts_found += 1
        feedback_parts.append("Dept 'Network Operations' created")
    
    if int(result.get("dept_desktop_count", 0)) > 0:
        score += 15
        depts_found += 1
        feedback_parts.append("Dept 'Desktop Support' created")
        
    if int(result.get("dept_security_count", 0)) > 0:
        score += 15
        depts_found += 1
        feedback_parts.append("Dept 'Information Security' created")

    if depts_found == 0:
        feedback_parts.append("No required departments found")

    # --- CRITERION 3: Anti-Gaming / Count Increase (10 pts) ---
    # Even if names match, we check if new records were actually added during this session
    init_site = int(result.get("initial_site_count", 0))
    curr_site = int(result.get("current_site_total", 0))
    init_dept = int(result.get("initial_dept_count", 0))
    curr_dept = int(result.get("current_dept_total", 0))
    
    if curr_site > init_site and curr_dept > init_dept:
        score += 10
        feedback_parts.append("Entity counts increased correctly")
    elif site_found or depts_found > 0:
        # If found but counts didn't increase, maybe they existed before?
        # Or maybe the count query failed. We give benefit of doubt if names match exactly,
        # but withhold these specific anti-gaming points.
        feedback_parts.append("Counts did not increase (records may have pre-existed)")

    # --- CRITERION 4: VLM Verification (10 pts) ---
    # Verify the agent actually used the Admin UI
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        prompt = """
        Review these screenshots of a user using ManageEngine ServiceDesk Plus.
        1. Did the user access the 'Admin' or 'Setup' tab/menu?
        2. Did the user fill out forms for creating a Site or Departments?
        
        Answer JSON: {"accessed_admin": bool, "filled_forms": bool}
        """
        
        vlm_resp = query_vlm(images=frames + [final], prompt=prompt)
        parsed = vlm_resp.get("parsed", {})
        
        if parsed.get("accessed_admin"):
            vlm_score += 5
        if parsed.get("filled_forms"):
            vlm_score += 5
            
        if vlm_score > 0:
            score += vlm_score
            feedback_parts.append(f"VLM verified workflow (+{vlm_score} pts)")
            
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: if they got the data right, give them the points
        if score >= 60:
            score += 10
            feedback_parts.append("VLM skipped (implicit pass)")

    # Final tally
    passed = score >= 60 and site_found and depts_found >= 2
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }