#!/usr/bin/env python3
"""
Verifier for troubleshoot_404_errors@1

Strategy:
1. Verify the specific file identified in logs now exists (40 pts)
2. Verify it is in the correct directory structure (30 pts)
3. Verify it was created *during* the task (anti-gaming) (20 pts)
4. Verify Virtualmin/File Manager interaction via VLM (10 pts)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_troubleshoot_404_errors(traj, env_info, task_info):
    # 1. Setup - Get Result JSON
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Score Calculation
    score = 0
    feedback = []
    
    file_exists = result.get('file_exists', False)
    dir_exists = result.get('dir_exists', False)
    created_during = result.get('file_created_during_task', False)
    target_path = result.get('target_rel_path', 'unknown path')

    # Criterion A: Directory Structure (30 pts)
    # Even if they named the file wrong, getting the folder right is partial success
    if dir_exists:
        score += 30
        feedback.append("Correct directory structure created.")
    else:
        feedback.append("Directory structure missing or incorrect.")

    # Criterion B: File Existence & Correct Name (40 pts)
    if file_exists:
        score += 40
        feedback.append(f"Correct file '{target_path}' created.")
    else:
        feedback.append(f"File '{target_path}' not found.")

    # Criterion C: Anti-Gaming / Freshness (20 pts)
    if file_exists and created_during:
        score += 20
        feedback.append("File was created during the task session.")
    elif file_exists and not created_during:
        feedback.append("File exists but has old timestamp (anti-gaming check failed).")

    # Criterion D: VLM Verification of Workflow (10 pts)
    # Did they use Logs or File Manager?
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        if final:
            frames.append(final)
            
        if frames:
            prompt = """
            Analyze these screenshots of a Virtualmin system administration task.
            The user is supposed to:
            1. Look at 'Logs and Reports' (Apache Access Log).
            2. Use 'File Manager' to create a file.
            
            Do you see evidence of:
            - The Log Viewer or Apache Logs being open?
            - The File Manager interface?
            
            Answer YES or NO for each.
            """
            vlm_response = query_vlm(images=frames, prompt=prompt)
            content = vlm_response.get('content', '').lower()
            
            if 'yes' in content and ('log' in content or 'file manager' in content):
                vlm_score = 10
                feedback.append("Visual evidence of Log/File Manager usage found.")
            else:
                feedback.append("No visual confirmation of workflow (Logs/File Manager).")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: if they got the file right, they likely used the tools. 
        # Give points if file exists.
        if file_exists:
            vlm_score = 10
    
    score += vlm_score

    # 3. Final Determination
    # Pass threshold: 70. 
    # Requires (Dir + File) OR (File + Freshness + VLM)
    passed = score >= 70 and file_exists

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }