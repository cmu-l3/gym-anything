#!/usr/bin/env python3
"""
Verifier for add_company_reference_record task in Jolly Lobby Track.

Criteria:
1. "Aramark" string exists in the application database (40 pts)
2. "Philadelphia" string exists in the application database (20 pts)
3. Database file was modified during the task (10 pts)
4. VLM Trajectory confirms navigation to Lists and data entry (30 pts)
"""

import json
import tempfile
import os
import logging
import sys
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_company_reference_record(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result JSON from Container
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
    
    # 2. Database Verification (Primary Signal)
    record_found = result.get("record_name_found", False)
    city_found = result.get("record_city_found", False)
    db_modified = result.get("db_modified_during_task", False)
    
    if record_found:
        score += 40
        feedback_parts.append("Company 'Aramark' found in database")
    else:
        feedback_parts.append("Company 'Aramark' NOT found in database")

    if city_found:
        score += 20
        feedback_parts.append("City 'Philadelphia' found in database")
    
    if db_modified:
        score += 10
        feedback_parts.append("Database file modified during task")
    else:
        feedback_parts.append("Database file timestamp unchanged (Action may not have been saved)")

    # 3. VLM Trajectory Verification (Secondary Signal)
    # We check if the agent actually opened the "Lists" or "Reference Data" screen.
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)
    
    vlm_prompt = """
    Review the sequence of screenshots from the visitor management software.
    Answer the following questions:
    1. Did the user navigate to a list management, reference data, or settings screen?
    2. Did the user enter "Aramark" into a text field?
    3. Did the user enter "Philadelphia" into a text field?
    4. Did the user click a "Save", "OK", or "Add" button?
    
    Return JSON: {"navigated_to_lists": bool, "entered_company": bool, "entered_city": bool, "saved": bool}
    """
    
    vlm_score = 0
    try:
        vlm_resp = query_vlm(images=frames, prompt=vlm_prompt)
        parsed = vlm_resp.get("parsed", {})
        
        if parsed.get("navigated_to_lists"):
            vlm_score += 10
        if parsed.get("entered_company"):
            vlm_score += 10
        if parsed.get("saved"):
            vlm_score += 10
            
        score += vlm_score
        feedback_parts.append(f"VLM Verification Score: {vlm_score}/30")
        
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        feedback_parts.append("VLM verification failed to run")

    # 4. Final Assessment
    # Pass if record is in DB OR (VLM confirms entry AND save)
    # The database check is the gold standard.
    passed = (record_found and db_modified) or (score >= 70)
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }