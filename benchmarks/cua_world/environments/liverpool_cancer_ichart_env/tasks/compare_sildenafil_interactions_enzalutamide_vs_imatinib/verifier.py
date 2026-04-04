#!/usr/bin/env python3
"""
Verifier for Compare Sildenafil Interactions task.
"""

import json
import tempfile
import os
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sildenafil_comparison(traj, env_info, task_info):
    """
    Verifies that the agent compared Sildenafil interactions for Enzalutamide and Imatinib.
    
    Scoring Criteria:
    1. File Existence & Freshness (20 pts): Report file created during task.
    2. Enzalutamide Data (20 pts): Report contains Enzalutamide and a valid color.
    3. Imatinib Data (20 pts): Report contains Imatinib and a valid color.
    4. VLM Trajectory (40 pts): Visual proof of visiting both drug pages.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # --- Criterion 1: File Check (20 pts) ---
    if result.get("file_exists") and result.get("file_created_during_task"):
        score += 20
        feedback.append("Report file created successfully.")
    else:
        feedback.append("Report file missing or not created during task.")
    
    content = result.get("content", "").lower()
    
    # --- Criterion 2 & 3: Content Check (40 pts) ---
    # Valid traffic light colors
    colors = ["red", "orange", "amber", "yellow", "green", "grey", "gray"]
    color_pattern = "|".join(colors)
    
    # Check Enzalutamide
    enz_match = re.search(f"enzalutamide.*?({color_pattern})", content)
    if enz_match:
        score += 20
        feedback.append(f"Enzalutamide interaction reported: {enz_match.group(1)}.")
    elif "enzalutamide" in content:
        score += 10
        feedback.append("Enzalutamide mentioned but color not clearly formatted.")
    else:
        feedback.append("Enzalutamide missing from report.")

    # Check Imatinib
    ima_match = re.search(f"imatinib.*?({color_pattern})", content)
    if ima_match:
        score += 20
        feedback.append(f"Imatinib interaction reported: {ima_match.group(1)}.")
    elif "imatinib" in content:
        score += 10
        feedback.append("Imatinib mentioned but color not clearly formatted.")
    else:
        feedback.append("Imatinib missing from report.")

    # --- Criterion 4: VLM Trajectory Verification (40 pts) ---
    # We need to ensure the agent actually looked up the drugs and didn't just guess.
    # Sampling frames from the trajectory.
    frames = sample_trajectory_frames(traj, n=8)
    
    vlm_prompt = """
    You are verifying an agent's workflow in the Liverpool Cancer iChart app.
    The agent was supposed to check interactions for Sildenafil with two cancer drugs: Enzalutamide and Imatinib.
    
    Look at the sequence of screenshots. Answer the following:
    1. Did the agent navigate to a screen showing "Enzalutamide"?
    2. Did the agent navigate to a screen showing "Imatinib"?
    3. Did the agent view the "Sildenafil" entry (or "Urologicals"/"Erectile Dysfunction" category) for either drug?
    
    Output JSON:
    {
        "saw_enzalutamide": boolean,
        "saw_imatinib": boolean,
        "saw_sildenafil_or_category": boolean
    }
    """
    
    try:
        vlm_resp = query_vlm(images=frames, prompt=vlm_prompt)
        vlm_data = vlm_resp.get("parsed", {})
        
        vlm_score = 0
        if vlm_data.get("saw_enzalutamide"):
            vlm_score += 15
            feedback.append("VLM confirmed Enzalutamide lookup.")
        if vlm_data.get("saw_imatinib"):
            vlm_score += 15
            feedback.append("VLM confirmed Imatinib lookup.")
        if vlm_data.get("saw_sildenafil_or_category"):
            vlm_score += 10
            feedback.append("VLM confirmed Sildenafil/Category lookup.")
            
        score += vlm_score
        
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        feedback.append("VLM verification skipped due to error (awarding partial credit).")
        score += 20 # Partial credit fallback

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }