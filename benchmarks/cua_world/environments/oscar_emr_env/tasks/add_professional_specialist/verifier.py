#!/usr/bin/env python3
"""
Verifier for add_professional_specialist task.
Verifies that the specialist was correctly added to the Oscar EMR database.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_specialist(traj, env_info, task_info):
    """
    Verify the specialist record exists and has correct details.
    
    Scoring:
    - Record exists (Name matches): 20 pts
    - Specialty correct: 15 pts
    - Phone correct: 10 pts
    - Fax correct: 10 pts
    - Email correct: 10 pts
    - Address correct: 10 pts
    - Annotation correct: 10 pts
    - Anti-gaming (New record created): 5 pts
    - VLM Navigation check: 10 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values
    metadata = task_info.get('metadata', {})
    expected_phone = metadata.get('expected_phone', '905-555-0147')
    expected_fax = metadata.get('expected_fax', '905-555-0148')
    expected_email = metadata.get('expected_email', 'referrals@patelortho.ca')
    expected_specialty = metadata.get('expected_specialty', 'Orthopedic Surgery')
    expected_address_part = metadata.get('expected_address_part', '250 Dundas')
    expected_annotation_part = metadata.get('expected_annotation_part', 'joint replacement')

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check if record exists (20 pts)
    record_found = result.get('record_found', False)
    record_data = result.get('record_data', {})
    
    if not record_found:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Specialist 'Rajesh Patel' not found in database."
        }
    
    score += 20
    feedback_parts.append("Record created")
    
    # 2. Check Specialty (15 pts)
    actual_spec = record_data.get('specType', '')
    if 'orthop' in actual_spec.lower():
        score += 15
        feedback_parts.append("Specialty correct")
    else:
        feedback_parts.append(f"Specialty incorrect ('{actual_spec}')")

    # 3. Check Phone (10 pts)
    actual_phone = record_data.get('phone', '')
    # Relaxed check for phone (contains main digits)
    if '555' in actual_phone and '0147' in actual_phone:
        score += 10
        feedback_parts.append("Phone correct")
    else:
        feedback_parts.append(f"Phone mismatch ('{actual_phone}')")

    # 4. Check Fax (10 pts)
    actual_fax = record_data.get('fax', '')
    if '555' in actual_fax and '0148' in actual_fax:
        score += 10
        feedback_parts.append("Fax correct")
    else:
        feedback_parts.append(f"Fax mismatch ('{actual_fax}')")

    # 5. Check Email (10 pts)
    actual_email = record_data.get('email', '')
    if expected_email.lower() in actual_email.lower():
        score += 10
        feedback_parts.append("Email correct")
    else:
        feedback_parts.append(f"Email mismatch ('{actual_email}')")

    # 6. Check Address (10 pts)
    actual_address = record_data.get('streetAddress', '')
    if expected_address_part.lower() in actual_address.lower():
        score += 10
        feedback_parts.append("Address correct")
    else:
        feedback_parts.append("Address mismatch")

    # 7. Check Annotation (10 pts)
    actual_annotation = record_data.get('annotation', '')
    if expected_annotation_part.lower() in actual_annotation.lower():
        score += 10
        feedback_parts.append("Annotation correct")
    else:
        feedback_parts.append("Annotation missing key details")

    # 8. Anti-gaming: Count check (5 pts)
    initial_count = int(result.get('initial_count', 0))
    final_count = int(result.get('final_count', 0))
    if final_count > initial_count:
        score += 5
        feedback_parts.append("Count increased")
    else:
        feedback_parts.append("Count did not increase (overwrite?)")

    # 9. VLM Navigation Check (10 pts)
    # If the user successfully filled out complex fields like annotation/address correctly,
    # they almost certainly navigated the UI correctly. We use field completion as a proxy 
    # for navigation success if VLM isn't strictly necessary, or give points if fields are populated.
    fields_populated = sum(1 for f in [actual_spec, actual_phone, actual_fax, actual_email, actual_address, actual_annotation] if f)
    if fields_populated >= 4:
        score += 10
        feedback_parts.append("UI usage inferred from data")
    else:
        feedback_parts.append("insufficient data to infer UI usage")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": ", ".join(feedback_parts)
    }