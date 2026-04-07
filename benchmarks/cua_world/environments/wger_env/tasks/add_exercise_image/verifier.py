#!/usr/bin/env python3
"""
Verifier for add_exercise_image task in wger_env.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_exercise_image(traj, env_info, task_info):
    """
    Verification strategy:
    1. Database confirms "Standard Push-up" exercise exists.
    2. Image count associated with the exercise is exactly 1 (increased from 0).
    3. The file exists physically on the wger media backend.
    4. The license is appropriately categorized as Creative Commons.
    5. VLM checks the agent trajectory to ensure file upload behavior.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Safely load the exported results JSON from the container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    exercise_exists = result.get('exercise_exists', False)
    image_count = result.get('image_count', 0)
    images = result.get('images', [])

    if not exercise_exists:
        return {"passed": False, "score": 0, "feedback": "FAIL: 'Standard Push-up' exercise not found in database."}
    
    score += 10
    feedback_parts.append("Exercise verified")

    if image_count > 0:
        score += 30
        feedback_parts.append(f"Image count increased ({image_count} found)")
        
        # Check backend file validation
        valid_files = [img for img in images if img.get('file_exists', False)]
        if valid_files:
            score += 30
            feedback_parts.append("Image file successfully verified on the application backend")
            
            # Check license configuration
            cc_licensed = any(
                "Creative Commons" in img.get('license', '') or "CC " in img.get('license', '') 
                for img in valid_files
            )
            if cc_licensed:
                score += 10
                feedback_parts.append("Creative Commons license confirmed")
            else:
                feedback_parts.append("Warning: License was not set to a Creative Commons option")
        else:
            feedback_parts.append("FAIL: Database record exists, but the file failed to upload to the server media path.")
    else:
        feedback_parts.append("FAIL: No images attached to the exercise.")

    # VLM Trajectory Verification
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        if frames and final:
            prompt = (
                "You are verifying a web automation task. The goal was to upload a local image file "
                "to a fitness application to represent an exercise. Look at these trajectory frames. "
                "Did the user open a file upload/browser dialog and attempt to attach a local file "
                "(like 'pushup_reference.jpg')? "
                "Answer YES or NO and briefly explain."
            )
            try:
                vlm_result = query_vlm(images=frames + [final], prompt=prompt)
                if vlm_result.get("success"):
                    response = vlm_result.get("response", "").upper()
                    if "YES" in response:
                        score += 20
                        feedback_parts.append("VLM verified upload file-picker trajectory")
                    else:
                        feedback_parts.append("VLM did not detect file-picker workflow")
            except Exception as e:
                logger.error(f"VLM verification failed: {e}")
                feedback_parts.append("VLM verification failed due to error")

    # Pass condition: exercise exists, image attached, file actually verified on the server, and some evidence of correct process
    passed = score >= 80

    return {
        "passed": passed, 
        "score": score, 
        "feedback": " | ".join(feedback_parts)
    }