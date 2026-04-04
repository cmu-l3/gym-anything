#!/usr/bin/env python3
"""
Verifier for Chemical Storage Segregation Task.
"""

import json
import csv
import os
import tempfile
import logging
from typing import Dict, Any, List

# Import VLM utils provided by the environment/framework
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
except ImportError:
    # Fallback/Mock for local testing if needed, though strictly we should expect it
    def sample_trajectory_frames(traj, n=5): return []
    def query_vlm(images, prompt): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chemical_storage_segregation(traj, env_info, task_info):
    """
    Verifies the CSV storage plan for accuracy and proper workflow.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_chemicals = metadata.get('expected_chemicals', [])
    
    # 1. Load result JSON from export_result.sh
    task_result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check basic file existence/creation requirements
    if not task_result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file 'storage_plan.csv' was not created."}
    
    if not task_result.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Output file exists but was not created/modified during the task session (anti-gaming check failed)."}

    # 3. Load and parse the CSV content
    score = 20 # Base points for creating the file
    feedback = []
    
    csv_content = []
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env("/home/ga/Documents/storage_plan.csv", temp_csv.name)
        with open(temp_csv.name, 'r', encoding='utf-8', errors='replace') as f:
            reader = csv.DictReader(f)
            # Normalize headers
            reader.fieldnames = [name.strip().lower() for name in reader.fieldnames] if reader.fieldnames else []
            
            # Check for required columns
            required_cols = ['chemical name', 'reactive group', 'storage code']
            missing_cols = [c for c in required_cols if c not in reader.fieldnames]
            
            if missing_cols:
                return {"passed": False, "score": 10, "feedback": f"CSV missing required columns: {', '.join(missing_cols)}"}
            
            for row in reader:
                # Normalize row keys/values
                normalized_row = {k: v.strip() for k, v in row.items() if k}
                csv_content.append(normalized_row)
    except Exception as e:
        return {"passed": False, "score": 10, "feedback": f"Failed to parse CSV file: {str(e)}"}
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # 4. Verify Content (Logic Check)
    # Mapping expected data to score
    # 5 chemicals * 12 points each = 60 points max for content
    # + 20 points for file existence = 80 total so far
    # + 20 points for VLM verification = 100 total
    
    matched_chemicals = 0
    correct_entries = 0
    
    for expected in expected_chemicals:
        name_key = expected['name'].lower()
        found_row = None
        
        # Find row by chemical name (fuzzy match)
        for row in csv_content:
            row_name = row.get('chemical name', '').lower()
            if name_key in row_name or row_name in name_key:
                found_row = row
                break
        
        if not found_row:
            feedback.append(f"Missing entry for {expected['name']}.")
            continue
            
        matched_chemicals += 1
        
        # Check Reactive Group (Substring match)
        # The agent must extract the real group name, e.g. "Acids, Strong Non-oxidizing"
        # We check if it contains the key word (e.g. "Acids")
        found_group = found_row.get('reactive group', '')
        found_code = found_row.get('storage code', '').upper()
        
        group_correct = expected['reactive_group_substring'].lower() in found_group.lower()
        code_correct = found_code == expected['expected_code']
        
        if group_correct and code_correct:
            score += 12
            correct_entries += 1
        elif not group_correct:
            feedback.append(f"{expected['name']}: Incorrect Reactive Group (Expected substring '{expected['reactive_group_substring']}', got '{found_group}').")
        elif not code_correct:
            feedback.append(f"{expected['name']}: Incorrect Code (Expected '{expected['expected_code']}', got '{found_code}').")

    # 5. VLM Verification (Trajectory Analysis)
    # Check if agent actually used the website
    vlm_frames = sample_trajectory_frames(traj, n=4)
    vlm_score = 0
    if vlm_frames:
        prompt = (
            "Review these screenshots of an agent performing a task.\n"
            "Did the agent:\n"
            "1. Visit the CAMEO Chemicals website (NOAA)?\n"
            "2. Search for chemicals or view datasheets?\n"
            "Answer 'YES' or 'NO' and provide a brief reason."
        )
        try:
            vlm_res = query_vlm(images=vlm_frames, prompt=prompt)
            if vlm_res.get("success") and "YES" in vlm_res.get("result", "").upper():
                vlm_score = 20
                score += vlm_score
            else:
                feedback.append("VLM verification failed: Could not verify usage of CAMEO Chemicals website.")
        except Exception as e:
            logger.warning(f"VLM check failed with error: {e}")
            # If VLM fails due to technical reasons, we might default to giving points if CSV is perfect,
            # but strict anti-gaming usually requires evidence. 
            # We will give partial credit if CSV is perfect to avoid punishing system errors too harshly.
            if correct_entries == 5:
                score += 10 
    else:
        feedback.append("No trajectory frames available for verification.")

    # 6. Final Assessment
    pass_threshold = 74 # Requires file existence (20) + ~3-4 correct entries (36-48) + VLM (20)
    passed = score >= pass_threshold
    
    final_feedback = f"Score: {score}/100. " + " ".join(feedback)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": final_feedback
    }