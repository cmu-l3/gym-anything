#!/usr/bin/env python3
"""
Verifier for upload_employee_profile_photos task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_upload_photos(traj, env_info, task_info):
    """
    Verify that profile photos were uploaded for both employees.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # 2. Load Result JSON
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

    # 3. Evaluate Criteria
    score = 0
    feedback = []
    
    # Metadata thresholds
    min_size = task_info.get('metadata', {}).get('min_photo_size_bytes', 1000)

    # Check James Carter
    james = result.get('james_carter', {})
    if james.get('photo_exists') and james.get('photo_size_bytes', 0) > min_size:
        score += 40
        feedback.append("James Carter: Photo uploaded successfully.")
    elif james.get('photo_exists'):
        score += 20
        feedback.append("James Carter: Photo record exists but data is too small/empty.")
    else:
        feedback.append("James Carter: No photo found.")

    # Check Linda Chen
    linda = result.get('linda_chen', {})
    if linda.get('photo_exists') and linda.get('photo_size_bytes', 0) > min_size:
        score += 40
        feedback.append("Linda Chen: Photo uploaded successfully.")
    elif linda.get('photo_exists'):
        score += 20
        feedback.append("Linda Chen: Photo record exists but data is too small/empty.")
    else:
        feedback.append("Linda Chen: No photo found.")

    # 4. VLM Verification (Trajectory check)
    # We want to see evidence of the photo upload dialog or the final profile with an image
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        prompt = """
        Review these screenshots of an agent using OrangeHRM.
        The agent's goal was to upload profile photos for employees James Carter and Linda Chen.
        
        Look for:
        1. Navigation to employee profiles.
        2. The file upload dialog or clicking on the profile picture placeholder.
        3. A profile page showing a photo (a face) instead of the default grey silhouette.
        
        Did the agent appear to attempt the upload steps?
        """
        
        try:
            vlm_resp = query_vlm(images=frames + [final], prompt=prompt)
            if vlm_resp.get('success'):
                # Simple boolean check based on VLM reasoning
                lower_resp = str(vlm_resp.get('parsed', '')).lower() + str(vlm_resp.get('response', '')).lower()
                if "yes" in lower_resp or "uploaded" in lower_resp or "face" in lower_resp:
                    vlm_score = 20
                    feedback.append("Visual verification passed.")
                else:
                    feedback.append("Visual verification inconclusive.")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback points if DB check passed perfectly
            if score >= 80: 
                vlm_score = 20
    
    score += vlm_score

    # 5. Final Determination
    # Must have both photos in DB to pass
    passed = (james.get('photo_exists') and 
              linda.get('photo_exists') and 
              james.get('photo_size_bytes', 0) > min_size and 
              linda.get('photo_size_bytes', 0) > min_size)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }