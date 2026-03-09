#!/usr/bin/env python3
"""
Verifier for configure_billing_profile_fields task.

Scoring (100 points total):
1. Profile Renamed (20 pts): Label is "Business Customer"
2. Organization Required (30 pts): Address field override set to required
3. Phone Field Created (30 pts): field_contact_phone exists
4. Phone Field Required (20 pts): field_contact_phone is set to required

Pass threshold: 80 points
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_billing_profile_fields(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    expected_label = metadata.get('expected_profile_label', 'Business Customer')
    expected_override = metadata.get('expected_address_override_org', 'required')
    expected_field_type = metadata.get('expected_field_type', 'string')

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []
    
    # --------------------------------------------------------------------------
    # Criterion 1: Profile Renamed (20 pts)
    # --------------------------------------------------------------------------
    actual_label = result.get('profile_label', '')
    if actual_label.strip().lower() == expected_label.lower():
        score += 20
        feedback_parts.append(f"Profile renamed to '{actual_label}'")
    else:
        feedback_parts.append(f"Profile label incorrect: found '{actual_label}', expected '{expected_label}'")

    # --------------------------------------------------------------------------
    # Criterion 2: Organization Required (30 pts)
    # --------------------------------------------------------------------------
    # Navigate the nested settings structure
    address_settings = result.get('address_settings', {})
    field_overrides = address_settings.get('field_overrides', {})
    # It might be directly in overrides or nested differently depending on version, 
    # but strictly it should be key 'organization' with value 'required'
    org_setting = field_overrides.get('organization', 'optional') # default is usually optional or None
    
    if org_setting == expected_override:
        score += 30
        feedback_parts.append("Organization field set to Required")
    else:
        feedback_parts.append(f"Organization field setting incorrect: found '{org_setting}'")

    # --------------------------------------------------------------------------
    # Criterion 3: Phone Field Created (30 pts)
    # --------------------------------------------------------------------------
    field_exists = result.get('field_storage_exists', False) and result.get('field_instance_exists', False)
    field_type = result.get('field_type', '')
    
    if field_exists:
        # Check type
        if field_type == expected_field_type:
            score += 30
            feedback_parts.append("Contact Phone field created correctly")
        else:
            # Partial credit for creating field but wrong type
            score += 15
            feedback_parts.append(f"Contact Phone field created but wrong type ('{field_type}')")
    else:
        feedback_parts.append("Contact Phone field NOT found")

    # --------------------------------------------------------------------------
    # Criterion 4: Phone Field Required (20 pts)
    # --------------------------------------------------------------------------
    if field_exists:
        is_required = result.get('field_required', False)
        if is_required:
            score += 20
            feedback_parts.append("Contact Phone field is Required")
        else:
            feedback_parts.append("Contact Phone field is NOT set to Required")
    
    # --------------------------------------------------------------------------
    # Final Result
    # --------------------------------------------------------------------------
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }