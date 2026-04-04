#!/usr/bin/env python3
"""
Verifier for export_employee_host_list task.

Checks:
1. File exists at expected location.
2. File was created during the task window.
3. File is a valid text/CSV file (not empty).
4. File contains expected data (employee names known to be in the system).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_employee_host_list(traj, env_info, task_info):
    """
    Verify the employee host list export.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_content = metadata.get('required_content', ["Wilson", "Thompson", "Chang"])
    min_size = metadata.get('min_file_size_bytes', 50)

    # Load result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []
    
    # Criterion 1: File Created (30 pts)
    if result.get('output_exists', False):
        score += 30
        feedback_parts.append("File created")
    else:
        feedback_parts.append("File not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Fresh Export (10 pts)
    if result.get('file_created_during_task', False):
        score += 10
        feedback_parts.append("File timestamp valid")
    else:
        feedback_parts.append("File is old (pre-existing)")

    # Criterion 3: Valid Format/Size (20 pts)
    size = result.get('output_size_bytes', 0)
    if size >= min_size:
        score += 20
        feedback_parts.append(f"File size ok ({size} bytes)")
    else:
        feedback_parts.append(f"File too small ({size} bytes)")

    # Criterion 4: Data Presence (40 pts)
    content_sample = result.get('content_sample', "")
    found_terms = 0
    for term in required_content:
        if term in content_sample:
            found_terms += 1
    
    # Calculate content score proportionally
    if len(required_content) > 0:
        content_score = int((found_terms / len(required_content)) * 40)
        score += content_score
        feedback_parts.append(f"Found {found_terms}/{len(required_content)} expected terms")
    else:
        score += 40 # No specific content required

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }