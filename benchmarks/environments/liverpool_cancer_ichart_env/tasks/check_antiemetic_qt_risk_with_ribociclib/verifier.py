#!/usr/bin/env python3
"""
Verifier for check_antiemetic_qt_risk_with_ribociclib task.

Criteria:
1. Result file exists and was created during the task.
2. Result file contains correct drug names (Ribociclib, Ondansetron).
3. Result file contains correct severity color (Red or Orange).
4. VLM verifies the agent actually navigated the app and saw the result.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_check_antiemetic_qt_risk(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_colors = metadata.get('expected_colors', ["red", "orange"])

    # 1. Retrieve Programmatic Result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result file: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task result data."}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- Programmatic Checks (50 points) ---

    # Check 1: File Existence & Timestamp (10 pts)
    file_exists = result_data.get("file_exists", False)
    file_mtime = int(result_data.get("file_mtime", 0))
    task_start = int(result_data.get("task_start_time", 0))

    if file_exists:
        if file_mtime >= task_start:
            score += 10
            feedback_parts.append("Result file created successfully.")
        else:
            feedback_parts.append("Result file exists but has old timestamp (pre-task?).")
    else:
        feedback_parts.append("Result file not found.")

    # Check 2: Content Validation (40 pts)
    # We allow case-insensitive matching
    l1 = result_data.get("line1", "").strip().lower()
    l2 = result_data.get("line2", "").strip().lower()
    l3 = result_data.get("line3", "").strip().lower()

    if "ribociclib" in l1:
        score += 10
    else:
        feedback_parts.append(f"Line 1 incorrect (Expected Ribociclib): {l1}")

    if "ondansetron" in l2:
        score += 10
    else:
        feedback_parts.append(f"Line 2 incorrect (Expected Ondansetron): {l2}")

    # Check color
    if l3 in expected_colors:
        score += 20
        feedback_parts.append(f"Correct interaction color reported: {l3}")
    else:
        # Check if they wrote valid colors but wrong one, or just nonsense
        valid_colors = ["red", "orange", "yellow", "green", "grey", "gray"]
        if l3 in valid_colors:
            feedback_parts.append(f"Wrong interaction color reported: {l3} (Expected Red/Orange)")
        else:
            feedback_parts.append(f"Invalid color format: {l3}")

    programmatic_score = score
    
    # --- VLM Checks (50 points) ---
    
    frames = sample_trajectory_frames(traj, n=6)
    
    vlm_prompt = """
    Analyze these screenshots of an agent using the Liverpool Cancer iChart app.
    
    The goal was to check the interaction between 'Ribociclib' and 'Ondansetron'.
    
    Please evaluate the following:
    1. Did the agent open the app?
    2. Did the agent select 'Ribociclib' in the cancer drug list?
    3. Did the agent select 'Ondansetron' (or find it in Anti-emetics) in the co-medication list?
    4. Is the final interaction result screen visible (showing traffic light colors)?
    5. Does the result screen show a Red or Orange alert?
    
    Return JSON:
    {
        "app_opened": boolean,
        "ribociclib_selected": boolean,
        "ondansetron_selected": boolean,
        "result_screen_visible": boolean,
        "observed_color": "string (red/orange/yellow/green/grey/none)",
        "confidence": "low/medium/high"
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    vlm_data = vlm_result.get("parsed", {})
    
    vlm_score = 0
    if vlm_data.get("app_opened"): vlm_score += 10
    if vlm_data.get("ribociclib_selected"): vlm_score += 10
    if vlm_data.get("ondansetron_selected"): vlm_score += 10
    if vlm_data.get("result_screen_visible"): vlm_score += 10
    
    obs_color = vlm_data.get("observed_color", "").lower()
    if obs_color in ["red", "orange"]:
        vlm_score += 10
    
    score += vlm_score
    
    # --- Final Decision ---
    
    # Must have the file correctly written AND visual evidence of the work
    passed = (programmatic_score >= 40) and (vlm_score >= 30)
    
    if passed:
        feedback = "Success: Interaction correctly identified and recorded."
    else:
        feedback = f"Failed. Programmatic check: {programmatic_score}/50. VLM check: {vlm_score}/50. Issues: {'; '.join(feedback_parts)}"

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }