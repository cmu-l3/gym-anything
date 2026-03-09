#!/usr/bin/env python3
"""
Verifier for shrinkwrap_decal_application task.

Criteria:
1. File saved and valid (15 pts)
2. WarningLabel has Shrinkwrap modifier (30 pts)
3. Modifier targets IndustrialPipe (30 pts)
4. Offset is between 0.005 and 0.02 (25 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_shrinkwrap_decal(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Check File Existence (15 pts)
    if result.get("output_exists") and result.get("file_modified"):
        score += 15
        feedback.append("File saved successfully.")
    else:
        feedback.append("File not saved or not modified.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    analysis = result.get("analysis", {})
    
    # 2. Check Modifier Existence (30 pts)
    if analysis.get("has_shrinkwrap"):
        score += 30
        feedback.append("Shrinkwrap modifier found.")
    else:
        feedback.append("No Shrinkwrap modifier found on WarningLabel.")
    
    # 3. Check Target (30 pts)
    if analysis.get("target_correct"):
        score += 30
        feedback.append("Target set to IndustrialPipe.")
    else:
        feedback.append("Modifier target is incorrect or missing.")

    # 4. Check Offset (25 pts)
    offset = analysis.get("offset", 0)
    min_off = task_info.get("metadata", {}).get("min_offset", 0.005)
    max_off = task_info.get("metadata", {}).get("max_offset", 0.02)
    
    if min_off <= offset <= max_off:
        score += 25
        feedback.append(f"Offset ({offset:.4f}) is within valid range.")
    else:
        feedback.append(f"Offset ({offset:.4f}) is outside range [{min_off}, {max_off}].")

    return {
        "passed": score >= 85,
        "score": score,
        "feedback": " ".join(feedback),
        "details": analysis
    }