#!/usr/bin/env python3
"""
Verifier for add_facility_logo_badge task.

Verification Logic:
1. Programmatic: Checks if badge template/config files were modified (20 pts)
2. Programmatic: Checks if logo was imported/referenced in app data (15 pts)
3. VLM: Checks trajectory for evidence of:
   - Opening badge designer (15 pts)
   - Importing the image (15 pts)
   - Final visual confirmation of ACME logo on badge (35 pts)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_facility_logo_badge(traj, env_info, task_info):
    """
    Verify that the user added the company logo to the badge template.
    """
    # 1. Setup and load programmatic results
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        # Continue, but programmatic score will be 0
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Programmatic Scoring (35 points max)
    
    # Criterion 1: File Modification (20 pts)
    # Did the user save changes?
    modified_count = result.get('modified_files_count', 0)
    if modified_count > 0:
        score += 20
        feedback_parts.append("Badge template files were modified/saved.")
    else:
        feedback_parts.append("No badge template file modifications detected (did you save?).")

    # Criterion 2: Logo Import Evidence (15 pts)
    # Did the app reference the logo file?
    logo_imported = result.get('logo_imported_programmatic', False)
    if logo_imported:
        score += 15
        feedback_parts.append("Logo file import detected in application data.")
    else:
        feedback_parts.append("No internal reference to logo file found in app data.")

    # 3. VLM Verification (65 points max)
    # We use trajectory frames to verify the workflow
    
    frames = sample_trajectory_frames(traj, n=4)
    final_screenshot = get_final_screenshot(traj)
    if final_screenshot:
        frames.append(final_screenshot)

    if not frames:
        return {
            "passed": False, 
            "score": score, 
            "feedback": " ".join(feedback_parts) + " No screenshots available for visual verification."
        }

    # VLM Prompt
    prompt = """
    You are verifying if a user successfully added a logo to a badge in 'Jolly Lobby Track'.
    The task requires:
    1. Opening the badge designer.
    2. Importing an image file named 'company_logo.png' (It looks like a blue/white square with text 'ACME').
    3. Placing it on the badge.
    4. Saving the template.

    Review the screenshots provided. 
    - Do you see the badge design interface?
    - Do you see a logo that says 'ACME' or 'Consulting' on the badge layout?
    - Does the final state show the logo integrated into the badge?
    
    Return JSON:
    {
        "badge_designer_opened": boolean,
        "logo_visible_on_badge": boolean,
        "logo_matches_description": boolean,
        "confidence": "low|medium|high"
    }
    """

    try:
        vlm_response = query_vlm(images=frames, prompt=prompt)
        parsed = vlm_response.get('parsed', {})
        
        # Scoring VLM results
        if parsed.get('badge_designer_opened'):
            score += 15
            feedback_parts.append("Visual confirmation: Badge designer was opened.")
        
        if parsed.get('logo_visible_on_badge'):
            score += 30
            feedback_parts.append("Visual confirmation: Logo is visible on the badge.")
            
            if parsed.get('logo_matches_description'):
                score += 20
                feedback_parts.append("Visual confirmation: Correct ACME logo used.")
            else:
                feedback_parts.append("Warning: Logo visible but might not match 'ACME' description.")
        else:
            feedback_parts.append("Visual verification failed: Logo not seen on badge.")

    except Exception as e:
        logger.error(f"VLM query failed: {e}")
        feedback_parts.append("VLM verification failed due to system error.")

    # 4. Final Pass/Fail Determination
    # Must have saved the file AND visually confirmed the logo
    passed = (modified_count > 0) and parsed.get('logo_visible_on_badge', False)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " ".join(feedback_parts)
    }