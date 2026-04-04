#!/usr/bin/env python3
"""
Verifier for export_host_visitor_history task.
Checks if the agent successfully filtered and exported the visitor log for a specific host.
"""

import json
import os
import csv
import tempfile
import logging
import sys
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_host_visitor_history(traj, env_info, task_info):
    """
    Verify that the user exported a CSV containing ONLY visitors for James Wilson.
    
    Criteria:
    1. Output file exists and is a CSV.
    2. File was created during the task window.
    3. Content Check:
       - Contains "James Wilson" (target host).
       - Does NOT contain "Sarah Connor" or other known hosts (proving filtering).
       - Has reasonable number of rows (not empty, not full database).
    4. VLM Check: Trajectory shows use of Filter/Search features.
    """
    
    # 1. Setup and Environment Check
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_host = metadata.get('target_host', 'James Wilson')
    excluded_hosts = metadata.get('excluded_hosts', [])
    
    # Load result JSON from export_result.sh
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

    # 2. Score Calculation
    score = 0
    feedback_parts = []
    
    # Criterion 1: File Existence & Creation Time (30 pts)
    output_exists = task_result.get('output_exists', False)
    created_during = task_result.get('file_created_during_task', False)
    
    if output_exists:
        score += 10
        feedback_parts.append("Output file found.")
        if created_during:
            score += 20
            feedback_parts.append("File created during task.")
        else:
            feedback_parts.append("File timestamp indicates it was not created during this session.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file 'james_wilson_visitors.csv' not found."}

    # Criterion 2: Content Analysis (40 pts)
    content_score = 0
    content_feedback = []
    
    # Copy the CSV file to host for analysis
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env(task_result['output_path'], temp_csv.name)
        
        with open(temp_csv.name, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
            
        # Basic text check (robust against CSV formatting nuances)
        if target_host in content:
            content_score += 20
            content_feedback.append(f"Contains target host '{target_host}'.")
        else:
            content_feedback.append(f"Target host '{target_host}' NOT found in file.")

        # Check for exclusions (Did they filter?)
        failed_exclusions = [h for h in excluded_hosts if h in content]
        if not failed_exclusions:
            content_score += 20
            content_feedback.append("Correctly excluded other hosts.")
        else:
            content_feedback.append(f"Failed to filter: Found records for {', '.join(failed_exclusions)}.")
            
        # Row count check (Sanity check)
        row_count = len(content.splitlines())
        if row_count < 2: # Header + at least 1 record
             content_feedback.append("File appears empty or missing data.")
             content_score = 0
             
    except Exception as e:
        content_feedback.append(f"Error analyzing CSV content: {str(e)}")
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)
            
    score += content_score
    feedback_parts.extend(content_feedback)

    # Criterion 3: VLM Verification (30 pts)
    # Check if agent used filter/search UI
    vlm_score = 0
    
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    if frames and final_shot:
        prompt = (
            "Review these screenshots of a user interacting with Lobby Track software. "
            "Did the user perform the following actions?\n"
            "1. Navigate to a visitor log or report view.\n"
            "2. Use a 'Filter', 'Search', or 'Query' feature to select specific records.\n"
            "3. Initiate an export or save operation.\n\n"
            "Respond with JSON: {'filtered_data': bool, 'exported_data': bool, 'confidence': float}"
        )
        
        try:
            vlm_resp = query_vlm(images=frames + [final_shot], prompt=prompt)
            result = vlm_resp.get('parsed', {})
            
            if result.get('filtered_data'):
                vlm_score += 15
                feedback_parts.append("VLM confirmed data filtering action.")
            if result.get('exported_data'):
                vlm_score += 15
                feedback_parts.append("VLM confirmed export action.")
                
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: if file is perfect, give benefit of doubt for VLM
            if content_score == 40: 
                vlm_score = 30
                feedback_parts.append("VLM skipped, inferred success from file content.")

    score += vlm_score

    # Final Pass/Fail Determination
    # Must have file, correct content, and no excluded data
    passed = (output_exists and created_during and content_score == 40)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }