#!/usr/bin/env python3
"""
Verifier for update_downstream_dependencies task.

Verifies that:
1. SRS-12 text was updated to contain "500ms"
2. SRS-12 text no longer contains "2 seconds"
3. A comment referencing "CR-105" was added to SRS-12
4. The project was saved (file modified)
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants
PROJECT_DIR_NAME = "update_dependencies_project"
SRS_REL_PATH = f"documents/SRS.json"
TARGET_SRS_ID = "12"  # Just the ID part, ReqView stores it as "12", UI shows "SRS-12"

def _find_req_by_id(data, req_id):
    """Recursively find requirement by ID in the data tree."""
    for item in data:
        if str(item.get('id')) == str(req_id):
            return item
        if 'children' in item:
            found = _find_req_by_id(item['children'], req_id)
            if found:
                return found
    return None

def _strip_html(text):
    """Simple regex to strip HTML tags."""
    if not text: return ""
    return re.sub(r'<[^>]+>', '', text)

def verify_update_downstream_dependencies(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # 1. Retrieve SRS.json
    srs_path_in_env = f"/home/ga/Documents/ReqView/{PROJECT_DIR_NAME}/{SRS_REL_PATH}"
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(srs_path_in_env, temp_file.name)
        with open(temp_file.name, 'r') as f:
            srs_data = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Could not read project data. Did you save the project? Error: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Retrieve Task Result Metadata (check for save timestamp)
    task_result = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except:
        pass # Not critical, used for timestamp check
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []

    # --- Verification Logic ---
    
    # 0. Check if saved
    if task_result.get('srs_modified', False):
        score += 10
        feedback.append("Project saved successfully.")
    else:
        feedback.append("Project NOT saved (changes not persisted).")

    # Find SRS-12
    req = _find_req_by_id(srs_data.get('data', []), TARGET_SRS_ID)
    if not req:
        return {
            "passed": False, 
            "score": score, 
            "feedback": f"Critical: SRS-{TARGET_SRS_ID} not found in project data."
        }
    
    text = _strip_html(req.get('text', '')).lower()
    
    # 1. Check for "500ms" or "500 milliseconds" (40 pts)
    if "500ms" in text or "500 milliseconds" in text or "500 ms" in text:
        score += 40
        feedback.append("Requirement text updated with new value (500ms).")
    else:
        feedback.append(f"Requirement text missing '500ms'. Current text: '{text[:50]}...'")

    # 2. Check for absence of "2 seconds" (20 pts)
    if "2 seconds" not in text and "2000ms" not in text:
        score += 20
        feedback.append("Old value (2 seconds) removed.")
    else:
        feedback.append("Old value (2 seconds) still present in text.")

    # 3. Check for Comment (30 pts)
    # Comments are typically stored in the 'discussion' or 'comments' field of the object
    # In ReqView JSON, comments are often in a 'discussion' array
    comments = req.get('discussion', [])
    comment_found = False
    for c in comments:
        c_text = _strip_html(c.get('text', '')).lower()
        if "cr-105" in c_text:
            comment_found = True
            break
    
    if comment_found:
        score += 30
        feedback.append("Comment 'CR-105' added.")
    else:
        feedback.append("No comment referencing 'CR-105' found on the requirement.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }