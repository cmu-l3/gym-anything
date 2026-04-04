#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_select_safer_hiv_therapy(traj, env_info, task_info):
    """
    Verifies the HIV-Crizotinib interaction task.
    
    Criteria:
    1. Result file created during task.
    2. Correct identification of Safer drug (Raltegravir) and Risky drug (Ritonavir).
    3. Correct traffic light colors identified (Green vs Red/Amber).
    4. VLM Trajectory: Confirms agent actually looked up both drugs in the app.
    """
    
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    
    # 1. Retrieve and Parse JSON Result from Device
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result file: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Evaluate File Content (80 Points Total)
    score = 0
    feedback = []
    
    file_exists = result_data.get("file_exists", False)
    start_time = result_data.get("start_time", 0)
    file_timestamp = result_data.get("file_timestamp", 0)
    
    # Check Anti-Gaming (File created *during* task)
    if not file_exists:
        feedback.append("Result file not found.")
    elif file_timestamp < start_time:
        feedback.append("File timestamp predates task start (anti-gaming check failed).")
    else:
        score += 10
        feedback.append("Result file created successfully.")
        
        # Parse Content
        l1 = result_data.get("line1", "").strip().lower() # Safer Name
        l2 = result_data.get("line2", "").strip().lower() # Safer Color
        l3 = result_data.get("line3", "").strip().lower() # Risky Name
        l4 = result_data.get("line4", "").strip().lower() # Risky Color
        
        # Check Safer Drug (Raltegravir)
        if "raltegravir" in l1:
            score += 30
            feedback.append("Correctly identified Raltegravir as the safer drug.")
            
            # Check Safer Color (Green or Yellow)
            if "green" in l2 or "yellow" in l2:
                score += 15
                feedback.append("Correct color for Raltegravir.")
            else:
                feedback.append(f"Incorrect color for Raltegravir: {l2}")
        else:
            feedback.append(f"Incorrect safer drug identified: {l1}")

        # Check Risky Drug (Ritonavir)
        if "ritonavir" in l3:
            score += 10
            feedback.append("Correctly identified Ritonavir as the risky drug.")
            
            # Check Risky Color (Red or Amber/Orange)
            if "red" in l4 or "amber" in l4 or "orange" in l4:
                score += 15
                feedback.append("Correct color for Ritonavir.")
            else:
                feedback.append(f"Incorrect color for Ritonavir: {l4}")
        else:
            feedback.append(f"Incorrect risky drug identified: {l3}")

    # 3. VLM Trajectory Verification (20 Points)
    # We want to see evidence that the agent actually looked up these drugs.
    
    frames = sample_trajectory_frames(traj, n=6)
    
    vlm_prompt = """
    I will show you a sequence of screenshots from an Android medical app.
    The user is supposed to be checking drug interactions for 'Crizotinib'.
    
    Please answer the following in JSON format:
    1. "seen_crizotinib": boolean - Is 'Crizotinib' visible as the selected cancer drug?
    2. "seen_ritonavir": boolean - Is 'Ritonavir' visible in the co-medication list or interaction detail?
    3. "seen_raltegravir": boolean - Is 'Raltegravir' visible in the co-medication list or interaction detail?
    4. "traffic_lights_visible": boolean - Are the colored traffic light icons visible?
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    vlm_score = 0
    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        if parsed.get("seen_crizotinib"):
            vlm_score += 5
        if parsed.get("seen_ritonavir"):
            vlm_score += 5
        if parsed.get("seen_raltegravir"):
            vlm_score += 5
        if parsed.get("traffic_lights_visible"):
            vlm_score += 5
            
        feedback.append(f"VLM Verification: {vlm_score}/20 points (Crizotinib: {parsed.get('seen_crizotinib')}, Ritonavir: {parsed.get('seen_ritonavir')}, Raltegravir: {parsed.get('seen_raltegravir')})")
    else:
        feedback.append("VLM Verification failed to run.")
    
    score += vlm_score

    # Final Result
    passed = (score >= 70) and ("raltegravir" in result_data.get("line1", "").strip().lower())
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }