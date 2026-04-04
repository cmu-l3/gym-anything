#!/usr/bin/env python3
"""
Verifier for screen_surgical_meds_imatinib task.
"""

import json
import logging
import os
import tempfile
import re
from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_surgical_screen(traj, env_info, task_info):
    """
    Verifies that the agent checked Imatinib against Fentanyl, Midazolam, and Ondansetron
    and created a correct report file.
    
    Scoring:
    - File created during task: 10 pts
    - Report content verification (drugs & colors): 60 pts
    - VLM Trajectory verification (navigation): 30 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # --- Step 1: File Verification ---
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Pull result JSON from Android device
        copy_from_env("/sdcard/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    file_exists = result.get("file_exists", False)
    created_during_task = result.get("created_during_task", False)
    content = result.get("file_content", "")
    
    if file_exists and created_during_task:
        score += 10
        feedback_parts.append("Report file created successfully.")
    elif file_exists:
        score += 5
        feedback_parts.append("Report file exists but timestamp check failed.")
    else:
        feedback_parts.append("Report file not found.")

    # --- Step 2: Content Analysis ---
    # Expected format:
    # Cancer Drug: Imatinib
    # Fentanyl: [Color]
    # Midazolam: [Color]
    # Ondansetron: [Color]
    # Overall Risk: [High/Low]
    
    drugs_found = 0
    colors_valid = 0
    risk_logic_correct = False
    
    if content:
        lines = content.split('\n')
        
        # Check Drugs
        if re.search(r"Imatinib", content, re.IGNORECASE):
            drugs_found += 1
        if re.search(r"Fentanyl", content, re.IGNORECASE):
            drugs_found += 1
        if re.search(r"Midazolam", content, re.IGNORECASE):
            drugs_found += 1
        if re.search(r"Ondansetron", content, re.IGNORECASE):
            drugs_found += 1
            
        # Check Colors (Red, Orange, Yellow, Green, Grey)
        valid_colors = ["Red", "Orange", "Yellow", "Green", "Grey"]
        found_colors = re.findall(r"(Red|Orange|Yellow|Green|Grey)", content, re.IGNORECASE)
        
        # We expect at least 3 color entries (one per co-medication)
        if len(found_colors) >= 3:
            colors_valid = 30 # Full points for finding colors for all 3
        elif len(found_colors) > 0:
            colors_valid = 10 * len(found_colors)
            
        # Check Risk Logic
        has_high_risk_color = any(c.lower() in ["red", "orange"] for c in found_colors)
        reported_risk = re.search(r"Overall Risk:\s*(HIGH|LOW)", content, re.IGNORECASE)
        
        if reported_risk:
            risk_val = reported_risk.group(1).upper()
            if has_high_risk_color and risk_val == "HIGH":
                risk_logic_correct = True
            elif not has_high_risk_color and risk_val == "LOW":
                risk_logic_correct = True
                
        # Calculate content score
        # Drugs: Max 15 pts (approx 3.75 per drug)
        score += int(drugs_found * 3.75)
        
        # Colors: Max 30 pts
        score += colors_valid
        
        # Logic: Max 15 pts
        if risk_logic_correct:
            score += 15
            
        if drugs_found == 4:
            feedback_parts.append("All drugs identified correctly.")
        else:
            feedback_parts.append(f"Found {drugs_found}/4 drug names.")
            
    # --- Step 3: VLM Trajectory Verification ---
    # We want to see if the agent navigated to the specific categories/drugs
    
    from gym_anything.vlm import query_vlm
    
    # Sample 8 frames to cover the workflow
    frames = sample_trajectory_frames(traj, n=8)
    
    prompt = """
    You are verifying an agent's workflow in the 'Liverpool Cancer iChart' app.
    The agent should have screened 'Imatinib' against three other drugs: 'Fentanyl', 'Midazolam', and 'Ondansetron'.
    
    Look at the sequence of screenshots.
    1. Did the agent select 'Imatinib'?
    2. Did the agent navigate to 'Analgesics' (for Fentanyl)?
    3. Did the agent navigate to 'Anxiolytics' or 'Hypnotics' (for Midazolam)?
    4. Did the agent navigate to 'Antiemetics' (for Ondansetron)?
    5. Did you see interaction result screens (Traffic light colors)?
    
    Return JSON:
    {
      "imatinib_selected": true,
      "analgesics_visited": true,
      "anxiolytics_visited": true,
      "antiemetics_visited": true,
      "results_seen": true
    }
    """
    
    try:
        vlm_result = query_vlm(images=frames, prompt=prompt)
        parsed = vlm_result.get('parsed', {})
        
        vlm_score = 0
        if parsed.get('imatinib_selected'): vlm_score += 5
        if parsed.get('analgesics_visited'): vlm_score += 5
        if parsed.get('anxiolytics_visited'): vlm_score += 5
        if parsed.get('antiemetics_visited'): vlm_score += 5
        if parsed.get('results_seen'): vlm_score += 10
        
        score += vlm_score
        feedback_parts.append(f"VLM Verification Score: {vlm_score}/30")
        
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        feedback_parts.append("VLM check failed (skipped).")
        # Fallback: if text file is perfect, give partial trust credit
        if score >= 60:
            score += 15

    return {
        "passed": score >= 75,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }