#!/usr/bin/env python3
"""
Verifier for add_pharmacy task in Oscar EMR.

Verifies that:
1. A pharmacy record with the correct name exists.
2. The address, phone, fax, and email details are correct.
3. The record was actually created (count increased).
"""

import json
import logging
import tempfile
import os
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_phone(phone_str):
    """Normalize phone/fax numbers to digits only for comparison."""
    if not phone_str:
        return ""
    return re.sub(r'\D', '', str(phone_str))

def verify_add_pharmacy(traj, env_info, task_info):
    """
    Verify that the pharmacy was added with correct details.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Expected values
    exp_name = metadata.get("expected_name", "Lakeshore Compounding Pharmacy")
    exp_addr_part = metadata.get("expected_address_part", "742 Lakeshore")
    exp_city = metadata.get("expected_city", "Toronto")
    exp_prov = metadata.get("expected_province", "ON")
    exp_postal = metadata.get("expected_postal", "M5V 1A5")
    exp_phone = metadata.get("expected_phone", "416-555-0198")
    exp_fax = metadata.get("expected_fax", "416-555-0199")
    exp_email = metadata.get("expected_email", "rx@lakeshorecompounding.ca")

    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    max_score = 100
    feedback_parts = []
    
    found = result.get("found", False)
    pharmacy = result.get("pharmacy", {})
    initial_count = result.get("initial_count", 0)
    current_count = result.get("current_count", 0)

    # Criterion 1: Record Exists (25 pts)
    if found:
        score += 25
        feedback_parts.append(f"Pharmacy record found: '{pharmacy.get('name')}'")
    else:
        feedback_parts.append("No pharmacy record found matching name")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Correct Address (15 pts)
    addr = pharmacy.get("address", "")
    city = pharmacy.get("city", "")
    if exp_addr_part.lower() in addr.lower() and exp_city.lower() in city.lower():
        score += 15
        feedback_parts.append("Address correct")
    else:
        feedback_parts.append(f"Address mismatch (got '{addr}, {city}')")

    # Criterion 3: Correct Province/Postal (10 pts)
    prov = pharmacy.get("province", "")
    postal = pharmacy.get("postal", "")
    # Allow loose postal matching (ignore spaces)
    postal_norm = postal.replace(" ", "").upper()
    exp_postal_norm = exp_postal.replace(" ", "").upper()
    
    if prov.upper() == exp_prov.upper() and exp_postal_norm in postal_norm:
        score += 10
        feedback_parts.append("Province/Postal correct")
    else:
        feedback_parts.append(f"Province/Postal mismatch (got '{prov}, {postal}')")

    # Criterion 4: Phone Number (15 pts)
    phone = pharmacy.get("phone", "")
    if normalize_phone(exp_phone) in normalize_phone(phone):
        score += 15
        feedback_parts.append("Phone correct")
    else:
        feedback_parts.append(f"Phone mismatch (got '{phone}')")

    # Criterion 5: Fax Number (15 pts)
    fax = pharmacy.get("fax", "")
    if normalize_phone(exp_fax) in normalize_phone(fax):
        score += 15
        feedback_parts.append("Fax correct")
    else:
        feedback_parts.append(f"Fax mismatch (got '{fax}')")

    # Criterion 6: Email (10 pts)
    email = pharmacy.get("email", "")
    if exp_email.lower() == email.lower():
        score += 10
        feedback_parts.append("Email correct")
    else:
        feedback_parts.append(f"Email mismatch (got '{email}')")

    # Criterion 7: Anti-Gaming / New Record (10 pts)
    # Check if count increased or if we can verify it's a new ID (not strictly checked here but implied by setup cleaning)
    if current_count > initial_count:
        score += 10
        feedback_parts.append("New record creation verified")
    else:
        feedback_parts.append("Warning: Total pharmacy count did not increase")

    passed = (score >= 65 and found)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }