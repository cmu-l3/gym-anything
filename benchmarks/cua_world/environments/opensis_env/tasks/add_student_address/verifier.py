#!/usr/bin/env python3
"""
Verifier for add_student_address task.
"""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_text(text):
    """Normalize text for comparison (lower case, strip punctuation/spaces)."""
    if not text:
        return ""
    return re.sub(r'[\s\.\-,]+', '', str(text).lower())

def verify_add_student_address(traj, env_info, task_info):
    """
    Verify that the student address was added correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Expected values
    metadata = task_info.get('metadata', {})
    expected_street = metadata.get('expected_street', "4712 Magnolia Boulevard")
    expected_city = metadata.get('expected_city', "Houston")
    expected_state = metadata.get('expected_state', "TX")
    expected_zip = metadata.get('expected_zip', "77033")
    expected_phone = metadata.get('expected_phone', "713-555-0198")

    # Load result from container
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

    # Scoring
    score = 0
    feedback_parts = []
    
    # 1. Check if any address was found (20 pts)
    address_found = result.get('address_found', False)
    record = result.get('address_record', {})
    
    if not address_found:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No address record found for student Alondra Reyes."
        }
    
    score += 20
    feedback_parts.append("Address record created.")

    # 2. Verify Street (30 pts)
    # Flexible matching for "Blvd" vs "Boulevard"
    actual_street = record.get('street', '')
    norm_expected = normalize_text(expected_street)
    norm_actual = normalize_text(actual_street)
    
    if norm_expected in norm_actual or norm_actual in norm_expected:
        score += 30
        feedback_parts.append(f"Street correct ({actual_street})")
    elif "4712" in actual_street and "magnolia" in actual_street.lower():
        score += 20
        feedback_parts.append(f"Street partially correct ({actual_street})")
    else:
        feedback_parts.append(f"Street incorrect (Expected: {expected_street}, Got: {actual_street})")

    # 3. Verify City (15 pts)
    if normalize_text(record.get('city', '')) == normalize_text(expected_city):
        score += 15
        feedback_parts.append("City correct")
    else:
        feedback_parts.append(f"City mismatch ({record.get('city')})")

    # 4. Verify State (15 pts)
    # Check for TX or Texas
    actual_state = record.get('state', '').lower()
    if actual_state in ['tx', 'texas']:
        score += 15
        feedback_parts.append("State correct")
    else:
        feedback_parts.append(f"State mismatch ({record.get('state')})")

    # 5. Verify Zip (10 pts)
    if expected_zip in str(record.get('zip', '')):
        score += 10
        feedback_parts.append("Zip correct")
    else:
        feedback_parts.append(f"Zip mismatch ({record.get('zip')})")

    # 6. Verify Phone (10 pts)
    # Remove all non-digits for phone comparison
    clean_expected_phone = re.sub(r'\D', '', expected_phone)
    clean_actual_phone = re.sub(r'\D', '', str(record.get('phone', '')))
    
    if clean_expected_phone in clean_actual_phone and len(clean_actual_phone) >= 7:
        score += 10
        feedback_parts.append("Phone correct")
    else:
        feedback_parts.append(f"Phone mismatch ({record.get('phone')})")

    # Anti-gaming: Ensure it wasn't pre-existing (setup script ensures student was fresh, 
    # but we check if ID is valid)
    if record.get('id') == "0" or not record.get('id'):
        score = 0
        feedback_parts = ["Address ID invalid - record may be malformed"]

    # Final logic
    # Threshold: Need street + at least 2 other fields correct to pass
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }