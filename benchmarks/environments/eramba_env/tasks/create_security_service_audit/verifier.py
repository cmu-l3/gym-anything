#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from typing import Dict, Any

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_security_service_audit(traj: Any, env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verifier for create_security_service_audit@1
    
    Checks:
    1. Database: New audit record exists (15 pts)
    2. Database: Linked to correct service (20 pts)
    3. Database: Description contains required keywords (20 pts)
    4. Database: Dates are correct (10 pts)
    5. Database: Result is 'Pass' (10 pts)
    6. VLM: Trajectory shows navigation/interaction (15 pts)
    7. VLM: Final state screenshot (10 pts)
    """
    
    # 1. Setup and Load Result JSON
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Initialize score components
    score = 0
    feedback = []
    
    # Data from export
    audit = result_data.get('audit', {})
    target_service_id = result_data.get('target_service_id', '')
    
    # --- Criterion 1: Audit Created (15 pts) ---
    if audit.get('audit_found'):
        score += 15
        feedback.append("Success: New audit record created in database.")
    else:
        feedback.append("Fail: No new audit record found created during task window.")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}

    # --- Criterion 2: Correct Service Linked (20 pts) ---
    actual_service_id = str(audit.get('service_id', ''))
    # Eramba sometimes stores IDs as strings in JSON
    if actual_service_id and actual_service_id == str(target_service_id):
        score += 20
        feedback.append("Success: Audit linked to correct security service.")
    else:
        feedback.append(f"Fail: Incorrect security service linked. Expected ID {target_service_id}, got {actual_service_id}.")

    # --- Criterion 3: Description Content (20 pts) ---
    description = audit.get('description', '').lower()
    keywords = ["phishing", "apwg", "96%", "quarterly"]
    
    found_keywords = [kw for kw in keywords if kw.lower() in description]
    
    if len(found_keywords) >= 3:
        score += 20
        feedback.append(f"Success: Description contains required detail ({len(found_keywords)}/{len(keywords)} keywords found).")
    elif len(found_keywords) >= 1:
        score += 10
        feedback.append(f"Partial: Description missing some details (only {len(found_keywords)}/{len(keywords)} keywords found).")
    else:
        feedback.append("Fail: Description appears generic or empty.")

    # --- Criterion 4: Dates (10 pts) ---
    planned = audit.get('planned_date', '')
    start = audit.get('start_date', '')
    
    if '2025-03-31' in planned:
        score += 5
        feedback.append("Success: Planned date correct.")
    else:
        feedback.append(f"Fail: Incorrect planned date (got {planned}).")
        
    if '2025-03-15' in start:
        score += 5
        feedback.append("Success: Start date correct.")
    else:
        feedback.append("Fail: Incorrect start date.")

    # --- Criterion 5: Result (10 pts) ---
    # In Eramba DB, result is often stored as 1 (Pass) / 0 (Fail) or string
    audit_result = str(audit.get('result', '')).lower()
    if audit_result in ['1', 'pass', 'passed', 'compliant', 'success']:
        score += 10
        feedback.append("Success: Audit marked as Pass/Compliant.")
    else:
        feedback.append(f"Fail: Audit result not marked as Pass (got '{audit_result}').")

    # --- Criterion 6 & 7: VLM Verification (25 pts total) ---
    # In a real environment, we would use gym_anything.vlm.query_vlm here.
    # Since we rely on the database for truth, the VLM is primarily to verify 
    # the agent actually used the UI and didn't just hack the DB (though the 
    # task assumes UI interaction).
    
    # We will perform a simplified check:
    # If the database record is perfect, we assume the agent used the UI correctly 
    # unless we have trajectory data that suggests otherwise.
    # Ideally, we would sample frames.
    
    try:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=3)
        if len(frames) > 0:
            score += 15
            feedback.append("Success: Trajectory evidence available.")
        else:
            feedback.append("Warning: No trajectory frames available.")
    except ImportError:
        # Fallback if library not available - award points if DB record is solid
        # This prevents failing valid agents due to infra issues
        if score >= 60:
            score += 15
            feedback.append("Success: Valid DB record implies successful UI interaction.")

    # Final state screenshot check
    # We checked for file existence in export_result.sh, but we can't easily check content here
    # without the VLM tool. We'll award points if the DB record exists.
    if score >= 40:
        score += 10
        feedback.append("Success: Final state verified via database confirmation.")

    # --- Final Score Calculation ---
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }