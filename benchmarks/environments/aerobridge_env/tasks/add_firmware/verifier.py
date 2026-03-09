#!/usr/bin/env python3
"""
Verifier for add_firmware@1 task.
Checks if the firmware record was correctly created in Aerobridge.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_firmware(traj, env_info, task_info):
    """
    Verify that the firmware 4.3.7 was added with correct details.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_version = metadata.get('expected_version', '4.3.7')
    expected_url = metadata.get('expected_url', '')
    expected_hash = metadata.get('expected_hash', '')
    expected_friendly_name = metadata.get('expected_friendly_name', '')
    expected_manufacturer = metadata.get('expected_manufacturer', '')
    expected_is_active = metadata.get('expected_is_active', True)

    # 1. Load result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve task results: {str(e)}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Analyze results
    score = 0
    feedback_parts = []
    
    firmware = result.get('firmware')
    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)

    # Criterion 1: Record Existence (15 points)
    if not firmware:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Firmware version {expected_version} was not found in the system."
        }
    
    score += 15
    feedback_parts.append(f"Firmware record {expected_version} exists (+15)")

    # Criterion 2: Binary URL (15 points)
    actual_url = firmware.get('binary_file_url', '').strip()
    if actual_url == expected_url:
        score += 15
        feedback_parts.append("Binary URL matches (+15)")
    else:
        feedback_parts.append(f"Binary URL mismatch. Expected: ...{expected_url[-20:]}, Got: ...{actual_url[-20:]}")

    # Criterion 3: Binary Hash (15 points)
    actual_hash = firmware.get('binary_file_hash', '').strip()
    if actual_hash == expected_hash:
        score += 15
        feedback_parts.append("Binary hash matches (+15)")
    else:
        feedback_parts.append(f"Binary hash mismatch.")

    # Criterion 4: Manufacturer (20 points)
    # This is critical as it involves correct FK selection
    actual_mfr = firmware.get('manufacturer_name', '').strip()
    if actual_mfr == expected_manufacturer:
        score += 20
        feedback_parts.append(f"Manufacturer '{actual_mfr}' correct (+20)")
    else:
        feedback_parts.append(f"Manufacturer mismatch. Expected: {expected_manufacturer}, Got: {actual_mfr}")

    # Criterion 5: Friendly Name (10 points)
    actual_name = firmware.get('friendly_name', '').strip()
    if actual_name == expected_friendly_name:
        score += 10
        feedback_parts.append("Friendly name matches (+10)")
    else:
        feedback_parts.append(f"Friendly name mismatch. Expected: {expected_friendly_name}, Got: {actual_name}")

    # Criterion 6: Is Active (10 points)
    actual_active = firmware.get('is_active')
    if actual_active == expected_is_active:
        score += 10
        feedback_parts.append(f"Active status correct ({actual_active}) (+10)")
    else:
        feedback_parts.append(f"Active status mismatch.")

    # Criterion 7: Anti-Gaming - Count check (10 points)
    # Ensure count increased by exactly 1 (clean creation)
    if current_count == initial_count + 1:
        score += 10
        feedback_parts.append("Firmware count increased by exactly 1 (+10)")
    elif current_count > initial_count:
        score += 5
        feedback_parts.append(f"Firmware count increased by {current_count - initial_count} (+5)")
    else:
        feedback_parts.append("Warning: Firmware count did not increase.")

    # Criterion 8: Anti-Gaming - Timestamp check (5 points)
    # Created time should be after task start time
    try:
        task_start_str = result.get('task_start_time')
        created_at_str = firmware.get('created_at')
        if task_start_str and created_at_str:
            # Basic ISO format comparison
            if created_at_str > task_start_str:
                score += 5
                feedback_parts.append("Record created during task session (+5)")
    except Exception:
        pass # Ignore parsing errors for timestamp

    # Pass logic
    # Threshold 70: requires record existence + manufacturer + significant data accuracy
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }