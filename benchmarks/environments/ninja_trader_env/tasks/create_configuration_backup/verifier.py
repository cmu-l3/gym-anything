#!/usr/bin/env python3
"""
Verifier for create_configuration_backup task.

This verifier checks:
1. That the backup ZIP file exists and was created during the task.
2. That the ZIP contains the required folders (workspaces, templates).
3. That the ZIP does NOT contain forbidden heavy folders (db, log, trace).
"""

import json
import zipfile
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_configuration_backup(traj, env_info, task_info):
    """
    Verifies the contents of the NinjaTrader configuration backup zip file.
    """
    # Use copy_from_env to safely retrieve files from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    # Define container paths (Windows paths)
    container_result_path = "C:/Users/Docker/AppData/Local/Temp/task_result.json"
    container_backup_path = "C:/Users/Docker/Desktop/NinjaTraderTasks/config_backup.zip"
    
    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # Step 1: Check metadata from export script (Existence & Timing)
    # ---------------------------------------------------------
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        try:
            copy_from_env(container_result_path, temp_json.name)
            with open(temp_json.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Failed to retrieve task result JSON: {e}"
            }
            
        if not result.get('file_exists'):
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Backup file 'config_backup.zip' was not found in the expected directory."
            }
            
        if not result.get('file_created_during_task'):
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "File exists but was not created during this task session (stale file)."
            }
            
        # If we get here, the file exists and is new
        score += 30
        feedback_parts.append("Backup file created successfully (+30)")
        
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # ---------------------------------------------------------
    # Step 2: Inspect ZIP contents (Content Verification)
    # ---------------------------------------------------------
    temp_zip = tempfile.NamedTemporaryFile(delete=False, suffix='.zip')
    try:
        try:
            copy_from_env(container_backup_path, temp_zip.name)
        except Exception as e:
            return {
                "passed": False, 
                "score": score, 
                "feedback": f"Failed to copy backup file for inspection: {e}"
            }
        
        if not zipfile.is_zipfile(temp_zip.name):
            return {
                "passed": False, 
                "score": score, 
                "feedback": "The output file is not a valid ZIP archive."
            }
            
        with zipfile.ZipFile(temp_zip.name, 'r') as zf:
            file_list = zf.namelist()
            
            # Normalize paths for case-insensitive check
            files = [f.lower().replace('\\', '/') for f in file_list]
            
            # Criterion: Required Folders
            has_templates = any('templates/' in f for f in files)
            has_workspaces = any('workspaces/' in f for f in files)
            
            if has_templates:
                score += 20
                feedback_parts.append("Templates included (+20)")
            else:
                feedback_parts.append("MISSING: Templates folder")
                
            if has_workspaces:
                score += 20
                feedback_parts.append("Workspaces included (+20)")
            else:
                feedback_parts.append("MISSING: Workspaces folder")
                
            # Criterion: Forbidden Folders (Database, Logs)
            # We want to ensure the agent UNCHECKED these heavy items
            forbidden_items = []
            if any('db/' in f for f in files):
                forbidden_items.append("Database")
            if any('log/' in f for f in files):
                forbidden_items.append("Log Files")
            if any('trace/' in f for f in files):
                forbidden_items.append("Trace Files")
            if any('ninjascript/' in f for f in files):
                forbidden_items.append("NinjaScript")
                
            if not forbidden_items:
                score += 30
                feedback_parts.append("Correctly excluded heavy data files (+30)")
            else:
                feedback_parts.append(f"FAILED: Backup includes excluded items: {', '.join(forbidden_items)}")
                
    except Exception as e:
        return {
            "passed": False, 
            "score": score, 
            "feedback": f"Error inspecting ZIP file: {e}"
        }
    finally:
        if os.path.exists(temp_zip.name):
            os.unlink(temp_zip.name)

    # ---------------------------------------------------------
    # Final Scoring
    # ---------------------------------------------------------
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }