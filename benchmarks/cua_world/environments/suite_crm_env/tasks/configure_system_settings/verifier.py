#!/usr/bin/env python3
"""
Verifier for configure_system_settings task.

Verifies:
1. System Name was updated to "Meridian Wholesale CRM" (30 points)
2. Listview pagination was updated to 50 (30 points)
3. Prevent user customizable layout (lock_homepage) was enabled (20 points)
4. Custom logo was uploaded (timestamp check in export_result.sh) (20 points)

Pass threshold: 80 points (Must get the text/numeric config correct at minimum)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_settings(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_system_name = metadata.get('expected_system_name', "Meridian Wholesale CRM")
    expected_list_entries = int(metadata.get('expected_list_entries', 50))
    expected_lock_homepage = metadata.get('expected_lock_homepage', True)

    # Read the extracted config state
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

    if 'error' in result:
        return {"passed": False, "score": 0, "feedback": f"Configuration extraction failed: {result['error']}"}

    score = 0
    feedback_parts = []

    # Criterion 1: System Name Updated (30 pts)
    actual_system_name = result.get('system_name', '')
    if actual_system_name.strip() == expected_system_name:
        score += 30
        feedback_parts.append("System Name correctly updated")
    else:
        feedback_parts.append(f"System Name mismatch: expected '{expected_system_name}', got '{actual_system_name}'")

    # Criterion 2: Listview Pagination (30 pts)
    # The config might store this as string or int
    actual_list_entries = result.get('list_max_entries_per_page', '')
    try:
        actual_list_entries_int = int(actual_list_entries)
    except (ValueError, TypeError):
        actual_list_entries_int = 0

    if actual_list_entries_int == expected_list_entries:
        score += 30
        feedback_parts.append(f"Listview pagination correctly set to {expected_list_entries}")
    else:
        feedback_parts.append(f"Listview pagination mismatch: expected {expected_list_entries}, got {actual_list_entries}")

    # Criterion 3: Homepage Locked (20 pts)
    actual_lock_homepage = result.get('lock_homepage', False)
    # The config could potentially store this as '1', 'true', or a boolean
    is_locked = actual_lock_homepage in [True, 'true', '1', 1]
    
    if is_locked == expected_lock_homepage:
        score += 20
        feedback_parts.append("Homepage layout correctly locked")
    else:
        feedback_parts.append("Homepage layout lock was not enabled")

    # Criterion 4: Logo Uploaded (20 pts)
    logo_uploaded = result.get('logo_uploaded', False)
    if logo_uploaded:
        score += 20
        feedback_parts.append("Company logo successfully uploaded")
    else:
        feedback_parts.append("No new logo file was detected")

    # Final Evaluation
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }