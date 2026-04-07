#!/usr/bin/env python3
"""
Verifier for retrieve_bookmarked_evidence task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_retrieve_bookmarked_evidence(traj, env_info, task_info):
    """
    Verifies that the agent retrieved the correct video evidence.
    
    Criteria:
    1. Output file exists at correct path.
    2. File is a valid video (checked via ffprobe in export script).
    3. File duration matches (Bookmark Duration + 20s buffer) +/- tolerance.
    4. File was created during the task.
    """
    
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring
    score = 0
    feedback = []
    
    # Criterion 1: File Existence (30 pts)
    if result.get("file_exists", False):
        score += 30
        feedback.append("File 'evidence_export.mkv' found.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file 'evidence_export.mkv' not found in Documents."}

    # Criterion 2: Valid Video Format (20 pts)
    fmt = result.get("file_format", "unknown")
    if fmt not in ["unknown", ""]:
        score += 20
        feedback.append(f"Valid video format detected ({fmt}).")
    else:
        feedback.append("File does not appear to be a valid video.")

    # Criterion 3: Creation Time (Anti-gaming) (10 pts)
    if result.get("created_during_task", False):
        score += 10
    else:
        feedback.append("Warning: File timestamp indicates it was not created during this session.")

    # Criterion 4: Duration Check (40 pts)
    # Expected: Bookmark (10s) + Pre (10s) + Post (10s) = 30s
    # Tolerance: +/- 5 seconds (handling GOP alignment and manual selection variance)
    try:
        actual_dur = float(result.get("file_duration_sec", 0))
        expected_dur = float(result.get("expected_duration_sec", 30.0))
        
        diff = abs(actual_dur - expected_dur)
        tolerance = 5.0 
        
        if diff <= tolerance:
            score += 40
            feedback.append(f"Video duration ({actual_dur:.1f}s) is within acceptable range of expected ({expected_dur}s).")
        elif diff <= 10.0:
            score += 20
            feedback.append(f"Video duration ({actual_dur:.1f}s) deviates significantly from expected ({expected_dur}s). check buffer settings.")
        else:
            feedback.append(f"Video duration ({actual_dur:.1f}s) is incorrect (Expected ~{expected_dur}s).")
            
    except (ValueError, TypeError):
        feedback.append("Could not parse video duration.")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }