#!/usr/bin/env python3
"""
Verifier for compute_incubation_period task (Epi Info 7).

Verifies:
1. Result file existence and creation time.
2. Correct calculation of incubation statistics (N, Median, Mean).
3. Correct identification of pathogen (Norovirus).
4. VLM verification of Classic Analysis workflow (DEFINE, ASSIGN, MEANS usage).
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compute_incubation_period(traj, env_info, task_info):
    """
    Verify the Epi Info 7 incubation period task.
    """
    # 1. Setup and Copy Results
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy JSON result from export script
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_json.close()
    
    try:
        # Note: Windows path inside container
        copy_from_env("C:\\Users\\Docker\\AppData\\Local\\Temp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Extract Metrics
    metadata = task_info.get('metadata', {})
    score = 0
    feedback_parts = []

    output_exists = result.get('output_exists', False)
    created_during = result.get('file_created_during_task', False)
    content = result.get('content_preview', "")
    
    # 3. Score Criteria
    
    # Criterion 1: File Creation (10 pts)
    if output_exists and created_during:
        score += 10
        feedback_parts.append("Result file created successfully.")
    elif output_exists:
        score += 5
        feedback_parts.append("Result file exists but timestamp check failed.")
    else:
        return {"passed": False, "score": 0, "feedback": "No result file found."}

    # Parse content for numbers
    # Expected format usually: "N: 91, Median: 33, Mean: 34" etc.
    # We'll use regex to find numbers near keywords
    
    # Find N (Case Count)
    n_match = re.search(r'(?:N|Count|Cases|Number).*?(\d{2,3})', content, re.IGNORECASE)
    n_val = int(n_match.group(1)) if n_match else 0
    
    # Find Median
    median_match = re.search(r'(?:Median).*?(\d{1,3}(?:\.\d)?)', content, re.IGNORECASE)
    median_val = float(median_match.group(1)) if median_match else 0.0
    
    # Find Pathogen
    pathogen_found = result.get('pathogen_found', "")
    
    # Criterion 2: Case Count (N) (15 pts)
    expected_n_min = metadata.get('expected_n_min', 85)
    expected_n_max = metadata.get('expected_n_max', 91)
    if expected_n_min <= n_val <= expected_n_max:
        score += 15
        feedback_parts.append(f"Correct case count (N={n_val}).")
    else:
        feedback_parts.append(f"Case count mismatch (Found {n_val}, expected ~91).")

    # Criterion 3: Median Calculation (25 pts)
    expected_med_min = metadata.get('expected_median_min', 28.0)
    expected_med_max = metadata.get('expected_median_max', 40.0)
    if expected_med_min <= median_val <= expected_med_max:
        score += 25
        feedback_parts.append(f"Correct median incubation ({median_val}h).")
    else:
        feedback_parts.append(f"Median incubation incorrect or not found (Found {median_val}).")

    # Criterion 4: Pathogen Identification (20 pts)
    if "norovirus" in pathogen_found.lower():
        score += 20
        feedback_parts.append("Correct pathogen identified (Norovirus).")
    else:
        feedback_parts.append(f"Pathogen incorrect or not identified (Found '{pathogen_found}').")

    # Criterion 5: App Running (5 pts)
    if result.get('app_was_running', False):
        score += 5
    
    # Criterion 6: VLM Trajectory Verification (25 pts)
    # We verify if the agent actually used the Classic Analysis commands
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = """
        Analyze these screenshots of Epi Info 7 Classic Analysis software.
        Check for the following:
        1. Is the 'Analysis' module visible (command tree on left, output on right)?
        2. Are there commands like 'DEFINE', 'ASSIGN', 'MEANS', or 'FREQ' being used?
        3. Is there a command output window showing statistical results?
        
        Return JSON: {"analysis_visible": bool, "commands_used": bool, "stats_shown": bool}
        """
        
        vlm_res = query_vlm(prompt=vlm_prompt, images=frames)
        vlm_data = vlm_res.get('parsed', {}) if vlm_res.get('success') else {}
        
        vlm_score = 0
        if vlm_data.get('analysis_visible'): vlm_score += 10
        if vlm_data.get('commands_used') or vlm_data.get('stats_shown'): vlm_score += 15
        
        score += vlm_score
        if vlm_score > 0:
            feedback_parts.append("Visual verification passed.")
        else:
            feedback_parts.append("Visual verification failed (workflow not observed).")
    
    passed = score >= 60 and "norovirus" in pathogen_found.lower() and (expected_med_min <= median_val <= expected_med_max)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }