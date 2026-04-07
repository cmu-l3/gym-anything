#!/usr/bin/env python3
"""
Verifier for configure_system_holidays task.

Checks:
1. Valid JSON result from database query.
2. Existence of 3 specific holidays in 2026 (Memorial, Labor, Thanksgiving).
3. Correct dates and partial name matching.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_system_holidays(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata expectations
    metadata = task_info.get('metadata', {})
    expected_holidays = metadata.get('holidays', [
        {"date": "2026-05-25", "name_keywords": ["Memorial"]},
        {"date": "2026-09-07", "name_keywords": ["Labor"]},
        {"date": "2026-11-26", "name_keywords": ["Thanksgiving"]}
    ])

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Check for basic success of the query script
    if result.get('status') != 'success':
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Database query failed: {result.get('message', 'Unknown error')}"
        }

    actual_holidays = result.get('holidays', [])
    
    score = 0
    max_score = 100
    # Base score for successfully running the check
    score += 10 
    
    feedback_lines = []
    
    # Check each expected holiday
    for expected in expected_holidays:
        target_date = expected['date']
        keywords = expected['name_keywords']
        
        # Find match by date
        match = next((h for h in actual_holidays if h.get('date') == target_date), None)
        
        if match:
            # Check name
            actual_name = match.get('name', '')
            name_match = any(k.lower() in actual_name.lower() for k in keywords)
            
            if name_match:
                score += 30
                feedback_lines.append(f"SUCCESS: Found {actual_name} on {target_date}")
            else:
                score += 15 # Partial credit for correct date but wrong name
                feedback_lines.append(f"PARTIAL: Found date {target_date}, but name '{actual_name}' does not match keywords {keywords}")
        else:
            feedback_lines.append(f"MISSING: No entry found for {keywords[0]} Day on {target_date}")

    passed = (score >= 90)
    
    return {
        "passed": passed,
        "score": min(score, max_score),
        "feedback": "\n".join(feedback_lines)
    }