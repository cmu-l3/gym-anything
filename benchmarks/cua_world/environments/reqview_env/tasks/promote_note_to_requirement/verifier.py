#!/usr/bin/env python3
"""
Verifier for promote_note_to_requirement task.

Criteria:
1. SRS.json must be modified after task start.
2. The object containing the target text ("encrypted at rest...") must be found.
3. This object must now have a valid 'id' (it was injected without one).
4. This object must have 'type' set to 'Constraint'.
"""

import json
import os
import sys
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_promote_note(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    target_substring = metadata.get('target_text_substring', "encrypted at rest using AES-256")
    expected_type = metadata.get('expected_type', "Constraint")
    project_dir_name = metadata.get('project_dir', "promote_note_project")
    
    srs_path = f"/home/ga/Documents/ReqView/{project_dir_name}/documents/SRS.json"

    # 1. Get the export result to check timestamps
    task_result = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load task_result.json: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Get the SRS file
    temp_srs = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    srs_data = {}
    try:
        copy_from_env(srs_path, temp_srs.name)
        with open(temp_srs.name, 'r') as f:
            srs_data = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve SRS.json. Did you save the project? Error: {e}"
        }
    finally:
        if os.path.exists(temp_srs.name):
            os.unlink(temp_srs.name)

    # 3. Analyze logic
    score = 0
    feedback = []
    
    # Criterion 1: File Modified (10 pts)
    if task_result.get("srs_modified", False):
        score += 10
        feedback.append("Project saved successfully.")
    else:
        feedback.append("Project file not modified (did you save?).")

    # Helper to find object
    def find_object_by_text(items, substring):
        for item in items:
            # Check text (strip HTML)
            raw_text = item.get('text', '')
            clean_text = re.sub(r'<[^>]+>', '', raw_text)
            
            if substring in clean_text or substring in raw_text:
                return item
            
            if 'children' in item:
                found = find_object_by_text(item['children'], substring)
                if found:
                    return found
        return None

    target_obj = find_object_by_text(srs_data.get('data', []), target_substring)

    # Criterion 2: Object Found (20 pts)
    if target_obj:
        score += 20
        feedback.append("Target text found in document.")
        
        # Criterion 3: Object has ID (40 pts)
        # In setup, we ensured it had NO id. Now it must have one.
        obj_id = target_obj.get('id')
        if obj_id and str(obj_id).strip():
            score += 40
            feedback.append(f"Object successfully promoted to Requirement (ID: {obj_id}).")
            
            # Criterion 4: Type is Constraint (30 pts)
            # ReqView types are usually stored in 'type' field, sometimes capitalized differently
            obj_type = target_obj.get('type', '')
            if obj_type.lower() == expected_type.lower():
                score += 30
                feedback.append(f"Attribute 'Type' correctly set to '{obj_type}'.")
            else:
                feedback.append(f"Incorrect Type. Expected '{expected_type}', got '{obj_type}'.")
        else:
            feedback.append("Object still lacks an ID (it is still a Note/Text object).")
    else:
        feedback.append(f"Could not find object containing text '{target_substring}'.")

    # Final scoring
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }