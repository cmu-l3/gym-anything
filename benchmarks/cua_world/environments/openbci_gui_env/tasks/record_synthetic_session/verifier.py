#!/usr/bin/env python3
"""
Verifier for record_synthetic_session task.

Validates that:
1. A new recording session directory was created.
2. A valid OpenBCI raw data file exists.
3. The file contains sufficient data for >10 seconds of recording.
4. The file format (header, columns) is correct.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_synthetic_session(traj, env_info, task_info):
    """
    Verify the agent recorded a valid synthetic session.
    """
    # 1. Setup: Get copy capability
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verification failed: copy_from_env not available"}

    # 2. Get thresholds from metadata
    metadata = task_info.get('metadata', {})
    min_duration_sec = metadata.get('min_duration_seconds', 10)
    # Approx 250Hz sample rate * 10 seconds = 2500 samples.
    # We allow some slack for header lines and timing variance.
    min_lines = metadata.get('min_data_rows', 2000) 
    min_size_kb = metadata.get('min_file_size_kb', 50)

    # 3. Retrieve result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 4. Evaluate Criteria
    score = 0
    feedback_parts = []
    
    # Criterion A: Session Directory Created (15 pts)
    if result.get('session_dir_found', False):
        score += 15
        feedback_parts.append("New session directory created.")
    else:
        feedback_parts.append("No new session directory found.")
        return {"passed": False, "score": 0, "feedback": "Did not create a recording session."}

    # Criterion B: Raw File Exists (15 pts)
    if result.get('raw_file_found', False):
        score += 15
        feedback_parts.append("Raw data file found.")
    else:
        feedback_parts.append("Session directory empty/no raw file.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Criterion C: Valid Header (15 pts)
    if result.get('has_valid_header', False):
        score += 15
        feedback_parts.append("Valid OpenBCI header detected.")
    else:
        feedback_parts.append("File missing valid OpenBCI header.")

    # Criterion D: Valid Columns (10 pts)
    if result.get('has_valid_columns', False):
        score += 10
        feedback_parts.append("Data columns format correct.")
    else:
        feedback_parts.append("Data format incorrect (wrong column count).")

    # Criterion E: File Size (15 pts)
    size_kb = result.get('file_size_bytes', 0) / 1024
    if size_kb >= min_size_kb:
        score += 15
        feedback_parts.append(f"File size adequate ({size_kb:.1f} KB).")
    else:
        feedback_parts.append(f"File too small ({size_kb:.1f} KB < {min_size_kb} KB).")

    # Criterion F: Data Duration / Line Count (20 pts)
    lines = result.get('total_lines', 0)
    # Calculate approx duration assuming 250Hz and ~5 lines of header
    approx_sec = (lines - 5) / 250.0
    
    if lines >= min_lines:
        score += 20
        feedback_parts.append(f"Recording duration sufficient (~{approx_sec:.1f}s).")
    elif lines > 100:
        # Partial credit for short recording
        score += 5
        feedback_parts.append(f"Recording too short (~{approx_sec:.1f}s < {min_duration_sec}s).")
    else:
        feedback_parts.append("File contains almost no data.")

    # Criterion G: Timestamp/App State (10 pts)
    # Implicitly checked by export script finding file AFTER task start, 
    # but we add points for cleanliness and app state.
    if result.get('app_running', False):
        score += 10
        feedback_parts.append("Application remained running.")

    # 5. Final Result
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }