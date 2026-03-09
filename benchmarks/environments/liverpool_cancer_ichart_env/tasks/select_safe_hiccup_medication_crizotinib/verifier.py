#!/usr/bin/env python3
"""
Verifier for select_safe_hiccup_medication_crizotinib task.

Checks:
1. Output file /sdcard/hiccup_safety.txt exists and was created during task.
2. File content correctly identifies interactions:
   - Chlorpromazine: Red/Orange (QT risk)
   - Baclofen: Green/Grey (Safe)
3. Recommendation matches "Baclofen".
4. VLM verifies navigation to both Crizotinib and the specific co-medications.
"""

import json
import tempfile
import os
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hiccup_safety(traj, env_info, task_info):
    # 1. Setup and Environment Check
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_rec = metadata.get('expected_recommendation', 'Baclofen').lower()
    
    # 2. Load Result JSON from Container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 3. Initialize Scoring
    score = 0
    feedback_log = []
    
    # --- Criterion A: File Existence & Anti-Gaming (10 pts) ---
    if result_data.get('file_exists') and result_data.get('created_during_task'):
        score += 10
        feedback_log.append("Report file created successfully.")
    else:
        feedback_log.append("Report file missing or stale.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_log)}

    # --- Criterion B: Data Accuracy (40 pts) ---
    content = result_data.get('file_content', '').lower()
    
    # Parse file content
    # Expected format:
    # Medication 1: Chlorpromazine - [COLOR]
    # Medication 2: Baclofen - [COLOR]
    
    chlor_match = re.search(r'chlorpromazine\s*-\s*(\w+)', content)
    baclo_match = re.search(r'baclofen\s*-\s*(\w+)', content)
    
    data_points_correct = 0
    
    # Check Chlorpromazine (Should be Red/Orange)
    if chlor_match:
        color = chlor_match.group(1)
        if color in ['red', 'orange']:
            data_points_correct += 1
            feedback_log.append(f"Correctly identified Chlorpromazine risk ({color}).")
        else:
            feedback_log.append(f"Incorrect color for Chlorpromazine: {color} (Expected Red/Orange).")
    else:
        feedback_log.append("Chlorpromazine entry not found in file.")

    # Check Baclofen (Should be Green/Grey)
    if baclo_match:
        color = baclo_match.group(1)
        if color in ['green', 'grey', 'gray']:
            data_points_correct += 1
            feedback_log.append(f"Correctly identified Baclofen safety ({color}).")
        else:
            feedback_log.append(f"Incorrect color for Baclofen: {color} (Expected Green/Grey).")
    else:
        feedback_log.append("Baclofen entry not found in file.")

    score += (data_points_correct * 20)

    # --- Criterion C: Recommendation (20 pts) ---
    rec_match = re.search(r'recommendation:\s*(\w+)', content)
    if rec_match and expected_rec in rec_match.group(1):
        score += 20
        feedback_log.append("Correct recommendation made.")
    else:
        feedback_log.append("Incorrect or missing recommendation.")

    # --- Criterion D: VLM Trajectory Verification (30 pts) ---
    # We need to confirm the agent actually looked up the drugs and didn't just guess.
    
    frames = sample_trajectory_frames(traj, n=6)
    
    vlm_prompt = """
    You are verifying an agent's workflow in the Liverpool Cancer iChart app.
    The agent should have:
    1. Selected the cancer drug 'Crizotinib'.
    2. Viewed interactions for 'Chlorpromazine' (likely Red/Orange).
    3. Viewed interactions for 'Baclofen' (likely Green/Grey).
    
    Look at these screenshots. 
    - Can you see 'Crizotinib' selected?
    - Can you see 'Chlorpromazine' or 'Antipsychotics' category?
    - Can you see 'Baclofen' or 'Muscle Relaxants' category?
    
    Return JSON:
    {
        "crizotinib_seen": boolean,
        "chlorpromazine_seen": boolean,
        "baclofen_seen": boolean,
        "confidence": "low|medium|high"
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    if vlm_result and vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        vlm_score = 0
        if parsed.get('crizotinib_seen'): vlm_score += 10
        if parsed.get('chlorpromazine_seen'): vlm_score += 10
        if parsed.get('baclofen_seen'): vlm_score += 10
        
        score += vlm_score
        feedback_log.append(f"VLM verified navigation: {vlm_score}/30 pts.")
    else:
        # Fallback if VLM fails: give partial credit if data was correct, assuming they must have looked it up
        if data_points_correct == 2:
            score += 15
            feedback_log.append("VLM unavailable, partial credit for correct data.")
        else:
            feedback_log.append("VLM verification failed.")

    # Final Pass/Fail Calculation
    passed = score >= 70 and data_points_correct == 2
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_log)
    }