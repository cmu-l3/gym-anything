#!/usr/bin/env python3
"""
Verifier for Create Appointment Type task in Oscar EMR.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_appointment_type(traj, env_info, task_info):
    """
    Verify that the 'Mental Health Intake' appointment type was created correctly.
    
    Criteria:
    1. Record exists (40 pts)
    2. Duration is 45 minutes (30 pts)
    3. Color is Red/#FF0000 (30 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', 'Mental Health Intake')
    expected_duration = str(metadata.get('expected_duration', '45'))
    
    # Allow loose matching for color (Hex or Name)
    expected_color_hex = metadata.get('expected_color_hex', '#FF0000').lower()
    expected_color_name = metadata.get('expected_color_name', 'Red').lower()

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    record_found = result.get('record_found', False)
    record = result.get('record', {})
    
    # Criterion 1: Record Exists
    if record_found:
        score += 40
        feedback_parts.append(f"Appointment type '{expected_name}' created")
    else:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Appointment type '{expected_name}' NOT found in database"
        }

    # Criterion 2: Check Duration
    actual_duration = str(record.get('duration', '0')).strip()
    if actual_duration == expected_duration:
        score += 30
        feedback_parts.append(f"Duration correct ({actual_duration} min)")
    else:
        feedback_parts.append(f"Duration incorrect (Expected: {expected_duration}, Got: {actual_duration})")

    # Criterion 3: Check Color
    actual_color = str(record.get('color', '')).strip().lower()
    # Normalize hex if present (remove #)
    actual_color_clean = actual_color.lstrip('#')
    expected_hex_clean = expected_color_hex.lstrip('#')
    
    if actual_color == expected_color_name or actual_color_clean == expected_hex_clean:
        score += 30
        feedback_parts.append(f"Color correct ({record.get('color')})")
    else:
        feedback_parts.append(f"Color incorrect (Expected: Red/{expected_color_hex}, Got: {record.get('color')})")

    passed = score >= 100
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }