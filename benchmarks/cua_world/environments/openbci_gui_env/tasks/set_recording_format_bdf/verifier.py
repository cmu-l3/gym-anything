#!/usr/bin/env python3
"""
Verifier for set_recording_format_bdf task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_set_recording_format_bdf(traj, env_info, task_info):
    """
    Verify that the user configured OpenBCI GUI to record in BDF+ format
    and successfully recorded data.
    """
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

    score = 0
    feedback_parts = []
    
    # Metadata targets
    min_size = task_info.get('metadata', {}).get('min_file_size_bytes', 10240)

    # 1. BDF File Existence (30 pts)
    if result.get('bdf_file_found', False):
        score += 30
        feedback_parts.append("BDF file created")
    else:
        feedback_parts.append("No new BDF file found")

    # 2. Valid Header (30 pts)
    # This proves it's actually a BDF file, not just a renamed text file
    if result.get('bdf_header_valid', False):
        score += 30
        feedback_parts.append("Valid BDF+ header detected")
    elif result.get('bdf_file_found', False):
        feedback_parts.append("Invalid BDF header (file content incorrect)")

    # 3. File Size / Data Duration (20 pts)
    size = result.get('bdf_file_size_bytes', 0)
    if size > min_size:
        score += 20
        feedback_parts.append(f"Sufficient data recorded ({size} bytes)")
    elif size > 0:
        score += 10
        feedback_parts.append(f"File too small ({size} bytes), verify recording duration")
    else:
        feedback_parts.append("File is empty")

    # 4. No Default Format Recording (10 pts)
    # If a TXT recording exists, they might have recorded BEFORE changing format
    # or failed to change format. We deduct if ONLY txt exists, but here we reward purity.
    if not result.get('txt_recording_found', False):
        score += 10
        feedback_parts.append("No default text recordings found (clean workflow)")
    else:
        feedback_parts.append("Warning: Default .txt recordings also found")

    # 5. App Running (10 pts)
    if result.get('app_was_running', False):
        score += 10
        feedback_parts.append("Application remained open")
    else:
        feedback_parts.append("Application was closed")

    # Pass Criteria
    # Must have valid BDF file with sufficient size
    passed = result.get('bdf_header_valid', False) and (size > min_size) and score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }