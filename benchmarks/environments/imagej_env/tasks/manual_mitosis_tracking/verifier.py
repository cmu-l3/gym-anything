#!/usr/bin/env python3
"""
Verifier for manual_mitosis_tracking task.
"""

import json
import tempfile
import os
import logging
import math

logger = logging.getLogger(__name__)

def verify_mitosis_tracking(traj, env_info, task_info):
    """
    Verify the mitosis tracking task.
    
    Criteria:
    1. CSV file created during task (20 pts)
    2. Coordinate accuracy for Frames 1, 6, 11, 16, 21 (16 pts each frame)
       - Uses Euclidean distance vs ground truth with tolerance.
    
    Pass threshold: 65 points (File + ~3 correct frames)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}
    
    # Load metadata
    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth', {}) # str_frame -> [x, y]
    tolerance = metadata.get('tolerance_px', 25)
    
    # Retrieve result JSON
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        copy_from_env("/tmp/mitosis_task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {str(e)}"}

    score = 0
    feedback_parts = []
    
    # 1. File Existence & Creation (20 pts)
    if result.get("file_exists") and result.get("file_created_during_task"):
        score += 20
        feedback_parts.append("Tracking file created.")
    elif result.get("file_exists"):
        score += 10
        feedback_parts.append("File exists but timestamp check failed (half points).")
    else:
        feedback_parts.append("FAIL: Output file not found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback_parts)}
    
    # 2. Coordinate Verification (16 pts per frame = 80 pts max)
    parsed_data = result.get("parsed_data", {})
    frames_to_check = ["1", "6", "11", "16", "21"]
    
    for frame in frames_to_check:
        if frame in parsed_data:
            user_pt = parsed_data[frame]
            gt_pt = ground_truth.get(frame)
            
            if gt_pt:
                # Calculate Euclidean distance
                dist = math.sqrt((user_pt[0] - gt_pt[0])**2 + (user_pt[1] - gt_pt[1])**2)
                
                if dist <= tolerance:
                    score += 16
                    feedback_parts.append(f"Frame {frame}: OK (dist={dist:.1f}px).")
                else:
                    feedback_parts.append(f"Frame {frame}: Off by {dist:.1f}px (Limit {tolerance}px).")
            else:
                feedback_parts.append(f"Frame {frame}: No GT defined.")
        else:
            feedback_parts.append(f"Frame {frame}: Missing.")

    # Final check
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }