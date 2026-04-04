#!/usr/bin/env python3
"""
Verifier for validate_outbreak_temporal_logic task.

Task: Identify records where Onset < Exposure OR Report < Onset.
Output: HTML file with list of invalid records.

Verification Criteria:
1. Output file exists and was created during task.
2. File contains the specific injected error IDs (Recall).
3. File does NOT contain valid IDs (Precision).
4. VLM: Confirms visual evidence of the analysis (Analysis window, List command output).
"""

import json
import os
import logging
import tempfile
import re
from typing import Dict, Any

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Metadata - MUST match setup_task.ps1
ERROR_IDS = ["CASE_015", "CASE_042", "CASE_088", "CASE_101"]
# Sample of valid IDs to ensure they aren't listed (anti-gaming: dumping all data)
VALID_IDS_SAMPLE = ["CASE_001", "CASE_002", "CASE_010", "CASE_100", "CASE_150"]

def verify_validate_outbreak_temporal_logic(traj, env_info, task_info):
    """
    Verify the agent correctly identified temporal logic errors.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment access failed (copy_from_env missing)"}

    # 1. Fetch Result JSON from Container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    output_exists = result.get("output_exists", False)
    file_created = result.get("file_created_during_task", False)
    content = result.get("file_content_snippet", "")
    
    score = 0
    feedback = []
    
    # 3. Evaluate Output Existence (20 pts)
    if output_exists:
        score += 10
        feedback.append("Output file found.")
        if file_created:
            score += 10
            feedback.append("File created during task.")
        else:
            feedback.append("Warning: File timestamp indicates it wasn't created during this session.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file 'Temporal_Errors.html' not found."}

    # 4. Content Verification (Logic Check) (60 pts)
    # We check if the HTML content contains the ID strings
    
    # Check for correct errors (Recall)
    found_errors = 0
    missing_errors = []
    for err_id in ERROR_IDS:
        if err_id in content:
            found_errors += 1
        else:
            missing_errors.append(err_id)
            
    recall_score = (found_errors / len(ERROR_IDS)) * 40
    score += recall_score
    if missing_errors:
        feedback.append(f"Missed invalid records: {', '.join(missing_errors)}")
    else:
        feedback.append("Correctly identified all invalid records.")

    # Check for false positives (Precision)
    # If the agent just dumped the whole table, they fail this check
    found_valid = 0
    for valid_id in VALID_IDS_SAMPLE:
        if valid_id in content:
            found_valid += 1
            
    precision_score = 20
    if found_valid > 0:
        precision_score = 0
        feedback.append(f"Included valid records (e.g., {valid_id}) - Analysis logic incorrect.")
    else:
        feedback.append("Did not include random sample of valid records.")
        
    score += precision_score

    # 5. VLM Verification (20 pts)
    # Check trajectory for 'SELECT' or 'LIST' commands
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    frames = sample_trajectory_frames(traj, n=4)
    if not frames:
         feedback.append("No trajectory frames available for visual verification.")
    else:
        vlm_prompt = """
        You are verifying an Epi Info 7 task.
        Look at the screenshots. The user should have:
        1. Open the "Classic Analysis" window.
        2. Issued a "READ" command.
        3. Issued a "SELECT" command (or IF statement) involving DateOnset, DateExposure, or DateReport.
        4. Issued a "LIST" command to show a grid of results.
        
        Do you see a result grid or table showing specific records?
        Do you see any commands related to date comparison (e.g., <, >, DATEDIFF)?
        
        Return JSON: {"evidence_found": true/false, "explanation": "..."}
        """
        
        try:
            vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
            if vlm_res.get("parsed", {}).get("evidence_found", False):
                score += 20
                feedback.append("Visual evidence of correct analysis workflow found.")
            else:
                feedback.append("Visual verification inconclusive: " + vlm_res.get("parsed", {}).get("explanation", ""))
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Grant partial points if logic verification was perfect
            if recall_score == 40 and precision_score == 20:
                score += 10

    # 6. Final Assessment
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": round(score),
        "feedback": " ".join(feedback)
    }