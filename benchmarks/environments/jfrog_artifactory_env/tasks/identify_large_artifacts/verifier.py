#!/usr/bin/env python3
"""
Verifier for identify_large_artifacts task.

Checks:
1. Output file exists and was created during task.
2. File contains names of artifacts > 5MB (True Positives).
3. File does NOT contain names of artifacts < 5MB (False Positives).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_identify_large_artifacts(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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
    
    # 1. Check File Existence (20 pts)
    if not result.get("file_exists", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Report file 'large_artifacts.txt' was not found in /home/ga/"
        }
    
    score += 10
    feedback_parts.append("File created")
    
    if result.get("created_during_task", False):
        score += 10
    else:
        feedback_parts.append("(Warning: File timestamp indicates it might be old)")

    # 2. Analyze Content
    content = result.get("file_content", "")
    # Normalize content: split by lines, strip whitespace, ignore empty lines
    agent_lines = [line.strip() for line in content.split('\n') if line.strip()]
    
    ground_truth_large = result.get("ground_truth_large", [])
    ground_truth_small = result.get("ground_truth_small", [])
    
    # Check True Positives (50 pts)
    # Are all large files listed?
    missing_large = []
    found_large_count = 0
    
    for large_file in ground_truth_large:
        # Flexible matching: verify if the filename appears in any line
        if any(large_file in line for line in agent_lines):
            found_large_count += 1
        else:
            missing_large.append(large_file)
            
    if not ground_truth_large:
        # Edge case: no large files existed (shouldn't happen with setup)
        score += 50
    else:
        # Proportional score
        portion = found_large_count / len(ground_truth_large)
        score += int(50 * portion)
        if missing_large:
            feedback_parts.append(f"Missing large files: {', '.join(missing_large)}")
        else:
            feedback_parts.append("All large files identified")

    # Check False Positives (30 pts)
    # Are any small files listed?
    found_small = []
    for small_file in ground_truth_small:
        if any(small_file in line for line in agent_lines):
            found_small.append(small_file)
            
    if found_small:
        # Penalty: Lose points for false positives
        # If they listed everything, they shouldn't get points for avoiding small files
        feedback_parts.append(f"Incorrectly listed small files: {', '.join(found_small)}")
    else:
        score += 30
        feedback_parts.append("No small files incorrectly listed")

    # Final Pass check
    # Require file existence + all large files found + score >= 70
    all_large_found = (len(missing_large) == 0)
    passed = (result.get("file_exists") and all_large_found and score >= 90)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }