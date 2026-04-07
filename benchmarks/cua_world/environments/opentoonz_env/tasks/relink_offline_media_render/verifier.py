#!/usr/bin/env python3
"""
Verifier for relink_offline_media_render task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_relink_offline_media_render(traj, env_info, task_info):
    """
    Verify that the user relinked the offline media and rendered a valid frame.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
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
    
    # 1. Output File Exists (20 pts)
    if result.get('output_exists'):
        score += 20
        feedback_parts.append("Output file exists")
    else:
        feedback_parts.append("Output file missing")

    # 2. File Created During Task (20 pts)
    if result.get('file_created_during_task'):
        score += 20
        feedback_parts.append("File created during task session")
    else:
        feedback_parts.append("File not created during task")

    # 3. Image Validity & Content (60 pts)
    # We check if the image has variance (is not blank/solid color)
    img_info = result.get('img_info', {})
    if img_info.get('valid'):
        variance = img_info.get('variance', 0)
        width = img_info.get('width', 0)
        
        # Valid image structure
        score += 20
        feedback_parts.append(f"Valid image format ({width}x{img_info.get('height')})")
        
        # Content check: "Missing" media often renders as solid white, transparent, or red.
        # A correct render of the dwanko character will have significant color variance.
        if variance > 50:  # Threshold for non-flat image
            score += 40
            feedback_parts.append("Image content shows loaded media (high variance)")
        else:
            feedback_parts.append("Image appears blank or solid color (media likely still offline)")
    else:
        feedback_parts.append("Invalid image data")

    # Pass logic
    passed = (score >= 70)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }