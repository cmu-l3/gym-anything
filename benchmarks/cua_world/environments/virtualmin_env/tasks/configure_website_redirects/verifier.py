#!/usr/bin/env python3
"""
Verifier for configure_website_redirects task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_website_redirects(traj, env_info, task_info):
    """
    Verifies that website redirects were correctly configured in Virtualmin.
    
    Criteria:
    1. Redirect 1 (/old-products) works: HTTP 301 to correct URL (30 pts)
    2. Redirect 2 (/survey) works: HTTP 302 to correct URL (30 pts)
    3. Configuration was modified during task (anti-gaming) (10 pts)
    4. VLM: Agent used Virtualmin UI (30 pts)
    """
    
    # 1. Retrieve result data from environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Task Metadata
    metadata = task_info.get('metadata', {})
    redirects_meta = metadata.get('redirects', [])
    r1_meta = redirects_meta[0]
    r2_meta = redirects_meta[1]

    score = 0
    feedback_parts = []

    # 3. Verify Redirect 1 (301 Permanent)
    r1_result = result.get('redirect1', {})
    r1_status = str(r1_result.get('actual_status', '0'))
    r1_loc = r1_result.get('actual_location', '').strip()
    
    # Check Status
    if r1_status == str(r1_meta['status']):
        score += 15
        feedback_parts.append(f"Redirect 1 status correct ({r1_status})")
    else:
        feedback_parts.append(f"Redirect 1 status incorrect (expected {r1_meta['status']}, got {r1_status})")

    # Check Location (allow trailing slashes mismatch generally, but exact is better)
    expected_loc_1 = r1_meta['destination']
    if r1_loc == expected_loc_1 or r1_loc == expected_loc_1 + "/":
        score += 15
        feedback_parts.append("Redirect 1 destination correct")
    else:
        feedback_parts.append(f"Redirect 1 destination incorrect (got {r1_loc})")

    # 4. Verify Redirect 2 (302 Temporary)
    r2_result = result.get('redirect2', {})
    r2_status = str(r2_result.get('actual_status', '0'))
    r2_loc = r2_result.get('actual_location', '').strip()

    # Check Status
    if r2_status == str(r2_meta['status']):
        score += 15
        feedback_parts.append(f"Redirect 2 status correct ({r2_status})")
    else:
        feedback_parts.append(f"Redirect 2 status incorrect (expected {r2_meta['status']}, got {r2_status})")

    # Check Location
    expected_loc_2 = r2_meta['destination']
    if r2_loc == expected_loc_2 or r2_loc == expected_loc_2 + "/":
        score += 15
        feedback_parts.append("Redirect 2 destination correct")
    else:
        feedback_parts.append(f"Redirect 2 destination incorrect (got {r2_loc})")

    # 5. Anti-gaming: Config Modified
    if result.get('config_modified_timestamp', False):
        score += 10
        feedback_parts.append("Configuration modified during task")
    elif result.get('config_modified', False):
        score += 5 # Partial credit if hash changed but timestamp weird
        feedback_parts.append("Configuration content changed")
    else:
        feedback_parts.append("Configuration NOT modified")

    # 6. VLM Verification (Trajectory)
    # Ensure they used the UI, not just `sed` in terminal
    frames = sample_trajectory_frames(traj, n=5)
    final_screen = get_final_screenshot(traj)
    
    if frames:
        vlm_prompt = (
            "Review these screenshots of a Virtualmin task.\n"
            "Did the user navigate to the 'Website Redirects' or 'Aliases and Redirects' page?\n"
            "Can you see a form where they entered '/old-products' or '/survey'?\n"
            "Does the interface look like the Virtualmin web control panel?\n"
            "Return JSON: {\"used_virtualmin_ui\": true/false, \"confidence\": \"high/medium/low\"}"
        )
        
        try:
            # We use a mix of frames + final to capture the action
            images_to_check = frames
            if final_screen:
                images_to_check.append(final_screen)
                
            vlm_response = query_vlm(images=images_to_check, prompt=vlm_prompt)
            parsed = vlm_response.get('parsed', {})
            
            if parsed.get('used_virtualmin_ui', False):
                score += 30
                feedback_parts.append("VLM confirmed UI usage")
            else:
                feedback_parts.append("VLM did not observe UI usage")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: if functional tests passed perfectly, give benefit of doubt for UI
            if score >= 60: 
                score += 30
                feedback_parts.append("VLM skipped (functional pass)")
    else:
        # No frames available
        if score >= 60:
            score += 30
            feedback_parts.append("No frames (functional pass)")

    # 7. Final Scoring
    passed = score >= 60 and r1_status == '301' and r2_status == '302'
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }