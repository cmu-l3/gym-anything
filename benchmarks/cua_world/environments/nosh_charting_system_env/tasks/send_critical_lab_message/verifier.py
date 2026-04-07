#!/usr/bin/env python3
"""
Verifier for send_critical_lab_message task in NOSH EHR.
Verifies that a secure message was sent with correct priority, recipient, and content.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_send_critical_lab_message(traj, env_info, task_info):
    """
    Verify the agent sent a critical lab notification message.
    
    Expected criteria:
    1. Message record exists in database (created during task).
    2. Recipient is 'demo_provider'.
    3. Patient is 'Maria Rodriguez'.
    4. Subject contains 'URGENT'.
    5. Body contains '6.2'.
    """
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring
    score = 0
    feedback_parts = []
    
    # Check 1: Message Found (30 pts)
    # The export script only finds messages created AFTER task start with subject 'URGENT' and body '6.2'
    # If message_found is true, it means Timestamp, Subject, and Body criteria are strictly met by the SQL query.
    # However, we should double check the specific values returned in the JSON for partial credit or strictness.
    
    if result.get("message_found"):
        score += 30
        feedback_parts.append("Message created successfully.")
        
        # Check 2: Recipient (20 pts)
        recipient = result.get("recipient", "")
        if recipient == "demo_provider":
            score += 20
            feedback_parts.append("Correct recipient (demo_provider).")
        else:
            feedback_parts.append(f"Incorrect recipient: '{recipient}'.")

        # Check 3: Patient Context (20 pts)
        patient_name = result.get("patient_name", "")
        # Allow case insensitive or slight variations if needed, but SQL join ensures it matches a valid pid
        if "Maria" in patient_name and "Rodriguez" in patient_name:
            score += 20
            feedback_parts.append("Correct patient linked.")
        else:
            feedback_parts.append(f"Incorrect patient linked: '{patient_name}'.")
            
        # Check 4: Subject (15 pts) - Verified by SQL, but confirming existance adds points
        score += 15 
        feedback_parts.append("Subject contained 'URGENT'.")
        
        # Check 5: Body (15 pts) - Verified by SQL
        score += 15
        feedback_parts.append("Body contained value '6.2'.")
        
    else:
        feedback_parts.append("No message found matching timestamp and content criteria.")
        # If no message found, we can't award other points. 
        # Score remains 0.

    passed = score >= 85
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }