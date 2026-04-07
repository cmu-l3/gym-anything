#!/usr/bin/env python3
"""
Verifier for update_school_info task.
Verifies that the school address and contact info were updated correctly in the database.
"""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_phone(phone_str):
    """Remove non-digit characters for comparison."""
    if not phone_str:
        return ""
    return re.sub(r'\D', '', str(phone_str))

def verify_update_school_info(traj, env_info, task_info):
    """
    Verify the agent updated the school information correctly.
    
    Scoring:
    - 20 pts: Address
    - 20 pts: City
    - 20 pts: State
    - 20 pts: Zip
    - 20 pts: Phone
    
    Anti-gaming:
    - Checks if values are different from initial values.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected = {
        "address": metadata.get("expected_address", "456 Oak Avenue"),
        "city": metadata.get("expected_city", "Springfield"),
        "state": metadata.get("expected_state", "IL"),
        "zipcode": metadata.get("expected_zip", "62704"),
        "phone": metadata.get("expected_phone", "217-555-9876")
    }
    
    initial = {
        "address": metadata.get("initial_address", "123 Main St"),
        "city": metadata.get("initial_city", "City"),
        "state": metadata.get("initial_state", "ST"),
        "zipcode": metadata.get("initial_zip", "12345"),
        "phone": metadata.get("initial_phone", "555-1234")
    }

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    actual = result.get('school_data', {})
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Check 1: Anti-gaming - Did anything change?
    # If all fields still match initial values, immediate fail.
    unchanged_fields = 0
    total_fields = 0
    for key in initial:
        # Simple string compare for initial check
        if str(actual.get(key, "")).strip() == str(initial.get(key, "")).strip():
            unchanged_fields += 1
        total_fields += 1
    
    if unchanged_fields == total_fields:
        return {
            "passed": False,
            "score": 0, 
            "feedback": "No changes detected. All fields match the starting state."
        }

    # Check 2: Verify each field (20 points each)
    
    # Address (Case insensitive, whitespace trimmed)
    if actual.get("address", "").strip().lower() == expected["address"].strip().lower():
        score += 20
        feedback_parts.append("Address: OK")
    else:
        feedback_parts.append(f"Address: Fail (Expected '{expected['address']}', Got '{actual.get('address')}')")

    # City (Case insensitive)
    if actual.get("city", "").strip().lower() == expected["city"].strip().lower():
        score += 20
        feedback_parts.append("City: OK")
    else:
        feedback_parts.append(f"City: Fail (Got '{actual.get('city')}')")

    # State (Case insensitive)
    if actual.get("state", "").strip().lower() == expected["state"].strip().lower():
        score += 20
        feedback_parts.append("State: OK")
    else:
        feedback_parts.append(f"State: Fail (Got '{actual.get('state')}')")

    # Zipcode (Exact match string)
    if actual.get("zipcode", "").strip() == expected["zipcode"].strip():
        score += 20
        feedback_parts.append("Zip: OK")
    else:
        feedback_parts.append(f"Zip: Fail (Got '{actual.get('zipcode')}')")

    # Phone (Normalize digits)
    if normalize_phone(actual.get("phone", "")) == normalize_phone(expected["phone"]):
        score += 20
        feedback_parts.append("Phone: OK")
    else:
        feedback_parts.append(f"Phone: Fail (Expected '{expected['phone']}', Got '{actual.get('phone')}')")

    # Final Result
    passed = score >= 80  # Allow 1 minor error, but generally require correctness
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }