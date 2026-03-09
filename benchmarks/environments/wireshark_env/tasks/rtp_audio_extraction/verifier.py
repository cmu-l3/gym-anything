#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rtp_audio_extraction(traj, env_info, task_info):
    """
    Verifies that the agent successfully extracted audio from the RTP stream.
    
    Scoring Criteria:
    1. Output file exists (30 pts)
    2. File was created during the task session (20 pts)
    3. File is a valid audio format (Sun .au or similar) (20 pts)
    4. File size indicates successful payload extraction (> 50KB) (30 pts)
    """
    
    # 1. Setup: Retrieve result from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification results: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Evaluate Criteria
    score = 0
    feedback = []
    
    # Criterion 1: File Exists
    if result.get("file_exists", False):
        score += 30
        feedback.append("Success: Output file 'recovered_call.au' found.")
    else:
        feedback.append("Fail: Output file 'recovered_call.au' not found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Criterion 2: Anti-Gaming (Timestamp)
    if result.get("created_during_task", False):
        score += 20
        feedback.append("Success: File created during task session.")
    else:
        feedback.append("Fail: File timestamp predates task start (stale file).")

    # Criterion 3: File Format
    # Wireshark RTP player usually exports Sun/NeXT audio
    file_type = result.get("file_type_output", "").lower()
    if "audio" in file_type or "sun" in file_type or "snd" in file_type:
        score += 20
        feedback.append(f"Success: Valid audio file format detected ({file_type}).")
    else:
        feedback.append(f"Warning: Unexpected file format: '{file_type}'. Expecting Sun/NeXT audio.")
        # Partial credit if it exists but type is weird? No, likely wrong export.
    
    # Criterion 4: File Size (Content Integrity)
    # The sample capture produces ~100KB-300KB depending on if forward/reverse/both are saved.
    # < 1KB implies empty file.
    size = result.get("file_size_bytes", 0)
    if size > 50000: # > 50KB
        score += 30
        feedback.append(f"Success: File size ({size} bytes) indicates successful audio extraction.")
    elif size > 1000:
        score += 10
        feedback.append(f"Partial: File size ({size} bytes) is smaller than expected for full conversation.")
    else:
        feedback.append(f"Fail: File is too small ({size} bytes) to contain audio.")

    # 3. Final Result
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }