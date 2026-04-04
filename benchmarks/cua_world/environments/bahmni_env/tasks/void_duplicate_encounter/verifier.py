#!/usr/bin/env python3
"""
Verifier for void_duplicate_encounter task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_void_duplicate_encounter(traj, env_info, task_info):
    """
    Verify that exactly one of the duplicate encounters was voided.
    
    Criteria:
    1. Exactly one encounter from the pair is voided (50 pts)
    2. The other encounter is active/not voided (30 pts)
    3. The voided encounter has a void reason (10 pts)
    4. The patient record itself is NOT voided (10 pts)
    
    Pass threshold: 80 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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
            
    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Error during export: {result['error']}"}

    encounters = result.get("encounters", [])
    patient_voided = result.get("patient_voided", False)
    
    if len(encounters) != 2:
        return {"passed": False, "score": 0, "feedback": f"Expected 2 tracked encounters, found {len(encounters)}"}

    score = 0
    feedback_parts = []
    
    # Analyze encounters
    voided_count = sum(1 for e in encounters if e.get("voided"))
    active_count = sum(1 for e in encounters if not e.get("voided"))
    reasons = [e.get("voidReason") for e in encounters if e.get("voided")]
    has_reason = any(r and len(str(r).strip()) > 0 for r in reasons)

    # Criterion 1: Exactly one duplicate voided (50 pts)
    if voided_count == 1:
        score += 50
        feedback_parts.append("Correctly voided exactly one duplicate")
    elif voided_count == 2:
        feedback_parts.append("FAIL: Both encounters were voided")
    else:
        feedback_parts.append("FAIL: No encounters were voided")

    # Criterion 2: One remains active (30 pts)
    if active_count == 1:
        score += 30
        feedback_parts.append("One encounter remains active (data preserved)")
    
    # Criterion 3: Void reason provided (10 pts)
    if has_reason:
        score += 10
        feedback_parts.append("Void reason provided")
    elif voided_count > 0:
        feedback_parts.append("WARNING: No void reason provided")

    # Criterion 4: Patient Integrity (10 pts)
    if not patient_voided:
        score += 10
        feedback_parts.append("Patient record intact")
    else:
        feedback_parts.append("CRITICAL FAIL: Patient record was voided")
        score = 0 # Automatic fail if patient is deleted

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }