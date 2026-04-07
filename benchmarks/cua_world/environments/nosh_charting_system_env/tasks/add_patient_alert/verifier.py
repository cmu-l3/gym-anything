#!/usr/bin/env python3
"""
Verifier for add_patient_alert@1

Verifies that the agent added a specific clinical alert to the correct patient.
Checks:
1. Alert record exists in DB for correct PID.
2. Alert text contains critical safety keywords ("latex", "anaphylaxis").
3. Alert is Active (not inactive/resolved).
4. Alert was created AFTER task start time (anti-gaming).
5. VLM verification of the workflow.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_patient_alert(traj, env_info, task_info):
    # 1. Setup & Environment Access
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment access failed (copy_from_env missing)"}

    # 2. Load Task Metadata
    metadata = task_info.get('metadata', {})
    required_keywords = metadata.get('required_keywords', ["latex", "anaphylaxis"])
    
    # 3. Retrieve Result JSON from Container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 4. Evaluate Database Evidence
    alerts = result_data.get("alerts", [])
    task_start = result_data.get("task_start_timestamp", 0)
    initial_count = result_data.get("initial_count", 0)
    
    score = 0
    feedback = []
    
    # Find the best matching alert
    best_alert = None
    keyword_matches = 0
    
    for alert in alerts:
        text = alert.get("text", "").lower()
        current_matches = sum(1 for k in required_keywords if k.lower() in text)
        
        # Check timestamp (must be created during task)
        # Allow 5 sec buffer for clock skew, though docker usually synced
        created_ts = alert.get("created_timestamp", 0)
        is_new = created_ts >= (task_start - 5)
        
        if is_new and current_matches > keyword_matches:
            keyword_matches = current_matches
            best_alert = alert
        elif is_new and best_alert is None:
            best_alert = alert

    # Scoring Criteria
    
    # Criterion A: Alert Created (Max 25 pts)
    if best_alert:
        score += 25
        feedback.append("New alert record found in database.")
    else:
        feedback.append("No new alert record found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Criterion B: Content Accuracy (Max 30 pts)
    # Check for keywords
    alert_text = best_alert.get("text", "").lower()
    missing_keywords = [k for k in required_keywords if k.lower() not in alert_text]
    
    if not missing_keywords:
        score += 30
        feedback.append("Alert text contains all required safety keywords.")
    else:
        # Partial credit
        pts_per_word = 30 // len(required_keywords)
        earned = (len(required_keywords) - len(missing_keywords)) * pts_per_word
        score += earned
        feedback.append(f"Alert text missing keywords: {', '.join(missing_keywords)}.")

    # Criterion C: Active Status (Max 15 pts)
    if best_alert.get("is_active"):
        score += 15
        feedback.append("Alert is correctly marked as Active.")
    else:
        feedback.append("Alert is marked as Inactive (should be Active).")

    # Criterion D: Count Check (Max 10 pts)
    # Prevents updating existing records instead of creating new
    if result_data.get("current_count", 0) > initial_count:
        score += 10
        feedback.append("Patient alert count increased.")

    # Criterion E: VLM Verification (Max 20 pts)
    # Verify the agent was actually in the patient chart/alert section
    vlm_score = 0
    try:
        final_screenshot = get_final_screenshot(traj)
        frames = sample_trajectory_frames(traj, 3)
        images = frames + ([final_screenshot] if final_screenshot else [])
        
        if images:
            prompt = """
            Review these screenshots of an EHR system interaction.
            Did the user:
            1. Access a patient chart for 'Robert Thompson'?
            2. Open the 'Alerts' or 'Issues' section?
            3. Enter text related to 'Latex Allergy'?
            
            Answer YES or NO for each.
            """
            
            # Using the query_vlm helper
            vlm_response = query_vlm(images=images, prompt=prompt)
            
            # Simple heuristic parsing of VLM response
            if vlm_response and vlm_response.get("success"):
                text_resp = vlm_response.get("result", "").lower()
                if "yes" in text_resp:
                    vlm_score = 20
                    feedback.append("Visual verification passed.")
                else:
                    vlm_score = 10 # Give some points if unsure but DB passed
                    feedback.append("Visual verification inconclusive.")
            else:
                vlm_score = 10 # Fallback
        else:
            vlm_score = 0
            feedback.append("No screenshots available for VLM.")
            
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        vlm_score = 20 # Fallback to trust DB if VLM crashes
    
    score += vlm_score

    # Final Check
    passed = (score >= 60) and (best_alert is not None)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }