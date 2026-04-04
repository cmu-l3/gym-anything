#!/usr/bin/env python3
"""
Verifier for Nuclei Motility Tracking with TrackMate.

Criteria:
1. Track Statistics CSV exists and was created/modified during task (20 pts)
2. CSV contains valid data (headers + rows) (20 pts)
3. At least 5 tracks identified (20 pts)
4. Motion data present (Mean Speed > 0) (20 pts)
5. Visual overlay image exists (20 pts)

Pass threshold: 60 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_nuclei_motility(traj, env_info, task_info):
    """
    Verify the output of the TrackMate tracking task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Environment interface error: copy_from_env not available"
        }
    
    # Retrieve result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/tracking_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Result file not found. Ensure export_result.sh ran successfully."
        }
    except json.JSONDecodeError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file corrupted or empty."
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 1. Check CSV Existence & Timing (20 pts)
    if result.get("csv_exists"):
        if result.get("files_created_during_task"):
            score += 20
            feedback.append("CSV statistics file created successfully.")
        else:
            score += 10
            feedback.append("CSV file exists but timestamp suggests it wasn't created during this run.")
    else:
        feedback.append("CSV statistics file not found.")

    # 2. Check CSV Validity (20 pts)
    if result.get("csv_valid"):
        score += 20
        feedback.append("CSV file has valid format and content.")
    else:
        feedback.append("CSV file is empty or invalid format.")

    # 3. Check Track Count (20 pts)
    track_count = result.get("track_count", 0)
    if track_count >= 5:
        score += 20
        feedback.append(f"Tracking successful: {track_count} tracks identified.")
    elif track_count > 0:
        score += 10
        feedback.append(f"Partial tracking: Only {track_count} tracks found (expected >= 5).")
    else:
        feedback.append("No tracks found in the output file.")

    # 4. Check Motion Data (20 pts)
    if result.get("has_motion_data") and result.get("mean_speed", 0) > 0:
        score += 20
        feedback.append(f"Motion data verified (Mean Speed: {result.get('mean_speed'):.2f}).")
    else:
        feedback.append("Motion data (Speed/Velocity) missing or zero.")

    # 5. Check Visual Output (20 pts)
    if result.get("visual_exists"):
        if result.get("visual_size", 0) > 5000: # Simple check for non-empty image
            score += 20
            feedback.append("Visual overlay image found.")
        else:
            score += 10
            feedback.append("Visual image exists but file size is suspiciously small.")
    else:
        feedback.append("Visual overlay image not found.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }