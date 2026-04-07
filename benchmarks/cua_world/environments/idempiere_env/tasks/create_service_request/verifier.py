#!/usr/bin/env python3
"""
Verifier for create_service_request task.
Validates if a Customer Service Request was created in iDempiere with correct details.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_service_request(traj, env_info, task_info):
    """
    Verifies the creation of a service request.
    
    Scoring Criteria:
    1. Request Record Exists (Matching Summary) - 30 pts
    2. Correct Business Partner (Joe Block) - 20 pts
    3. Priority set to High - 15 pts
    4. Confidentiality set to Customer Confidential - 10 pts
    5. Record Count Increased - 15 pts
    6. Created during task window - 10 pts
    
    Pass Threshold: 65 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_summary_frag = metadata.get('target_summary_fragment', 'paint peeling').lower()
    
    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read verification result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Parse Result Data
    initial_count = int(result.get('initial_count', 0))
    current_count = int(result.get('current_count', 0))
    found_request = result.get('found_request', False)
    details = result.get('request_details', {})
    
    # Criterion 1: Request Record Exists (30 pts)
    # The export script searches specifically for the summary + timestamp.
    # If found_request is true, it means a record with the summary fragment AND correct timestamp was found.
    if found_request:
        score += 30
        feedback_parts.append("✅ Request record created with correct summary.")
    else:
        # Check fallback
        fallback_summary = result.get('fallback_summary', '')
        if fallback_summary:
            feedback_parts.append(f"⚠️ Request created but summary mismatch (Got: '{fallback_summary}').")
            score += 10 # Partial credit for creating A request for the BP
        else:
            feedback_parts.append("❌ No matching request record found.")

    # Criterion 2: Correct Business Partner (20 pts)
    actual_bp = details.get('bpartner_id', '')
    expected_bp = details.get('expected_bp_id', '')
    
    if found_request and actual_bp and expected_bp and actual_bp == expected_bp:
        score += 20
        feedback_parts.append("✅ Correct Business Partner linked.")
    elif found_request:
        feedback_parts.append(f"❌ Incorrect Business Partner (ID: {actual_bp}, Expected: {expected_bp}).")

    # Criterion 3: Priority High (15 pts)
    # iDempiere Priority: '3' is High
    priority = details.get('priority', '')
    if found_request and priority == '3':
        score += 15
        feedback_parts.append("✅ Priority set to High.")
    elif found_request:
        feedback_parts.append(f"❌ Priority incorrect (Value: {priority}, Expected: 3/High).")

    # Criterion 4: Confidentiality (10 pts)
    # 'C' = Customer Confidential
    confidentiality = details.get('confidentiality', '')
    if found_request and confidentiality == 'C':
        score += 10
        feedback_parts.append("✅ Confidentiality set to Customer Confidential.")
    elif found_request:
        feedback_parts.append(f"❌ Confidentiality incorrect (Value: {confidentiality}, Expected: C).")

    # Criterion 5: Count Increased (15 pts)
    if current_count > initial_count:
        score += 15
        feedback_parts.append(f"✅ Total request count increased ({initial_count} -> {current_count}).")
    else:
        feedback_parts.append("❌ Total request count did not increase.")

    # Criterion 6: Created During Task (10 pts)
    # Implicitly checked by the export script query, but we award points explicitly if we found the record
    if found_request:
        score += 10
        feedback_parts.append("✅ Record timestamp confirms creation during task.")
    elif result.get('fallback_summary'):
        score += 10 # Credit if fallback was found (it also checks timestamp)
        feedback_parts.append("✅ New record timestamp verified.")

    # Final check
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }