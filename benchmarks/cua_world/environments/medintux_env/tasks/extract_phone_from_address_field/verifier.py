#!/usr/bin/env python3
"""
Verifier for extract_phone_from_address_field task.

Checks if phone numbers were correctly moved from Address to Phone field in the database.
"""

import json
import os
import tempfile
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_text(text):
    """Normalize text for comparison (trim whitespace)."""
    if not text:
        return ""
    return text.strip()

def verify_extract_phone(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task metadata
    metadata = task_info.get('metadata', {})
    targets = metadata.get('target_patients', [])
    controls = metadata.get('control_patients', [])

    # Load result from environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    records = result.get('records', {})
    if not records:
        return {"passed": False, "score": 0, "feedback": "No records returned from database check."}

    score = 0
    max_score = 100
    feedback_lines = []
    
    # Weight distribution
    # Extraction: 45 pts (15 pts per target)
    # Cleaning: 45 pts (15 pts per target)
    # Control integrity: 10 pts

    # 1. Verify Target Records
    for target in targets:
        guid = target['guid']
        expected_phone = target['expected_phone']
        expected_addr = target['expected_addr_clean']
        
        record = records.get(guid, {})
        actual_phone = normalize_text(record.get('phone', ''))
        actual_addr = normalize_text(record.get('address', ''))
        
        # Check Phone Extraction
        if actual_phone == expected_phone:
            score += 15
            feedback_lines.append(f"[{guid}] Phone extracted correctly ({actual_phone}).")
        elif actual_phone.replace('.', '').replace(' ', '') == expected_phone:
            # Partial credit if not normalized (e.g. still has dots)
            score += 5
            feedback_lines.append(f"[{guid}] Phone extracted but NOT normalized (expected {expected_phone}, got {actual_phone}).")
        else:
            feedback_lines.append(f"[{guid}] Phone extraction FAILED (expected {expected_phone}, got '{actual_phone}').")

        # Check Address Cleaning
        # We allow some flexibility in whitespace/trimming
        # The key is that the phone number digits and specific markers ("Tel") are gone
        
        # Regex to check if phone digits remain in address (sequence of 4+ digits)
        digits_remain = re.search(r'\d{4,}', actual_addr)
        tel_marker_remains = "Tel" in actual_addr or "tel" in actual_addr
        
        if actual_addr == expected_addr:
            score += 15
            feedback_lines.append(f"[{guid}] Address cleaned perfectly.")
        elif not digits_remain and not tel_marker_remains:
            # If it's not perfect match but digits are gone and no 'Tel' marker
            score += 10
            feedback_lines.append(f"[{guid}] Address mostly cleaned (digits removed), but format differs slightly.")
        else:
            feedback_lines.append(f"[{guid}] Address cleaning FAILED (digits or 'Tel' marker remain: '{actual_addr}').")

    # 2. Verify Control Record
    for control in controls:
        guid = control['guid']
        initial_addr = control['initial_addr']
        initial_phone = control['initial_phone']
        
        record = records.get(guid, {})
        actual_phone = normalize_text(record.get('phone', ''))
        actual_addr = normalize_text(record.get('address', ''))
        
        if actual_phone == initial_phone and actual_addr == initial_addr:
            score += 10
            feedback_lines.append(f"[Control {guid}] Record correctly preserved.")
        else:
            feedback_lines.append(f"[Control {guid}] Record was MODIFIED incorrectly (addr: '{actual_addr}', phone: '{actual_phone}').")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines)
    }