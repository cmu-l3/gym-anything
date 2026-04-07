#!/usr/bin/env python3
"""
Verifier for export_incident_evidence task.
Checks if the agent exported the correct video clip and generated a valid hash.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_incident_evidence(traj, env_info, task_info):
    """
    Verify the exported video evidence and hash.
    
    Criteria:
    1. Video file exists and is valid MKV (20 pts)
    2. Video file was created during the task (10 pts)
    3. Hash file exists (10 pts)
    4. Hash in file matches the actual video file hash (25 pts)
    5. Video duration matches the requested ticket duration +/- tolerance (20 pts)
    6. Video resolution indicates it's from the camera stream (not empty/black) (15 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    tolerance_sec = metadata.get('duration_tolerance_sec', 5.0)

    # Retrieve result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    video_info = result.get("video_file", {})
    hash_info = result.get("hash_file", {})
    expected_duration = result.get("expected_duration_sec", 30)

    # 1. Video File Existence (20 pts)
    if video_info.get("exists"):
        score += 20
        feedback_parts.append("Video file created")
    else:
        feedback_parts.append("Video file missing")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Created During Task (10 pts)
    if video_info.get("created_during_task"):
        score += 10
    else:
        feedback_parts.append("Video file timestamp predates task")

    # 3. Hash File Existence (10 pts)
    if hash_info.get("exists"):
        score += 10
        feedback_parts.append("Hash file created")
    else:
        feedback_parts.append("Hash file missing")

    # 4. Hash Validity (25 pts)
    actual_hash = video_info.get("actual_sha256", "").strip().lower()
    agent_hash = hash_info.get("content_hash", "").strip().lower()
    
    if actual_hash and agent_hash and actual_hash == agent_hash:
        score += 25
        feedback_parts.append("Checksum is valid")
    elif hash_info.get("exists"):
        feedback_parts.append(f"Checksum mismatch (Actual: {actual_hash[:8]}... Agent: {agent_hash[:8]}...)")

    # 5. Video Duration Accuracy (20 pts)
    actual_duration = float(video_info.get("duration_sec", 0))
    duration_diff = abs(actual_duration - expected_duration)
    
    if duration_diff <= tolerance_sec:
        score += 20
        feedback_parts.append(f"Duration accurate ({actual_duration:.1f}s)")
    elif duration_diff <= (tolerance_sec * 2):
        score += 10
        feedback_parts.append(f"Duration slightly off ({actual_duration:.1f}s, target {expected_duration}s)")
    else:
        feedback_parts.append(f"Duration incorrect ({actual_duration:.1f}s, target {expected_duration}s)")

    # 6. Video Resolution/Content (15 pts)
    # Check if we have a valid resolution (implies valid stream)
    width = video_info.get("width", 0)
    height = video_info.get("height", 0)
    
    if width > 0 and height > 0:
        score += 15
        feedback_parts.append(f"Valid video stream ({width}x{height})")
    else:
        feedback_parts.append("Video appears empty or invalid")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }