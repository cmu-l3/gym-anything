#!/usr/bin/env python3
"""
Verifier for generate_patient_demographics_report@1.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_patient_demographics_report(traj, env_info, task_info):
    """
    Verifies that the agent generated the filtered patient report and recorded the count.
    
    Scoring:
    1. File Validation (15 pts): File exists, valid integer, created during task.
    2. Data Accuracy (35 pts): Count matches ground truth (within tolerance).
    3. Visual Verification (50 pts):
       - Login successful
       - Reports module accessed
       - Filters applied (Male, DOB)
       - Report generated
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # --- 1. Load Programmatic Results ---
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Extract data
    file_exists = result.get("file_exists", False)
    file_content = result.get("file_content", "")
    created_during = result.get("file_created_during_task", False)
    ground_truth = int(result.get("ground_truth_count", -1))

    # --- 2. Evaluate Output File (Max 50 pts) ---
    
    # Check existence
    if file_exists:
        score += 10
        feedback_parts.append("Output file exists.")
    else:
        feedback_parts.append("Output file '/home/ga/patient_report_count.txt' not found.")
    
    # Check anti-gaming
    if created_during:
        score += 5
        feedback_parts.append("File created during task session.")
    elif file_exists:
        feedback_parts.append("Warning: File timestamp indicates it wasn't created during this session.")

    # Check content accuracy
    agent_count = -1
    if file_content.isdigit():
        agent_count = int(file_content)
        
        # Calculate error percentage
        if ground_truth > 0:
            diff = abs(agent_count - ground_truth)
            percent_error = (diff / ground_truth) * 100
            
            if diff == 0:
                score += 35
                feedback_parts.append(f"Count {agent_count} is exactly correct.")
            elif percent_error <= 3.0:
                score += 35
                feedback_parts.append(f"Count {agent_count} is within 3% tolerance (Truth: {ground_truth}).")
            elif percent_error <= 10.0:
                score += 15
                feedback_parts.append(f"Count {agent_count} is close (within 10%) but imprecise (Truth: {ground_truth}).")
            else:
                feedback_parts.append(f"Count {agent_count} is incorrect (Truth: {ground_truth}).")
        else:
            # Fallback if ground truth failed (unlikely)
            if agent_count > 100: 
                score += 5
                feedback_parts.append("Count seems reasonable (positive integer).")
    else:
        if file_exists:
            feedback_parts.append(f"File content '{file_content}' is not a valid integer.")

    # --- 3. VLM Trajectory Verification (Max 50 pts) ---
    
    # Sample frames to see workflow
    frames = sample_trajectory_frames(traj, n=6)
    
    vlm_prompt = """
    You are verifying an agent using LibreHealth EHR (Electronic Health Records).
    The goal is to generate a patient report filtered by Sex=Male and DOB < 1960.
    
    Analyze the sequence of screenshots. Look for these specific steps:
    1. LOGIN: Successful login to the dashboard.
    2. NAVIGATION: Navigate to the 'Reports' menu (or 'Clients' -> 'List').
    3. CONFIGURATION: Setting report filters. Look specifically for:
       - 'Male' selected in a gender/sex dropdown.
       - A date entered in a DOB/Date of Birth field (looking for '1960' or similar).
    4. GENERATION: A list of patients or a report result displayed on screen.
    
    Respond in JSON:
    {
        "login_visible": true/false,
        "reports_navigated": true/false,
        "filters_visible": true/false,
        "results_displayed": true/false,
        "confidence": "low/medium/high",
        "explanation": "Brief reasoning"
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    vlm_score = 0
    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        if parsed.get("login_visible"):
            vlm_score += 10
        if parsed.get("reports_navigated"):
            vlm_score += 10
        if parsed.get("filters_visible"):
            vlm_score += 15
        if parsed.get("results_displayed"):
            vlm_score += 15
            
        feedback_parts.append(f"VLM Analysis: {parsed.get('explanation', 'Workflow verified')}")
    else:
        feedback_parts.append("VLM verification failed to process images.")
        # Fallback partial credit if they got the exact number correct, assuming they must have seen it
        if score >= 45: # They got file + exact count
             vlm_score = 25 # Give half VLM points for getting the hard part right
             feedback_parts.append("Granted partial VLM credit based on result accuracy.")

    score += vlm_score

    # Determine Pass/Fail
    # Must have a reasonable file AND reasonable score
    passed = (score >= 60) and (file_exists) and (agent_count > 0)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }