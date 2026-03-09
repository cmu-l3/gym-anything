#!/usr/bin/env python3
"""
Verifier for Submarine Buoyancy Pilot task.

Verification Strategy:
1. File Verification (40%):
   - Check existence and timestamps of submarine_depth.png, submarine_surface.png, and captains_log.txt.
   - Files must be created during the task window.
   
2. Content Verification (20%):
   - Check captains_log.txt for physics keywords (ballast, density, etc.).
   
3. Visual Verification (40%):
   - VLM analysis of TRAJECTORY to confirm the submarine activity was played.
   - VLM analysis of the AGENT'S SCREENSHOTS to confirm they show correct states (bottom vs surface).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_submarine_pilot(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    required_keywords = metadata.get('required_keywords', ["ballast", "density"])

    # 1. Load Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []
    
    # =========================================================
    # CRITERION 1: File Existence & Timestamps (30 pts)
    # =========================================================
    files_ok = 0
    
    # Check Depth Screenshot
    depth_info = result.get("depth_screenshot", {})
    if depth_info.get("exists") and depth_info.get("created_during_task") and depth_info.get("size", 0) > 5000:
        score += 10
        files_ok += 1
        feedback.append("Depth screenshot created.")
    else:
        feedback.append("Missing or invalid depth screenshot.")

    # Check Surface Screenshot
    surf_info = result.get("surface_screenshot", {})
    if surf_info.get("exists") and surf_info.get("created_during_task") and surf_info.get("size", 0) > 5000:
        score += 10
        files_ok += 1
        feedback.append("Surface screenshot created.")
    else:
        feedback.append("Missing or invalid surface screenshot.")

    # Check Log File Existence
    log_info = result.get("log_file", {})
    if log_info.get("exists") and log_info.get("created_during_task"):
        score += 10
        files_ok += 1
        feedback.append("Log file created.")
    else:
        feedback.append("Missing log file.")

    # =========================================================
    # CRITERION 2: Log Content (20 pts)
    # =========================================================
    log_content = result.get("log_content_preview", "").lower()
    if log_info.get("exists") and len(log_content) > 20:
        found_keywords = [kw for kw in required_keywords if kw in log_content]
        if len(found_keywords) >= 2:
            score += 20
            feedback.append(f"Log content good (keywords: {', '.join(found_keywords)}).")
        elif len(found_keywords) == 1:
            score += 10
            feedback.append(f"Log content partial (keyword: {found_keywords[0]}).")
        else:
            feedback.append("Log file missing physics keywords.")
    
    # =========================================================
    # CRITERION 3: VLM Trajectory Verification (30 pts)
    # =========================================================
    # Verify the agent actually played the game
    frames = sample_trajectory_frames(traj, n=4)
    
    traj_prompt = """
    Analyze these screenshots of GCompris.
    1. Is the 'Submarine' activity visible (submarine in water, dashboard with valves/levers)?
    2. Does the submarine change depth (go down or up) between frames?
    
    Return JSON:
    {
        "submarine_activity_visible": true/false,
        "depth_change_observed": true/false
    }
    """
    
    vlm_traj = query_vlm(images=frames, prompt=traj_prompt)
    traj_data = vlm_traj.get("parsed", {})
    
    if traj_data.get("submarine_activity_visible"):
        score += 15
        feedback.append("Submarine activity detected in trajectory.")
        if traj_data.get("depth_change_observed"):
            score += 15
            feedback.append("Submarine movement observed.")
        else:
            feedback.append("No depth change observed in trajectory.")
    else:
        feedback.append("Submarine activity NOT detected in trajectory.")

    # =========================================================
    # CRITERION 4: VLM Evidence Verification (20 pts)
    # =========================================================
    # Check the actual screenshots the agent took (requires copying them out)
    evidence_score = 0
    
    # Helper to VLM a specific file from env
    def check_evidence_file(remote_path, prompt):
        if not remote_path: return False
        temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env(remote_path, temp_img.name)
            res = query_vlm(image=temp_img.name, prompt=prompt)
            return res.get("parsed", {}).get("match", False)
        except:
            return False
        finally:
            if os.path.exists(temp_img.name): os.unlink(temp_img.name)

    # Verify Depth Image
    if depth_info.get("exists"):
        depth_prompt = "Is the submarine near the BOTTOM of the ocean floor? Return JSON: {'match': true/false}"
        if check_evidence_file(depth_info.get("path"), depth_prompt):
            evidence_score += 10
            feedback.append("Depth screenshot verified visually.")
    
    # Verify Surface Image
    if surf_info.get("exists"):
        surf_prompt = "Is the submarine near the SURFACE of the water (top of screen)? Return JSON: {'match': true/false}"
        if check_evidence_file(surf_info.get("path"), surf_prompt):
            evidence_score += 10
            feedback.append("Surface screenshot verified visually.")

    score += evidence_score

    # Final Pass Calculation
    # Must have at least created the files and played the game
    passed = (score >= 70) and (files_ok == 3)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }