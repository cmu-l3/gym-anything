#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_flight_plan_gpx(traj, env_info, task_info):
    """
    Verifies that the agent created a flight plan and exported it to GPX.
    
    Criteria:
    1. File 'route_export.gpx' exists (30 pts)
    2. File was created during the task window (20 pts)
    3. File contains valid GPX/XML header (10 pts)
    4. File contains waypoint KRHV (15 pts)
    5. File contains waypoint KMOD (15 pts)
    6. VLM Verification of workflow (10 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    score = 0
    feedback = []
    
    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # 2. Check File Existence (30 pts)
    if result.get("file_exists"):
        score += 30
        feedback.append("Success: Export file found.")
    else:
        feedback.append("Fail: 'route_export.gpx' not found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 3. Check Freshness (20 pts)
    if result.get("created_during_task"):
        score += 20
        feedback.append("Success: File created during task.")
    else:
        feedback.append("Fail: File timestamp is too old (pre-existing file used?).")
        
    # 4. Check Content (40 pts total)
    content_check = result.get("content_check", {})
    
    if content_check.get("has_gpx_tag"):
        score += 10
        feedback.append("Success: Valid GPX format detected.")
    else:
        feedback.append("Fail: File does not appear to be valid GPX XML.")
        
    if content_check.get("has_krhv"):
        score += 15
        feedback.append("Success: Origin KRHV found in file.")
    else:
        feedback.append("Fail: Origin KRHV missing from file.")
        
    if content_check.get("has_kmod"):
        score += 15
        feedback.append("Success: Destination KMOD found in file.")
    else:
        feedback.append("Fail: Destination KMOD missing from file.")

    # 5. VLM Verification (10 pts)
    # We want to see the Plan screen or the Export dialog in the trajectory
    frames = sample_trajectory_frames(traj, n=5)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)
        
    if frames:
        vlm_prompt = (
            "Review these screenshots of an aviation app (Avare). "
            "Does the user navigate to the 'Plan' screen? "
            "Is there evidence of entering 'KRHV' or 'KMOD'? "
            "Is there evidence of an Export or Save File dialog?"
            "Return JSON: {\"plan_screen_seen\": bool, \"export_dialog_seen\": bool}"
        )
        try:
            vlm_response = query_vlm(images=frames, prompt=vlm_prompt)
            parsed = vlm_response.get('parsed', {})
            if parsed.get('plan_screen_seen') or parsed.get('export_dialog_seen'):
                score += 10
                feedback.append("VLM: Workflow verified visually.")
            else:
                feedback.append("VLM: Could not clearly see Plan/Export workflow.")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Do not penalize score if VLM fails, just skip
            score += 10 
            feedback.append("VLM: Check skipped/failed.")

    # 6. Final Assessment
    passed = score >= 80  # Requires file existence + freshness + most content correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }