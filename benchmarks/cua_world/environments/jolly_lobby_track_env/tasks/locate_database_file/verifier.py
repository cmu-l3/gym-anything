#!/usr/bin/env python3
"""
Verifier for locate_database_file task.
"""

import json
import tempfile
import os
import logging
import math
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_locate_database_file(traj, env_info, task_info):
    """
    Verify that the agent correctly identified the database file.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result JSON
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
    max_score = 100
    
    # Extract data
    report_exists = result.get('report_exists', False)
    agent_path = result.get('agent_reported', {}).get('path', '')
    agent_size_str = result.get('agent_reported', {}).get('size', '0')
    agent_format = result.get('agent_reported', {}).get('format', '')
    
    gt_path = result.get('ground_truth', {}).get('path', '')
    gt_size = result.get('ground_truth', {}).get('size', 0)
    
    path_exists = result.get('validation', {}).get('path_exists', False)
    real_size = result.get('validation', {}).get('actual_size_of_agent_path', 0)
    
    # --- Scoring Criteria ---

    # 1. Report existence and formatting (20 pts)
    if report_exists:
        score += 10
        if agent_path and agent_size_str and agent_format:
            score += 10
            feedback_parts.append("Report format correct")
        else:
            feedback_parts.append("Report format incomplete")
    else:
        return {"passed": False, "score": 0, "feedback": "No report file found"}

    # 2. Path Validity (30 pts)
    if path_exists:
        score += 15
        feedback_parts.append("Path points to existing file")
        
        # Check if it matches ground truth OR is a valid alternative
        # (Sometimes multiple DB backups exist, we accept valid DBs in the right folder)
        is_exact_match = (agent_path == gt_path)
        is_same_dir = (os.path.dirname(agent_path) == os.path.dirname(gt_path))
        is_db = result.get('validation', {}).get('path_is_db_extension', False)
        
        if is_exact_match:
            score += 15
            feedback_parts.append("Found primary database file")
        elif is_same_dir and is_db:
            score += 10 # Close enough (maybe backup file)
            feedback_parts.append("Found valid database file in correct directory")
        elif is_db and "Lobby" in agent_path:
            score += 5
            feedback_parts.append("Found a Lobby Track database (possibly not main one)")
        else:
            feedback_parts.append("File found but doesn't look like main DB")
    else:
        feedback_parts.append(f"Path does not exist: {agent_path}")

    # 3. Size Accuracy (20 pts)
    try:
        agent_size = int(agent_size_str)
        # Compare agent reported size to ACTUAL size of the file they pointed to
        if path_exists and real_size > 0:
            diff_percent = abs(agent_size - real_size) / real_size
            if diff_percent < 0.1: # 10% tolerance
                score += 20
                feedback_parts.append("Size reported correctly")
            else:
                feedback_parts.append(f"Size mismatch (Reported: {agent_size}, Actual: {real_size})")
        else:
             feedback_parts.append("Cannot verify size (invalid file)")
    except ValueError:
        feedback_parts.append("Invalid size format")

    # 4. Format/Extension (10 pts)
    if agent_format and agent_path:
        ext = os.path.splitext(agent_path)[1].replace('.', '').lower()
        if agent_format.lower() == ext:
            score += 10
            feedback_parts.append("Format matches extension")
        else:
            feedback_parts.append(f"Format mismatch ({agent_format} vs {ext})")

    # 5. VLM Verification (20 pts)
    # Did the agent actually look at settings?
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_screen = get_final_screenshot(traj)
        
        vlm_prompt = (
            "Does the user appear to be searching for database settings? "
            "Look for 'Options', 'Preferences', 'Database', 'Data Path', or Windows Explorer showing 'Lobby Track'. "
            "Return JSON with 'settings_opened' (bool) and 'explorer_used' (bool)."
        )
        
        try:
            vlm_res = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('settings_opened') or parsed.get('explorer_used'):
                    score += 20
                    feedback_parts.append("VLM confirmed investigation")
                else:
                    feedback_parts.append("VLM did not see explicit investigation steps")
            else:
                score += 10 # Benefit of doubt if VLM fails
        except:
            score += 10 # Benefit of doubt
    else:
        score += 20 # Skip check if no VLM

    # Pass threshold
    passed = (score >= 60) and path_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }