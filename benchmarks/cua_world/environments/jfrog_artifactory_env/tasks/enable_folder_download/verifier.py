#!/usr/bin/env python3
"""
Verifier for enable_folder_download task.

Criteria:
1. Artifactory Configuration:
   - folderDownloadEnabled must be "true"
   - maxFolderDownloadSizeMbytes must be 500
2. Data Retrieval:
   - File ~/Desktop/commons-io-package.zip must exist
   - Must be a valid ZIP
   - Must contain commons-io-2.15.1.jar
   - Must be created during the task window
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enable_folder_download(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load results
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
    
    # 1. Configuration Check (40 points)
    config_enabled = str(result.get('config_folder_download_enabled', '')).lower() == 'true'
    
    # Handle int or str for max size
    try:
        max_size = int(result.get('config_max_size', -1))
    except (ValueError, TypeError):
        max_size = -1
        
    if config_enabled:
        score += 20
        feedback_parts.append("Folder Download enabled")
    else:
        feedback_parts.append("Folder Download NOT enabled")
        
    if max_size == 500:
        score += 20
        feedback_parts.append("Max Size set to 500MB")
    else:
        feedback_parts.append(f"Max Size incorrect (found {max_size}, expected 500)")

    # 2. File Check (60 points)
    zip_exists = result.get('zip_exists', False)
    zip_valid = result.get('zip_valid', False)
    zip_contains_jar = result.get('zip_contains_jar', False)
    
    # Anti-gaming: Check timestamp
    task_start = result.get('task_start', 0)
    zip_mtime = result.get('zip_mtime', 0)
    created_during_task = zip_mtime > task_start

    if zip_exists:
        if created_during_task:
            score += 20
            feedback_parts.append("Zip file created")
            
            if zip_valid:
                score += 20
                feedback_parts.append("Zip file valid")
                
                if zip_contains_jar:
                    score += 20
                    feedback_parts.append("Zip contains correct artifacts")
                else:
                    feedback_parts.append("Zip missing expected JAR")
            else:
                feedback_parts.append("Zip file corrupted/invalid")
        else:
            feedback_parts.append("Zip file exists but looks old (pre-dated task)")
    else:
        feedback_parts.append("No output Zip file found")

    # Final Pass Decision
    # Need at least config enabled + valid zip download to pass
    passed = (config_enabled and zip_valid and max_size == 500)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }