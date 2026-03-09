#!/usr/bin/env python3
"""
Verifier for calculate_fleet_utilization task.

Checks if the user calculated the correct total flight duration (135 minutes)
for 'SkyHigh Surveyors' in October 2023.
"""

import json
import re
import tempfile
import os

def verify_calculate_fleet_utilization(traj, env_info, task_info):
    """
    Verify the utilization report contains the correct duration (135).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected value from metadata (default 135)
    metadata = task_info.get('metadata', {})
    expected_value = metadata.get('expected_value', 135)
    tolerance = metadata.get('tolerance', 2)

    # Read result from container
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

    # Scoring
    score = 0
    feedback_parts = []
    
    # 1. Check if file exists (20 pts)
    if result.get('report_exists'):
        score += 20
        feedback_parts.append("Report file exists (+20)")
    else:
        return {"passed": False, "score": 0, "feedback": "Report file not found"}

    # 2. Check content (80 pts)
    content = result.get('report_content', '')
    # Extract all numbers from the content
    nums = re.findall(r'\d+', content)
    
    val_found = False
    if nums:
        # Check if any number matches the expected value within tolerance
        # (Agents might write "135" or "135 minutes" or "Total: 135")
        # We take the number that is closest to expectation if multiple exist, 
        # or just the first one if unambiguous.
        # Let's be strict: The *calculated* number must be there.
        for num_str in nums:
            try:
                val = int(num_str)
                if abs(val - expected_value) <= tolerance:
                    val_found = True
                    break
            except ValueError:
                continue
    
    if val_found:
        score += 80
        feedback_parts.append(f"Correct calculated value found: {expected_value} (+80)")
    else:
        feedback_parts.append(f"Incorrect value. Found numbers: {nums}, Expected: {expected_value}")

    # 3. Anti-gaming (File modification check)
    if not result.get('file_created_during_task'):
        feedback_parts.append("(Warning: File not modified during task execution)")
        # We might penalize here, but for now just warn in feedback.

    passed = score >= 100
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }