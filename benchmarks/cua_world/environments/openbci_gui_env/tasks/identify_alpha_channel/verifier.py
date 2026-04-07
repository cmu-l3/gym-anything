#!/usr/bin/env python3
"""
Verifier for identify_alpha_channel task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_identify_alpha_channel(traj, env_info, task_info):
    """
    Verify the agent identified the correct Alpha channel.
    
    Scoring:
    - Output file exists and is valid integer: 15 pts
    - Anti-gaming (file created during task): 15 pts
    - App was running: 10 pts
    - Correct Channel (Exact match): 60 pts
    - OR Close Channel (In top 3): 30 pts (Partial credit)
    
    Total: 100 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check File Existence (15 pts)
    if result.get("output_exists", False):
        score += 15
        feedback_parts.append("Output file found.")
    else:
        feedback_parts.append("Output file NOT found.")
        return {"passed": False, "score": 0, "feedback": "Output file not found."}

    # 2. Check Anti-Gaming (15 pts)
    if result.get("file_created_during_task", False):
        score += 15
        feedback_parts.append("File created during task.")
    else:
        feedback_parts.append("File pre-dated task (Anti-gaming penalty).")

    # 3. Check App State (10 pts)
    if result.get("app_was_running", False):
        score += 10
        feedback_parts.append("OpenBCI GUI was running.")
    else:
        feedback_parts.append("OpenBCI GUI was NOT running.")

    # 4. Check Value Correctness (60 pts max)
    reported_str = result.get("reported_value", "")
    ground_truth_str = result.get("ground_truth", "")
    
    # Parse Top 3 for partial credit
    top3_str = result.get("ground_truth_top3", "")
    top3 = []
    if top3_str:
        top3 = [x.strip() for x in top3_str.split(',') if x.strip()]

    try:
        reported_val = int(reported_str)
        ground_truth_val = int(ground_truth_str) if ground_truth_str else -1
        
        if reported_val == ground_truth_val:
            score += 60
            feedback_parts.append(f"CORRECT: Channel {reported_val} matches ground truth.")
        elif str(reported_val) in top3:
            score += 30
            feedback_parts.append(f"CLOSE: Channel {reported_val} is in top 3 (Ground truth: {ground_truth_val}).")
        else:
            feedback_parts.append(f"INCORRECT: Reported {reported_val}, expected {ground_truth_val}.")
            
    except ValueError:
        feedback_parts.append(f"INVALID FORMAT: Could not parse '{reported_str}' as integer.")
    
    # VLM Check (Optional integration point, usually handled by framework using traj)
    # We can assume if the programmatic check passes, they likely used the tool, 
    # but strictly we rely on the logic above.
    
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }