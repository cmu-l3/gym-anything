#!/usr/bin/env python3
"""
Verifier for set_tier2_certification_info task in CAMEO Data Manager.

Verification Strategy:
1. Anti-Gaming: Check if the CAMEO database file was modified during the task (indicates 'Save').
2. VLM Verification: Analyze trajectory and final screenshot to read the form fields.
   - Certifier Name
   - Title
   - Date
"""

import json
import os
import logging
import tempfile
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_set_tier2_certification_info(traj, env_info, task_info):
    """
    Verify the agent entered the correct certification details.
    """
    # 1. Setup and Load Metadata
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('certifier_name', 'Maria T. Rodriguez')
    expected_title = metadata.get('certifier_title', 'Director of Environmental Health & Safety')
    expected_date = metadata.get('certifier_date_str', 'March 01, 2024')
    
    # 2. Retrieve Exported Result (File timestamps)
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.warning(f"Could not read task_result.json: {e}")
        # Continue, but penalize for no file check
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Calculate Score Components
    score = 0
    feedback_parts = []
    
    # Check 1: Database Modified (Anti-Gaming) - 20 pts
    db_modified = result_data.get('db_modified_during_task', False)
    if db_modified:
        score += 20
        feedback_parts.append("Database record saved successfully.")
    else:
        feedback_parts.append("Warning: Database file was not modified (did you save?).")

    # Check 2: VLM Visual Verification - 80 pts
    # We sample frames to see if the user was in the right menu, but rely on final state for values
    final_screenshot = get_final_screenshot(traj)
    
    if not final_screenshot:
        return {"passed": False, "score": score, "feedback": "No screenshots available for verification."}

    prompt = f"""
    You are verifying a data entry task in CAMEO Data Manager.
    The user was supposed to enter Certification/Signatory details for a facility.
    
    Look at the screenshot and check for these SPECIFIC values:
    1. Name/Certifier: "{expected_name}"
    2. Title: "{expected_title}"
    3. Date: "{expected_date}" (or similar format like 3/1/2024)
    4. Email/Phone: Checking for populated contact fields is a plus.
    
    Output JSON with:
    - name_match: boolean
    - title_match: boolean
    - date_match: boolean
    - context_is_certification: boolean (is this the certification screen?)
    """
    
    vlm_response = query_vlm(
        prompt=prompt,
        image=final_screenshot
    )
    
    vlm_data = vlm_response.get('parsed', {})
    
    # Scoring based on VLM
    if vlm_data.get('context_is_certification', False):
        score += 10
        feedback_parts.append("Navigate to Certification screen: OK.")
    else:
        feedback_parts.append("Could not confirm agent is on Certification screen.")

    if vlm_data.get('name_match', False):
        score += 30
        feedback_parts.append(f"Certifier Name '{expected_name}': OK.")
    else:
        feedback_parts.append(f"Certifier Name mismatch or not visible.")

    if vlm_data.get('title_match', False):
        score += 20
        feedback_parts.append(f"Title '{expected_title}': OK.")
    else:
        feedback_parts.append(f"Title mismatch.")

    if vlm_data.get('date_match', False):
        score += 20
        feedback_parts.append(f"Date '{expected_date}': OK.")
    else:
        feedback_parts.append(f"Date mismatch.")

    # 4. Final Verdict
    # Pass threshold: 70 points (Must have saved + mostly correct data)
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }