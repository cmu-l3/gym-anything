#!/usr/bin/env python3
"""
Verifier for verify_vaccine_safety_profile_rituximab@1.
Checks if the agent correctly identified the interaction risks for Live vs Inactivated vaccines.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rituximab_vaccine_safety(traj, env_info, task_info):
    """
    Verifies the Rituximab vaccine safety task.
    
    Scoring Criteria:
    1. Report file exists and was created during task (20 pts)
    2. Live Vaccine interaction correctly identified (Red/Orange) (20 pts)
    3. Inactivated Vaccine interaction correctly identified (Yellow/Green) (20 pts)
    4. Safety conclusion is correct (NO for live vaccines) (20 pts)
    5. VLM Trajectory: Agent actually navigated to specific vaccine pages (20 pts)
    """
    
    # 1. Setup and File Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    metadata = task_info.get('metadata', {})
    score = 0
    feedback_parts = []
    
    # Create temp files for retrieval
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    try:
        # Fetch JSON result
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
            
        # Fetch Report File if it exists
        report_content = ""
        if result_data.get("file_exists", False):
            try:
                copy_from_env(metadata.get("output_file_path", "/sdcard/rituximab_vaccine_report.txt"), temp_report.name)
                with open(temp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
                    report_content = f.read()
            except Exception as e:
                logger.warning(f"Failed to read report file: {e}")
                
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task data: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name): os.unlink(temp_json.name)
        if os.path.exists(temp_report.name): os.unlink(temp_report.name)

    # 2. File Existence & Anti-Gaming Check (20 pts)
    if result_data.get("file_exists") and result_data.get("file_created_during_task"):
        score += 20
        feedback_parts.append("Report file created successfully.")
    elif result_data.get("file_exists"):
        score += 10
        feedback_parts.append("Report file exists but timestamp suggests pre-existence.")
    else:
        feedback_parts.append("Report file NOT found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 3. Content Analysis (60 pts total)
    lines = report_content.upper().split('\n')
    
    # Check Live Vaccine Entry
    live_correct = False
    for line in lines:
        if "LIVE" in line and any(c in line for c in ["RED", "ORANGE"]):
            live_correct = True
            break
    
    if live_correct:
        score += 20
        feedback_parts.append("Live vaccine interaction correctly identified (High Risk).")
    else:
        feedback_parts.append("Failed to correctly identify Live vaccine interaction color.")

    # Check Inactivated Vaccine Entry
    inactivated_correct = False
    for line in lines:
        if "INACTIVATED" in line and any(c in line for c in ["YELLOW", "GREEN", "GREY"]):
            inactivated_correct = True
            break
            
    if inactivated_correct:
        score += 20
        feedback_parts.append("Inactivated vaccine interaction correctly identified (Low/Medium Risk).")
    else:
        feedback_parts.append("Failed to correctly identify Inactivated vaccine interaction color.")

    # Check Conclusion
    conclusion_correct = False
    for line in lines:
        if "SAFE" in line and "NO" in line:
            conclusion_correct = True
            break
            
    if conclusion_correct:
        score += 20
        feedback_parts.append("Safety conclusion correct (NO for live vaccines).")
    else:
        feedback_parts.append("Incorrect safety conclusion.")

    # 4. VLM Trajectory Verification (20 pts)
    # We check if the agent actually looked at the detailed interaction screens
    frames = sample_trajectory_frames(traj, n=6)
    
    vlm_prompt = """
    Analyze these screenshots of a medical app (Liverpool Cancer iChart).
    The user is supposed to check 'Rituximab' interactions with two types of vaccines.
    
    I need you to answer three questions with YES or NO:
    1. Is 'Rituximab' (or Rituxan) visible as the selected cancer drug in any frame?
    2. Is a screen visible showing 'Yellow Fever' or another Live Vaccine?
    3. Is a screen visible showing 'Influenza' or another Inactivated Vaccine?
    
    Return JSON: {"rituximab_selected": bool, "live_vaccine_viewed": bool, "inactivated_vaccine_viewed": bool}
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    vlm_data = vlm_result.get("parsed", {})
    
    vlm_score = 0
    if vlm_data.get("rituximab_selected"): vlm_score += 5
    if vlm_data.get("live_vaccine_viewed"): vlm_score += 7.5
    if vlm_data.get("inactivated_vaccine_viewed"): vlm_score += 7.5
    
    score += vlm_score
    if vlm_score < 10:
        feedback_parts.append("Warning: VLM could not verify navigation to specific vaccine pages.")
    else:
        feedback_parts.append("Visual verification confirmed correct navigation.")

    # 5. Final Decision
    passed = score >= 80 and conclusion_correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }