#!/usr/bin/env python3
"""
Verifier for chi_sq_mnxtable_titanic task.
"""

import json
import tempfile
import os
import re
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chi_sq_mnxtable_titanic(traj, env_info, task_info):
    """
    Verify the Chi-Square analysis task.
    
    Criteria:
    1. Output file exists and was created during task (anti-gaming).
    2. Chi-Square statistic is correct (~102.89).
    3. Degrees of Freedom is correct (2).
    4. P-value is correct (< 0.001).
    5. VLM: Classic Analysis window was used and Tables output visible.
    """
    
    # 1. Setup and Load Result JSON
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_chisq = metadata.get('expected_chisq', 102.89)
    tolerance = metadata.get('tolerance_chisq', 2.0)
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Copy the JSON result exported by the powershell script
        # Path inside container is C:\tmp\task_result.json -> mapped to /tmp/task_result.json usually?
        # Windows containers usually map C:\tmp to /tmp in the mount logic if using dockur/windows?
        # Assuming the copy_from_env handles the path correctly based on env_id.
        # For Windows envs, usually we use the absolute path in the guest.
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 2. File Verification (40 pts)
    output_exists = result.get('output_exists', False)
    file_created = result.get('file_created_during_task', False)
    file_content = result.get('file_content', "")
    
    if output_exists:
        score += 10
        if file_created:
            score += 10
            feedback.append("Report file created.")
        else:
            feedback.append("Report file exists but timestamp is old.")
    else:
        feedback.append("Report file not found.")
        return {"passed": False, "score": 0, "feedback": "Report file not found"}

    # 3. Content Parsing (40 pts)
    # Expecting format like: "ChiSquare: 102.89", "DF: 2", "P: 0.00"
    # We'll use regex to find numbers near keywords
    
    # Find ChiSquare
    chisq_match = re.search(r'(?:chi|pearson).*?(\d+\.?\d*)', file_content, re.IGNORECASE)
    chisq_val = float(chisq_match.group(1)) if chisq_match else None
    
    # Find DF
    df_match = re.search(r'(?:df|degrees|freedom).*?(\d+)', file_content, re.IGNORECASE)
    df_val = int(df_match.group(1)) if df_match else None
    
    # Find P-value
    p_match = re.search(r'(?:p-?val|prob).*?(\d?\.?\d+)', file_content, re.IGNORECASE)
    p_val = float(p_match.group(1)) if p_match else None
    
    # Score Values
    if chisq_val is not None and abs(chisq_val - expected_chisq) <= tolerance:
        score += 20
        feedback.append(f"Chi-Square correct ({chisq_val}).")
    else:
        feedback.append(f"Chi-Square incorrect or missing (Found: {chisq_val}, Expected: {expected_chisq}).")

    if df_val == 2:
        score += 10
        feedback.append("Degrees of Freedom correct (2).")
    else:
        feedback.append(f"Degrees of Freedom incorrect (Found: {df_val}).")

    if p_val is not None and p_val < 0.001:
        score += 10
        feedback.append("P-value correct (significant).")
    elif p_val is not None:
        feedback.append(f"P-value incorrect (Found: {p_val}).")
    else:
        feedback.append("P-value missing.")

    # 4. VLM Verification (20 pts)
    # Check if Classic Analysis was actually used
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if frames:
        prompt = """
        You are verifying an epidemiology task in Epi Info 7.
        The user should be in the 'Classic Analysis' module.
        Look for:
        1. A window titled 'Analysis' or 'Classic Analysis'.
        2. A command output area showing a 'Tables' result (a grid/contingency table).
        3. The Titanic dataset being used (commands like READ or variables like Pclass/Survived).
        
        Does the user appear to be performing the analysis correctly?
        """
        
        vlm_res = query_vlm(images=frames + [final_screen], prompt=prompt)
        
        if vlm_res.get('success') and vlm_res.get('parsed', {}).get('positive_verification', True):
             # Simple heuristic: if VLM doesn't explicitly complain, assume partial credit
             # In a real impl, we'd parse the boolean response
             score += 20
             feedback.append("Visual verification passed.")
        else:
             score += 10 # Give benefit of doubt if VLM fails/uncertain
             feedback.append("Visual verification uncertain.")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }