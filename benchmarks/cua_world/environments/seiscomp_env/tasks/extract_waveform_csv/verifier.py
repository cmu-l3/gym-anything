#!/usr/bin/env python3
"""
Verifier for the Extract Waveform Data to CSV task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_extract_waveform_csv(traj, env_info, task_info):
    """
    Verify the CSV extraction was performed correctly.
    
    Checks:
    1. CSV file exists and was created during the task
    2. Python script was created (evidence of programmatic access)
    3. Correct CSV format and exact headers
    4. Row count corresponds to ~60 seconds of seismic data (>=600 rows)
    5. Starting timestamp matches the requested target start time
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_headers = metadata.get('expected_headers', ["Time_UTC", "Amplitude_Counts"])
    
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
    
    # 1. Output Existence (15 points)
    if not result.get("output_exists"):
        return {"passed": False, "score": 0, "feedback": "Failure: 'toli_waveform.csv' was not found."}
    score += 15
    feedback_parts.append("CSV file exists")

    # 2. Anti-gaming / Creation check (10 points)
    if result.get("file_created_during_task"):
        score += 10
        feedback_parts.append("File newly created")
    else:
        feedback_parts.append("File modified timestamp predates task start (gaming attempt?)")
        
    # 3. Process Check: Script created (10 points)
    if result.get("script_created"):
        score += 10
        feedback_parts.append("Python script created")
    else:
        feedback_parts.append("No Python script found in home directory")

    # 4. Valid CSV format (15 points)
    if not result.get("valid_csv"):
        feedback_parts.append(f"Invalid CSV format: {result.get('error')}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
    score += 15
    
    # 5. Header Check (15 points)
    actual_headers = result.get("headers", [])
    if len(actual_headers) == 2 and actual_headers[0] == expected_headers[0] and actual_headers[1] == expected_headers[1]:
        score += 15
        feedback_parts.append("Exact headers match")
    elif any(expected_headers[0].lower() in h.lower() for h in actual_headers):
        # Partial credit for roughly correct headers
        score += 5
        feedback_parts.append(f"Headers approximate: {actual_headers}")
    else:
        feedback_parts.append(f"Incorrect headers: {actual_headers}")
        
    # 6. Data Volume / Row count (20 points)
    # 60s @ 20Hz = 1200 rows. Allow some buffer.
    row_count = result.get("row_count", 0)
    if row_count >= 600 and row_count <= 3000:
        score += 20
        feedback_parts.append(f"Correct data volume ({row_count} rows)")
    elif row_count > 0:
        score += 5
        feedback_parts.append(f"Insufficient or excessive data volume ({row_count} rows)")
    else:
        feedback_parts.append("CSV contains no data rows")

    # 7. Start time Verification (15 points)
    first_time = result.get("first_time", "")
    # Check if string contains the target date and minute
    if "2024-01-01" in first_time and ("07:10" in first_time or "07:11" in first_time):
        score += 15
        feedback_parts.append("Start time matches 2024-01-01 07:10:XX")
    else:
        feedback_parts.append(f"Incorrect start time window: {first_time}")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }