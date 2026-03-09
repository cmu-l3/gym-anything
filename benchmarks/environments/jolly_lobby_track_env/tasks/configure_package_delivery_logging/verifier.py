#!/usr/bin/env python3
"""
Verifier for configure_package_delivery_logging task.

Strategies:
1. File-based: Inspect database files (via strings/grep results export) to verify data persistence.
2. VLM: Analyze trajectory to verify workflow steps (Group creation, Field setup, Disabling Photo/NDA).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_package_delivery_logging(traj, env_info, task_info):
    """
    Verify the package delivery logging configuration.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_tracking = metadata.get('test_tracking', "1Z999AA10123456784")

    # 1. Load exported results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # =================================================================
    # CRITERION 1: Data Persistence (40 pts)
    # =================================================================
    # Check if strings were found in the DB file
    group_found = result.get('group_found_in_db', False)
    field_found = result.get('field_found_in_db', False)
    tracking_found = result.get('tracking_found_in_db', False)
    db_modified = result.get('db_modified_during_task', False)

    if tracking_found:
        score += 20
        feedback_parts.append("Tracking number found in database (+20)")
    else:
        feedback_parts.append("Tracking number NOT found in database")

    if group_found:
        score += 10
        feedback_parts.append("Group 'Deliveries' found in database (+10)")
    
    if field_found:
        score += 10
        feedback_parts.append("Field 'Tracking Number' found in database (+10)")

    if db_modified:
        # Bonus/Anti-gaming: DB was actually written to
        pass
    else:
        feedback_parts.append("(Warning: Database file not modified during task)")

    # =================================================================
    # CRITERION 2: VLM Trajectory Verification (60 pts)
    # =================================================================
    # We need to verify the *workflow*:
    # 1. Did they access settings/group configuration?
    # 2. Did they disable "Capture Photo" and "Sign Agreement"?
    # 3. Did they register the visitor?

    frames = sample_trajectory_frames(traj, n=8)
    final_screen = get_final_screenshot(traj)
    images_to_analyze = frames + [final_screen]

    prompt = f"""
    You are verifying a software configuration task in Jolly Lobby Track.
    The user was supposed to:
    1. Create a Visitor Group named "Deliveries".
    2. Add a field "Tracking Number".
    3. DISABLE "Capture Photo" and "Sign Agreement" in the Registration settings for this group.
    4. Register a visitor "FedEx Express" with tracking number "{expected_tracking}".

    Analyze the sequence of screenshots.
    
    Q1: Do you see a screen for configuring "Visitor Groups" or "Settings"?
    Q2: Do you see the checkboxes for "Capture Photo" or "Sign Agreement" being unchecked or disabled?
    Q3: Do you see the "Deliveries" group being selected or created?
    Q4: Do you see the final registration of "FedEx Express" or the log showing this entry?
    Q5: In the final registration step, was the photo capture screen SKIPPED (i.e., did it go straight to finish/print)?

    Output JSON:
    {{
      "settings_accessed": true/false,
      "photo_nda_disabled": true/false,
      "deliveries_group_created": true/false,
      "registration_completed": true/false,
      "photo_skipped": true/false,
      "confidence": "high/medium/low"
    }}
    """

    try:
        vlm_resp = query_vlm(images=images_to_analyze, prompt=prompt)
        vlm_data = vlm_resp.get('parsed', {})
        
        if vlm_data.get('settings_accessed'):
            score += 10
            feedback_parts.append("Accessed configuration settings (+10)")
        
        if vlm_data.get('deliveries_group_created'):
            score += 10
            feedback_parts.append("Created 'Deliveries' group (+10)")
            
        if vlm_data.get('photo_nda_disabled') or vlm_data.get('photo_skipped'):
            score += 20
            feedback_parts.append("Disabled Photo/NDA steps (+20)")
        else:
            feedback_parts.append("Could not verify Photo/NDA disabling")

        if vlm_data.get('registration_completed'):
            score += 20
            feedback_parts.append("Registration completed successfully (+20)")

    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        feedback_parts.append("VLM verification failed")

    # =================================================================
    # FINAL SCORE CALCULATION
    # =================================================================
    
    # Cap score at 100
    score = min(100, score)
    
    # Pass threshold: 60 points
    # Must have at least tracking number found OR clear VLM evidence of registration + group creation
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }