#!/usr/bin/env python3
"""
Verifier for create_function task in OrientDB.
"""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_function(traj, env_info, task_info):
    """
    Verify the agent created the OrientDB function and saved results to file.
    
    Scoring:
    - Function exists in DB: 25 pts
    - Function is callable and returns correct values (via API check): 30 pts (15 per country)
    - Output file exists and created during task: 15 pts
    - Output file content is correct: 30 pts (15 per country)
    
    Pass Threshold: 60 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
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

    score = 0
    feedback_parts = []
    
    # 1. Check Function Existence (25 pts)
    if result.get('function_exists', False):
        score += 25
        feedback_parts.append("Function 'getAvgHotelStars' exists in DB")
    else:
        feedback_parts.append("Function 'getAvgHotelStars' NOT found in DB")

    # 2. Check Function Logic (30 pts)
    # Expected: Italy ~ 4.5, Japan ~ 5.0
    italy_val = result.get('test_result_italy', 'null')
    japan_val = result.get('test_result_japan', 'null')
    
    try:
        italy_float = float(italy_val) if italy_val != 'null' else -1.0
        if 4.4 <= italy_float <= 4.6:
            score += 15
            feedback_parts.append("Function returns correct value for Italy (4.5)")
        elif italy_val != 'null':
            feedback_parts.append(f"Function returned incorrect value for Italy: {italy_val}")
    except ValueError:
        pass

    try:
        japan_float = float(japan_val) if japan_val != 'null' else -1.0
        if 4.9 <= japan_float <= 5.1:
            score += 15
            feedback_parts.append("Function returns correct value for Japan (5.0)")
        elif japan_val != 'null':
            feedback_parts.append(f"Function returned incorrect value for Japan: {japan_val}")
    except ValueError:
        pass

    # 3. Check Output File Existence (15 pts)
    if result.get('output_exists', False):
        if result.get('file_created_during_task', False):
            score += 15
            feedback_parts.append("Output file created during task")
        else:
            score += 5 # Partial credit if it exists but timestamps look weird
            feedback_parts.append("Output file exists but timestamp check failed")
    else:
        feedback_parts.append("Output file NOT found")

    # 4. Check Output File Content (30 pts)
    content = result.get('file_content', '')
    
    # Check Italy=4.5
    if re.search(r"Italy\s*[=:]\s*4\.5", content, re.IGNORECASE):
        score += 15
        feedback_parts.append("File contains correct Italy value")
    else:
        feedback_parts.append("File missing correct Italy entry")
        
    # Check Japan=5.0
    if re.search(r"Japan\s*[=:]\s*5\.0", content, re.IGNORECASE):
        score += 15
        feedback_parts.append("File contains correct Japan value")
    else:
        feedback_parts.append("File missing correct Japan entry")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }