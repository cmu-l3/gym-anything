#!/usr/bin/env python3
"""
Verifier for configure_ransomware_detection task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_ransomware_detection(traj, env_info, task_info):
    """
    Verifies the ransomware configuration task using VLM analysis of evidence and trajectory.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_threshold_count = metadata.get('expected_threshold_count', 50)
    expected_threshold_time = metadata.get('expected_threshold_time', 1)
    expected_email = metadata.get('expected_email', "soc-alerts@acmefinancial.com")

    # 1. Retrieve Result JSON from Container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        copy_from_env("C:\\workspace\\tasks\\configure_ransomware_detection\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task execution data"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Retrieve Evidence Screenshot (if it exists)
    evidence_path_in_container = result_data.get("evidence_path")
    local_evidence_path = None
    
    if result_data.get("evidence_exists") and evidence_path_in_container:
        temp_evidence = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env(evidence_path_in_container, temp_evidence.name)
            local_evidence_path = temp_evidence.name
        except Exception as e:
            logger.warning(f"Could not copy evidence screenshot: {e}")

    # 3. Retrieve Final Desktop Screenshot
    final_desktop_path_in_container = result_data.get("final_screenshot_path")
    local_final_path = None
    if final_desktop_path_in_container:
        temp_final = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env(final_desktop_path_in_container, temp_final.name)
            local_final_path = temp_final.name
        except Exception:
            pass

    # 4. Scoring Logic
    score = 0
    feedback_log = []

    # Criterion A: Evidence File Created (10 pts)
    if result_data.get("evidence_exists"):
        score += 10
        feedback_log.append("Evidence screenshot file created.")
        if result_data.get("evidence_created_during_task"):
            score += 10
            feedback_log.append("Evidence created during task window (Freshness verified).")
        else:
            feedback_log.append("WARNING: Evidence file timestamp is old.")
    else:
        feedback_log.append("Evidence screenshot missing.")

    # Criterion B: Browser Running (10 pts)
    if result_data.get("browser_running"):
        score += 10
    else:
        feedback_log.append("Browser was not open at task end.")

    # Criterion C: VLM Verification of Configuration (70 pts)
    # We prefer the specific evidence screenshot the agent took of the config,
    # falling back to the final desktop state if needed.
    image_to_verify = local_evidence_path if local_evidence_path else local_final_path
    
    if image_to_verify:
        prompt = f"""
        Analyze this screenshot of the ManageEngine ADAudit Plus interface.
        I am looking for the 'Possible Ransomware Attack' or similar alert profile configuration.

        Please verify the following settings:
        1. Is the Alert Profile Name 'Possible Ransomware Attack' (or 'Ransomware')?
        2. Is the Threshold 'Number of Events' set to {expected_threshold_count}?
        3. Is the Threshold 'Time' set to {expected_threshold_time} minute(s)?
        4. Is Email Notification enabled?
        5. Is the Email Recipient set to '{expected_email}'?
        6. Is the Subject Line set to 'CRITICAL: Ransomware Activity Detected'?

        Return JSON:
        {{
            "profile_name_correct": boolean,
            "threshold_count_match": boolean,
            "threshold_time_match": boolean,
            "email_enabled": boolean,
            "email_recipient_match": boolean,
            "subject_line_match": boolean,
            "confidence": "high/medium/low"
        }}
        """
        
        vlm_response = query_vlm(prompt=prompt, image=image_to_verify)
        
        if vlm_response.get("success"):
            parsed = vlm_response.get("parsed", {})
            
            # Threshold Check (30 pts)
            if parsed.get("threshold_count_match") and parsed.get("threshold_time_match"):
                score += 30
                feedback_log.append(f"Thresholds correctly set to {expected_threshold_count} events / {expected_threshold_time} min.")
            else:
                feedback_log.append("Thresholds do not match expected values.")

            # Email Check (30 pts)
            if parsed.get("email_enabled") and parsed.get("email_recipient_match"):
                score += 30
                feedback_log.append(f"Email notification correctly configured for {expected_email}.")
            elif parsed.get("email_enabled"):
                score += 15
                feedback_log.append("Email enabled but recipient incorrect.")
            else:
                feedback_log.append("Email notification not enabled.")

            # Subject Line Bonus (10 pts max within 70 cap, effective 10)
            if parsed.get("subject_line_match"):
                # Bonus points if we haven't capped
                pass 
        else:
            feedback_log.append("VLM analysis failed.")
    else:
        feedback_log.append("No screenshots available for visual verification.")

    # Cleanup local temp files
    if local_evidence_path and os.path.exists(local_evidence_path):
        os.unlink(local_evidence_path)
    if local_final_path and os.path.exists(local_final_path):
        os.unlink(local_final_path)

    # Final Pass Decision
    # Must have evidence file + correct thresholds + correct email
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_log)
    }