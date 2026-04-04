#!/usr/bin/env python3
"""
Verifier for calculate_smr_british_doctors@1
"""

import json
import tempfile
import os
import re
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_calculate_smr_british_doctors(traj, env_info, task_info):
    """
    Verifies that the agent calculated the correct SMR and Total Expected deaths.
    
    Verification Signals:
    1. Report file exists and was created during the task.
    2. Report contains the correct SMR (~14.69) and Total Expected (~10.35).
    3. VLM trajectory check: Did the agent perform a MERGE operation?
    """
    
    # 0. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    metadata = task_info.get('metadata', {})
    expected_smr_min = metadata.get('expected_smr_min', 14.5)
    expected_smr_max = metadata.get('expected_smr_max', 14.9)
    expected_exp_min = metadata.get('expected_total_expected_min', 10.2)
    expected_exp_max = metadata.get('expected_total_expected_max', 10.5)

    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Check File Existence and Timing (20 pts)
    report_exists = result.get('report_exists', False)
    file_created = result.get('file_created_during_task', False)
    report_content = result.get('report_content', "")

    if report_exists:
        if file_created:
            score += 20
            feedback_parts.append("Report file created successfully.")
        else:
            score += 5
            feedback_parts.append("Report file exists but timestamp is old (reused file?).")
    else:
        feedback_parts.append("Report file not found.")

    # 3. Check Values in Report (60 pts)
    # Looking for SMR ~14.69 and Expected ~10.35
    # Regex to find floating point numbers
    numbers = [float(x) for x in re.findall(r"[-+]?\d*\.\d+|\d+", report_content)]
    
    smr_found = False
    expected_found = False
    
    for num in numbers:
        if expected_smr_min <= num <= expected_smr_max:
            smr_found = True
        if expected_exp_min <= num <= expected_exp_max:
            expected_found = True
            
    if smr_found:
        score += 35
        feedback_parts.append(f"Correct SMR value found in report.")
    else:
        feedback_parts.append(f"SMR value incorrect or missing. Expected range: {expected_smr_min}-{expected_smr_max}.")

    if expected_found:
        score += 25
        feedback_parts.append(f"Correct Total Expected deaths found.")
    else:
        feedback_parts.append(f"Total Expected deaths incorrect or missing. Expected range: {expected_exp_min}-{expected_exp_max}.")

    # 4. VLM Trajectory Verification (20 pts)
    # Check if the MERGE command or dialog was used
    frames = sample_trajectory_frames(traj, n=5)
    
    vlm_prompt = """
    Review these screenshots of an Epi Info 7 session.
    The user should be performing an SMR analysis.
    Look for:
    1. The 'Classic Analysis' window.
    2. Evidence of a MERGE operation (either the MERGE command in the output or the Merge dialog).
    3. Evidence of defining a new variable (Expected or ExpectedDeaths).
    4. A SUMMARIZE or LIST command output showing totals.
    
    Return JSON:
    {
        "analysis_module_open": true/false,
        "merge_evidence": true/false,
        "calculation_evidence": true/false,
        "summarize_evidence": true/false
    }
    """
    
    try:
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        parsed = vlm_res.get('parsed', {})
        
        if parsed.get('analysis_module_open', False):
            score += 5
        if parsed.get('merge_evidence', False):
            score += 5
            feedback_parts.append("Merge operation verified visually.")
        if parsed.get('calculation_evidence', False):
            score += 5
        if parsed.get('summarize_evidence', False):
            score += 5
            
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Graceful degradation - don't penalize if VLM fails but file is correct
        if smr_found and expected_found:
            score += 20
            feedback_parts.append("VLM skipped (Full points awarded based on correct output).")

    # Final logic
    # Must have correct SMR to pass
    passed = (score >= 80) and smr_found

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }