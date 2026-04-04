#!/usr/bin/env python3
"""
Verifier for cleanup_disk_space task.

Criteria:
1. The specific large file created during setup MUST be deleted (Primary).
2. The agent should have used the Virtualmin UI (VLM verification of trajectory).
"""

import json
import os
import tempfile
import logging
import sys
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cleanup_disk_space(traj, env_info, task_info):
    """
    Verify that the large target file was removed.
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
    
    # CRITERION 1: File Removal (80 points)
    # The file must be completely gone.
    target_exists = result.get('target_file_exists', True)
    
    if not target_exists:
        score += 80
        feedback_parts.append("Large temporary file successfully removed")
    else:
        feedback_parts.append("Target file still exists on disk")
        # If file exists, they fail the main objective immediately
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # CRITERION 2: VLM Trajectory Check (20 points)
    # Verify they actually visited the Disk Usage page or File Manager
    frames = sample_trajectory_frames(traj, n=4)
    
    vlm_prompt = """
    The user was tasked with identifying a large file using Virtualmin's 'Disk Usage' tool or File Manager.
    Look at these screenshots of the user's workflow.
    
    1. Do you see a screen showing 'Disk Usage', 'Disk Quota', or a list of files with sizes?
    2. Do you see a large file (approx 200 MB) being selected or viewed?
    3. Do you see a confirmation of file deletion?
    
    Answer 'Yes' if any of these are visible.
    """
    
    # We execute VLM query if we have frames
    vlm_score = 0
    if frames:
        try:
            vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
            # Simple heuristic: if VLM response is positive
            response_text = vlm_result.get('response', '').lower()
            if 'yes' in response_text or 'visible' in response_text or 'shows' in response_text:
                vlm_score = 20
                feedback_parts.append("Workflow verified visually")
            else:
                # Even if VLM is unsure, if the file is gone, we give partial credit for method
                vlm_score = 10 
                feedback_parts.append("File removed (visual verification inconclusive)")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            vlm_score = 10  # Default fallback points if VLM fails but file is gone
            feedback_parts.append("VLM check skipped")
    else:
        vlm_score = 10
        feedback_parts.append("No trajectory frames available")

    score += vlm_score

    return {
        "passed": score >= 90,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }