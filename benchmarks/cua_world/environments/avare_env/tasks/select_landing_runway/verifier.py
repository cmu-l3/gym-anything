#!/usr/bin/env python3
"""
Verifier for select_landing_runway task.

Checks:
1. Did the agent create the report file during the task?
2. Is the selected runway correct for the wind conditions?
3. Is the runway length accurate?
4. VLM: Did the agent actually view the airport info/runway data?
"""

import json
import tempfile
import os
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_select_landing_runway(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # --- Retrieve Result JSON ---
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: File Existence & Anti-Gaming (20 pts) ---
    file_exists = result.get("file_exists", False)
    created_during = result.get("file_created_during_task", False)
    
    if file_exists:
        if created_during:
            score += 20
            feedback_parts.append("Report file created successfully.")
        else:
            feedback_parts.append("Report file exists but is old (anti-gaming fail).")
            return {"passed": False, "score": 0, "feedback": "File timestamp predates task start."}
    else:
        feedback_parts.append("Report file not found.")
        return {"passed": False, "score": 0, "feedback": "Report file /sdcard/runway_report.txt not found."}

    # --- Criterion 2: Correct Runway Selection (30 pts) ---
    # KOAK Wind 310 @ 12kt -> Best Rwy 30 (heading ~300)
    # Acceptable alternative: 28R/28L (heading ~280), but 30 is better aligned
    
    reported_runway = str(result.get("content_runway", "")).strip().upper()
    best_runway = metadata.get("best_runway", "30")
    alternatives = metadata.get("acceptable_alternatives", ["28R", "28L", "28"])
    
    # Normalize input (remove 'RWY', 'RUNWAY', etc)
    clean_runway = re.sub(r'[^0-9LR]', '', reported_runway)
    
    if clean_runway == best_runway:
        score += 30
        feedback_parts.append(f"Correct runway selected: {reported_runway}.")
    elif clean_runway in alternatives:
        score += 15
        feedback_parts.append(f"Acceptable runway selected ({reported_runway}), but Runway {best_runway} is better aligned to 310° wind.")
    else:
        feedback_parts.append(f"Incorrect runway selection: '{reported_runway}'. Expected {best_runway} for 310° wind.")

    # --- Criterion 3: Runway Length Accuracy (20 pts) ---
    # Rwy 30 is approx 10,520 ft. Rwy 28s are ~6,000 ft.
    # We check against the length of the *selected* runway if possible, 
    # but primarily against the correct one or the one they claimed.
    
    reported_length_str = str(result.get("content_length", "")).strip()
    # Extract numbers only
    length_match = re.search(r'\d+', reported_length_str)
    
    length_points = 0
    if length_match:
        reported_length = int(length_match.group())
        target_length = metadata.get("runway_30_length_approx", 10520)
        tolerance = metadata.get("length_tolerance", 500)
        
        # If they picked the wrong runway (e.g. 28), we should check against 28's length 
        # to give partial credit for data extraction even if decision was wrong.
        if "28" in clean_runway:
            target_length = 6213 # Approx for 28R
        
        if abs(reported_length - target_length) <= tolerance:
            length_points = 20
            feedback_parts.append(f"Runway length correct ({reported_length}).")
        else:
            feedback_parts.append(f"Runway length {reported_length} is incorrect (expected ~{target_length}).")
    else:
        feedback_parts.append("Could not parse runway length number.")
        
    score += length_points

    # --- Criterion 4: VLM Process Verification (30 pts) ---
    # Did they verify the airport info?
    
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=5)
        
        prompt = """
        You are verifying an agent's workflow in the Avare aviation app.
        The goal was to look up airport information for KOAK (Oakland).
        
        Look at the sequence of images.
        1. Does the agent search for "KOAK" or "Oakland"?
        2. Does the agent view a screen showing "Airport Info", "AFD", or a list of runways (headings/lengths)?
        
        Answer JSON: {"searched_airport": bool, "viewed_info": bool, "explanation": str}
        """
        
        vlm_resp = query_vlm(images=frames, prompt=prompt)
        
        vlm_score = 0
        if vlm_resp.get("success"):
            parsed = vlm_resp.get("parsed", {})
            if parsed.get("searched_airport", False):
                vlm_score += 10
            if parsed.get("viewed_info", False):
                vlm_score += 20
                feedback_parts.append("VLM confirmed airport info access.")
            else:
                feedback_parts.append("VLM did not see Airport Info/Runway details page.")
        
        score += vlm_score
    else:
        # Fallback if VLM unavailable, grant points if data correct
        if score >= 60: 
            score += 30
            feedback_parts.append("VLM skipped, assuming process valid based on correct data.")

    # --- Final Result ---
    # Pass threshold: 60 points (Requires file + reasonable runway + some correct data/VLM)
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " ".join(feedback_parts)
    }