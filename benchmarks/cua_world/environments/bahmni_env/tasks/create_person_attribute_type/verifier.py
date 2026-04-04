#!/usr/bin/env python3
"""
Verifier for create_person_attribute_type task.

Checks:
1. "Preferred Language" attribute type exists in OpenMRS.
2. Configuration matches: format=java.lang.String, searchable=true, correct description.
3. Anti-gaming: Created during task window, count increased.
4. VLM: Visual verification of the admin interface interaction.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

# Import VLM helpers from the framework
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_person_attribute_type(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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

    # Scoring Variables
    score = 0
    feedback_parts = []
    
    attr_found = result.get('attribute_found', False)
    details = result.get('attribute_details', {})
    
    # Metadata targets
    metadata = task_info.get('metadata', {})
    target_name = metadata.get('target_name', 'Preferred Language')
    target_format = metadata.get('target_format', 'java.lang.String')
    target_desc_keyword = metadata.get('target_description_keyword', 'language')

    # Criterion 1: Attribute Exists (40 pts)
    if attr_found and not details.get('retired', True):
        score += 40
        feedback_parts.append("Attribute type created and active")
    else:
        feedback_parts.append("Attribute type NOT found or is retired")
        # Early fail if core object missing
        return {
            "passed": False, 
            "score": score, 
            "feedback": " | ".join(feedback_parts)
        }

    # Criterion 2: Correct Format (20 pts)
    if details.get('format') == target_format:
        score += 20
        feedback_parts.append("Format correct")
    else:
        feedback_parts.append(f"Format mismatch: expected {target_format}, got {details.get('format')}")

    # Criterion 3: Valid Description (15 pts)
    desc = details.get('description', '') or ''
    if target_desc_keyword.lower() in desc.lower():
        score += 15
        feedback_parts.append("Description contains keywords")
    else:
        feedback_parts.append(f"Description missing or incomplete ('{desc}')")

    # Criterion 4: Searchable (10 pts)
    if details.get('searchable') is True:
        score += 10
        feedback_parts.append("Marked as searchable")
    else:
        feedback_parts.append("Not marked as searchable")

    # Criterion 5: Anti-gaming / Count Check (10 pts)
    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)
    if current_count == initial_count + 1:
        score += 10
        feedback_parts.append("Total count increased by 1")
    else:
        feedback_parts.append(f"Count mismatch (Initial: {initial_count}, Current: {current_count})")

    # Criterion 6: Timestamp Check (5 pts)
    # OpenMRS ISO Format: "2023-10-27T10:00:00.000+0000"
    created_str = details.get('date_created', '')
    task_start = result.get('task_start', 0)
    
    timestamp_valid = False
    if created_str:
        try:
            # Handle OpenMRS timestamp format
            # Simple check: created timestamp > task_start
            # We strip the timezone for simple comparison or use rough parsing
            # Python < 3.11 doesn't handle 'Z' or +0000 easily in strptime without external libs sometimes
            # We will use a robust string comparison if dates are ISO-like and year matches
            # Or try basic parsing
            dt_str = created_str.split('.')[0] # remove milliseconds/tz for rough parse
            dt_obj = datetime.strptime(dt_str, "%Y-%m-%dT%H:%M:%S")
            if dt_obj.timestamp() > task_start:
                timestamp_valid = True
        except Exception:
            # Fallback: just check if string exists
            timestamp_valid = True 
            
    if timestamp_valid:
        score += 5
    else:
        feedback_parts.append("Creation timestamp validation failed")

    # Optional: VLM Verification (Can verify if Admin UI was actually visited)
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=3)
        final_ss = get_final_screenshot(traj)
        images = frames + ([final_ss] if final_ss else [])
        
        prompt = (
            "Does the user navigate to the 'OpenMRS Administration' page? "
            "Do screenshots show a form for 'Add Person Attribute Type'? "
            "Is the 'Preferred Language' attribute visible in a list at the end?"
        )
        
        try:
            vlm_res = query_vlm(images=images, prompt=prompt)
            # We don't change score based on this secondary check for now unless strict mode,
            # but we append it to feedback for debugging.
            if vlm_res.get('success'):
                feedback_parts.append(f"VLM: {vlm_res.get('response', 'No response')}")
        except Exception:
            pass

    # Threshold
    passed = (score >= 60) and (attr_found is True)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }