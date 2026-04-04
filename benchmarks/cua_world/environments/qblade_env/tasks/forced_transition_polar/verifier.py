#!/usr/bin/env python3
"""
Verifier for forced_transition_polar task in QBlade.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_forced_transition_polar(traj, env_info, task_info):
    """
    Verifies that the agent configured XFoil with forced transition parameters
    and saved the project.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_re = metadata.get('target_re', 1000000)
    target_xtr_top = metadata.get('target_xtr_top', 0.05)
    target_xtr_bot = metadata.get('target_xtr_bot', 0.10)
    
    # Retrieve result from container
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
    
    # 1. File Existence & Validity (20 pts)
    if result.get('output_exists') and result.get('file_created_during_task'):
        score += 20
        feedback_parts.append("Project file created successfully")
    elif result.get('output_exists'):
        score += 10
        feedback_parts.append("Project file exists but timestamp check failed")
    else:
        feedback_parts.append("Project file not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Content Checks
    
    # Airfoil (15 pts)
    if result.get('airfoil_found'):
        score += 15
        feedback_parts.append("NACA 0012 airfoil confirmed")
    else:
        feedback_parts.append("NACA 0012 airfoil not found in project")

    # Transition Parameters (30 pts - CRITICAL)
    # Check Xtr Top
    xtr_top = result.get('xtr_top', 1.0)
    if abs(xtr_top - target_xtr_top) < 0.01:
        score += 15
        feedback_parts.append(f"Top transition correct ({xtr_top})")
    else:
        feedback_parts.append(f"Top transition incorrect (found {xtr_top}, expected {target_xtr_top})")

    # Check Xtr Bot
    xtr_bot = result.get('xtr_bot', 1.0)
    if abs(xtr_bot - target_xtr_bot) < 0.01:
        score += 15
        feedback_parts.append(f"Bottom transition correct ({xtr_bot})")
    else:
        feedback_parts.append(f"Bottom transition incorrect (found {xtr_bot}, expected {target_xtr_bot})")

    # Reynolds Number (10 pts)
    reynolds = result.get('reynolds_num', 0)
    if abs(reynolds - target_re) < 100000: # 10% tolerance
        score += 10
        feedback_parts.append(f"Reynolds number correct ({int(reynolds)})")
    else:
        feedback_parts.append(f"Reynolds number incorrect or missing ({int(reynolds)})")

    # Polar Data (15 pts)
    data_points = result.get('data_points', 0)
    if data_points >= 20:
        score += 15
        feedback_parts.append(f"Polar data generated ({data_points} points)")
    elif data_points > 5:
        score += 5
        feedback_parts.append(f"Incomplete polar data ({data_points} points)")
    else:
        feedback_parts.append("No significant polar data found")
        
    # 3. Application State (10 pts)
    if result.get('app_was_running'):
        score += 10
    else:
        feedback_parts.append("QBlade was not running at end of task")

    # Check for passing
    # Must have file, correct transition params to pass
    transition_ok = (abs(xtr_top - target_xtr_top) < 0.01) and (abs(xtr_bot - target_xtr_bot) < 0.01)
    file_ok = result.get('output_exists') and result.get('file_created_during_task')
    
    passed = file_ok and transition_ok and score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }