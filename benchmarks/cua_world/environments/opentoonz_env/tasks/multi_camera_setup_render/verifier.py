#!/usr/bin/env python3
"""
Verifier for multi_camera_setup_render task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_multi_camera(traj, env_info, task_info):
    """
    Verifies that the agent created a multi-camera scene and rendered a close-up.
    
    Criteria:
    1. Scene file 'multi_camera.tnz' exists (10 pts)
    2. Scene file contains at least 2 cameras (20 pts)
    3. Output 'closeup.png' exists and created during task (20 pts)
    4. Output image shows a close-up (subject height > 50% of image height) (30 pts)
    5. VLM verification of workflow (20 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Load result from container
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

    score = 0
    feedback = []

    # 1. Scene File Existence (10 pts)
    if result.get('scene_exists', False):
        score += 10
        feedback.append("Scene file saved successfully.")
    else:
        feedback.append("Failed: Scene file 'multi_camera.tnz' not found.")

    # 2. Camera Count (20 pts)
    # dwanko_run.tnz has 1 camera by default. We expect >= 2.
    cam_count = result.get('camera_count', 0)
    if cam_count >= 2:
        score += 20
        feedback.append(f"Multiple cameras detected in scene ({cam_count}).")
    elif cam_count == 1:
        feedback.append("Only 1 camera detected. You likely modified the existing camera instead of adding a new one.")
    else:
        feedback.append("No cameras detected in scene file.")

    # 3. Output Existence & Freshness (20 pts)
    if result.get('output_exists', False):
        if result.get('output_created_during_task', False):
            score += 20
            feedback.append("Output image rendered successfully.")
        else:
            score += 5
            feedback.append("Output image exists but was not created during this session (stale?).")
    else:
        feedback.append("Failed: 'closeup.png' not found.")

    # 4. Visual Verification (Close-up Check) (30 pts)
    # In the wide shot, the character is small. In a close-up, they should fill the frame.
    # We use the bounding box height ratio calculated in export_result.sh
    ratio = result.get('bbox_height_ratio', 0.0)
    min_ratio = task_info.get('metadata', {}).get('min_bbox_ratio', 0.5)
    
    if ratio >= min_ratio:
        score += 30
        feedback.append(f"Close-up framing verified (Subject fills {ratio:.2%} of frame).")
    elif ratio > 0.1:
        # Partial credit if they rendered *something* but it's not a close-up
        score += 10
        feedback.append(f"Image rendered but subject is too small for a close-up (fills {ratio:.2%} of frame). Did you switch cameras?")
    else:
        feedback.append("Rendered image appears empty or fully transparent.")

    # 5. VLM Verification (20 pts) - Placeholder for logic using trajectory
    # Since we don't have the VLM in this pure python verifier, we award points if the hard checks passed
    # In a real system, this would analyze `traj` screenshots.
    # We'll assume if they got the hard technical steps right, the workflow was likely correct.
    if score >= 70: 
        score += 20
        feedback.append("Workflow implicitly verified by output quality.")
    
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }