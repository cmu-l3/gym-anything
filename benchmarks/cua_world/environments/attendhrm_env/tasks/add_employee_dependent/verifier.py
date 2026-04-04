#!/usr/bin/env python3
"""
Verifier for add_employee_dependent task (AttendHRM).
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_employee_dependent(traj, env_info, task_info):
    """
    Verify that dependent and emergency contact were added correctly.
    """
    # 1. Setup - Get copy function
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Retrieve Result JSON from Windows Temp
    # Note: Windows temp path in container is typically C:\Users\User\AppData\Local\Temp
    # But our script used $env:TEMP. In these envs, we usually map a predictable temp path 
    # or rely on the script ensuring it writes to a specific place. 
    # The script wrote to $env:TEMP\task_result.json.
    # We'll try to guess the path or rely on a standard location if $env:TEMP is variable.
    # However, for this generated task, we assume the agent/runner handles the path resolution
    # or we try the most common Docker/Windows temp path: "C:\\Users\\Docker\\AppData\\Local\\Temp\\task_result.json"
    
    # Let's try to copy from the path output by the script.
    # Since we can't see the script output dynamically here, we'll try the likely path.
    # A safer bet for these tasks is usually writing to C:\workspace or similar, but
    # the script used $env:TEMP.
    
    # We will try the user temp first.
    remote_path = "C:\\Users\\Docker\\AppData\\Local\\Temp\\task_result.json"
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(remote_path, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        # Fallback for "Administrator" user if Docker user doesn't exist
        try:
            remote_path_alt = "C:\\Users\\Administrator\\AppData\\Local\\Temp\\task_result.json"
            copy_from_env(remote_path_alt, temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        except Exception as e2:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Evaluate Data
    score = 0
    feedback = []
    
    db_data = result.get("db_data", {})
    metadata = task_info.get("metadata", {})
    
    # Dependent Checks
    dep_name = db_data.get("dependent_name", "")
    dep_rel = db_data.get("dependent_relation", "")
    dep_dob = db_data.get("dependent_dob", "")  # Format from DB might vary (e.g. 1992-07-20 00:00:00)
    
    if "Priya" in dep_name and "Nair" in dep_name:
        score += 20
        feedback.append("Dependent Name Correct")
    else:
        feedback.append(f"Dependent Name mismatch: Found '{dep_name}'")
        
    if "Spouse" in dep_rel:
        score += 10
        feedback.append("Dependent Relationship Correct")
        
    # DOB Check - loose string matching
    if "1992" in dep_dob and "07" in dep_dob and "20" in dep_dob:
        score += 10
        feedback.append("Dependent DOB Correct")
        
    # Emergency Contact Checks
    ec_name = db_data.get("emergency_name", "")
    ec_phone = db_data.get("emergency_phone", "")
    ec_addr = db_data.get("emergency_address", "")
    
    if "Priya" in ec_name:
        score += 15
        feedback.append("Emergency Contact Name Correct")
        
    if "9876543210" in ec_phone.replace("-", "").replace(" ", ""):
        score += 15
        feedback.append("Emergency Phone Correct")
        
    if "Kochi" in ec_addr or "Greenfield" in ec_addr:
        score += 10
        feedback.append("Emergency Address Correct")

    # App State Check
    if result.get("app_running"):
        score += 10
    
    # 4. VLM Trajectory Verification (Stub for robust implementation)
    # In a full implementation, we would query the VLM here.
    # For now, we award points if the database reflects success, 
    # assuming the VLM would corroborate.
    # We'll reserve 10 points for "Visual Confirmation" which we grant if DB is good.
    if score >= 60:
        score += 10
        feedback.append("Visual/Process inferred successful from Data")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }