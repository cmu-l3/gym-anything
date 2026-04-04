#!/usr/bin/env python3
"""
Verifier for write_consultation_request task.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_write_consultation_request(traj, env_info, task_info):
    """
    Verifies that the consultation request was created correctly in Oscar EMR.
    """
    # 1. Setup and Load Data
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Load metadata
    metadata = task_info.get('metadata', {})
    target_demo = metadata.get('target_patient_demo_no', "10001")
    target_service = metadata.get('target_service_id', "1")
    keywords = metadata.get('required_keywords_reason', [])
    urgency_vals = metadata.get('required_urgency', ["urgent", "1", "u"])

    score = 0
    feedback_parts = []
    
    # 2. Programmatic Verification (Database)
    
    # Criterion 1: New record created (20 pts)
    # Check if count increased AND we found a new record ID
    initial_count = int(result.get('initial_count', 0))
    current_count = int(result.get('current_count', 0))
    record_found = result.get('record_found', False)
    consult = result.get('consultation_record', {})

    if record_found and current_count > initial_count:
        score += 20
        feedback_parts.append("New consultation record created.")
    elif record_found:
        # Fallback: Found a new ID even if count logic was fuzzy
        score += 15
        feedback_parts.append("New consultation record found (count check unclear).")
    else:
        return {"passed": False, "score": 0, "feedback": "No new consultation request found in database."}

    # Criterion 2: Correct Patient (15 pts)
    demo_no = str(consult.get('demographic_no', '')).strip()
    if demo_no == target_demo:
        score += 15
        feedback_parts.append("Correct patient linked.")
    else:
        feedback_parts.append(f"Wrong patient linked. Expected {target_demo}, got {demo_no}.")

    # Criterion 3: Urgency (10 pts)
    urgency = str(consult.get('urgency', '')).lower().strip()
    if any(val in urgency for val in urgency_vals):
        score += 10
        feedback_parts.append("Urgency set correctly.")
    else:
        # Partial credit if not empty
        if urgency and urgency != "null":
            score += 5
            feedback_parts.append(f"Urgency set to '{urgency}' (expected Urgent).")
        else:
            feedback_parts.append("Urgency not set.")

    # Criterion 4: Service/Specialist (10 pts)
    # Check service ID (1) OR specialist name/ID match
    service_id = str(consult.get('service_id', '')).strip()
    spec_id = str(consult.get('specialist_id', '')).strip()
    send_to = str(consult.get('send_to', '')).lower()
    
    service_match = (service_id == target_service)
    spec_match = ("hartfield" in send_to) or (spec_id == "1")
    
    if service_match or spec_match:
        score += 10
        feedback_parts.append("Service/Specialist correct.")
    else:
        feedback_parts.append("Service or Specialist incorrect.")

    # Criterion 5: Clinical Content (Reason/Clinical Info) (25 pts)
    reason = str(consult.get('reason', '')).lower()
    clinical_info = str(consult.get('clinical_info', '')).lower()
    combined_text = reason + " " + clinical_info
    
    found_keywords = [kw for kw in keywords if kw.lower() in combined_text]
    keyword_score = min(25, len(found_keywords) * 6) # approx 4 keywords needed for full points
    if keyword_score > 0:
        score += keyword_score
        feedback_parts.append(f"Content verified ({len(found_keywords)} keywords found).")
    else:
        feedback_parts.append("No relevant clinical content found in reason/notes.")

    # 3. VLM Verification (Trajectory) (20 pts)
    # We define a simple VLM check here for workflow validation
    
    # In a real scenario, we would call a VLM model. 
    # For this implementation, we check if the final screenshot exists and application is running.
    # Additionally, we assume the trajectory shows interaction if the database state changed.
    
    app_running = result.get('app_running', False)
    screenshot_path = result.get('screenshot_path', '')
    
    if app_running and screenshot_path:
        score += 20
        feedback_parts.append("Application state valid.")
    else:
        feedback_parts.append("Application not running or screenshot missing.")

    # 4. Final Result
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }