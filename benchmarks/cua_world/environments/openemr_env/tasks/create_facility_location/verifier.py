#!/usr/bin/env python3
"""
Verifier for Create Facility Location task in OpenEMR

Verifies that a new facility was correctly created with all required details.
Uses multi-criteria scoring with anti-gaming checks.

Scoring (100 points total):
- Facility exists with matching name: 25 points
- Name exactly correct: 15 points
- Address complete (street, city, state, postal): 20 points
- Phone/Fax correct: 10 points
- Tax ID and NPI present: 10 points
- Service location flag set: 10 points
- Billing location flag set: 10 points

Passing threshold: 70 points with facility_exists met
"""

import sys
import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_string(s):
    """Normalize string for comparison (lowercase, strip whitespace)."""
    if not s:
        return ""
    return str(s).lower().strip()


def normalize_phone(phone):
    """Normalize phone number by removing non-digit characters."""
    if not phone:
        return ""
    return re.sub(r'\D', '', str(phone))


def fuzzy_match(actual, expected, threshold=0.8):
    """Check if actual string approximately matches expected."""
    if not actual or not expected:
        return False
    
    actual_norm = normalize_string(actual)
    expected_norm = normalize_string(expected)
    
    # Exact match
    if actual_norm == expected_norm:
        return True
    
    # Check if expected is contained in actual or vice versa
    if expected_norm in actual_norm or actual_norm in expected_norm:
        return True
    
    # Check key words match
    expected_words = set(expected_norm.split())
    actual_words = set(actual_norm.split())
    common = expected_words.intersection(actual_words)
    
    if len(common) >= len(expected_words) * threshold:
        return True
    
    return False


def verify_create_facility(traj, env_info, task_info):
    """
    Verify that a facility was correctly created in OpenEMR.
    
    Args:
        traj: Trajectory data with frames
        env_info: Environment info with copy_from_env function
        task_info: Task info with metadata containing expected values
        
    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', 'Riverside Family Medicine - East')
    expected_street = metadata.get('expected_street', '450 Harbor View Drive, Suite 200')
    expected_city = metadata.get('expected_city', 'Springfield')
    expected_state = metadata.get('expected_state', 'Massachusetts')
    expected_postal = metadata.get('expected_postal_code', '01109')
    expected_phone = metadata.get('expected_phone', '(413) 555-0192')
    expected_fax = metadata.get('expected_fax', '(413) 555-0193')
    expected_ein = metadata.get('expected_federal_ein', '04-3892156')
    expected_npi = metadata.get('expected_facility_npi', '1234567893')
    expected_service = metadata.get('expected_service_location', True)
    expected_billing = metadata.get('expected_billing_location', True)
    
    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
        
        score = 0
        feedback_parts = []
        subscores = {
            "facility_exists": False,
            "name_correct": False,
            "address_complete": False,
            "phone_fax_correct": False,
            "tax_npi_present": False,
            "service_location": False,
            "billing_location": False,
            "newly_created": False
        }
        
        # Extract data from result
        initial_count = result.get('initial_facility_count', 1)
        current_count = result.get('current_facility_count', 0)
        existing_target = result.get('existing_target_before_task', 0)
        facility_found = result.get('facility_found', False)
        facility_is_new = result.get('facility_is_new', False)
        facility = result.get('facility', {})
        
        logger.info(f"Result: initial={initial_count}, current={current_count}, found={facility_found}, new={facility_is_new}")
        logger.info(f"Facility data: {facility}")
        
        # Anti-gaming check: Was there already a matching facility?
        if existing_target > 0 and not facility_is_new:
            feedback_parts.append("WARNING: Target facility existed before task started")
            # Reduce score for gaming attempt
            score = max(0, score - 20)
        
        # CRITERION 1: Facility exists with matching name (25 points)
        if facility_found:
            actual_name = facility.get('name', '')
            if fuzzy_match(actual_name, expected_name):
                score += 25
                subscores["facility_exists"] = True
                feedback_parts.append(f"✅ Facility found: '{actual_name}'")
            else:
                # Partial credit if a facility was created but name doesn't match
                score += 10
                feedback_parts.append(f"⚠️ Facility found but name mismatch: expected '{expected_name}', got '{actual_name}'")
        else:
            feedback_parts.append(f"❌ No facility found matching '{expected_name}'")
            # Check if count increased (something was created)
            if current_count > initial_count:
                feedback_parts.append(f"Note: Facility count increased ({initial_count} → {current_count}) but target not found")
            
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }
        
        # CRITERION 2: Name exactly correct (15 points)
        actual_name = facility.get('name', '')
        if normalize_string(actual_name) == normalize_string(expected_name):
            score += 15
            subscores["name_correct"] = True
            feedback_parts.append("✅ Facility name exact match")
        elif fuzzy_match(actual_name, expected_name):
            score += 8
            feedback_parts.append(f"⚠️ Facility name close match: '{actual_name}'")
        else:
            feedback_parts.append(f"❌ Name mismatch: expected '{expected_name}'")
        
        # CRITERION 3: Address complete (20 points)
        address_score = 0
        address_checks = 0
        
        # Street
        actual_street = facility.get('street', '')
        if fuzzy_match(actual_street, expected_street):
            address_score += 5
            address_checks += 1
        else:
            feedback_parts.append(f"⚠️ Street: expected '{expected_street}', got '{actual_street}'")
        
        # City
        actual_city = facility.get('city', '')
        if normalize_string(actual_city) == normalize_string(expected_city):
            address_score += 5
            address_checks += 1
        else:
            feedback_parts.append(f"⚠️ City: expected '{expected_city}', got '{actual_city}'")
        
        # State
        actual_state = facility.get('state', '')
        if normalize_string(actual_state) == normalize_string(expected_state) or \
           normalize_string(actual_state) == 'ma':  # Accept abbreviation
            address_score += 5
            address_checks += 1
        else:
            feedback_parts.append(f"⚠️ State: expected '{expected_state}', got '{actual_state}'")
        
        # Postal code
        actual_postal = facility.get('postal_code', '')
        if normalize_string(actual_postal) == normalize_string(expected_postal):
            address_score += 5
            address_checks += 1
        else:
            feedback_parts.append(f"⚠️ Postal: expected '{expected_postal}', got '{actual_postal}'")
        
        score += address_score
        if address_checks >= 3:
            subscores["address_complete"] = True
            feedback_parts.append(f"✅ Address mostly complete ({address_checks}/4 fields)")
        elif address_checks > 0:
            feedback_parts.append(f"⚠️ Address partially complete ({address_checks}/4 fields)")
        else:
            feedback_parts.append("❌ Address fields not filled correctly")
        
        # CRITERION 4: Phone/Fax correct (10 points)
        phone_score = 0
        
        actual_phone = facility.get('phone', '')
        if normalize_phone(actual_phone) == normalize_phone(expected_phone):
            phone_score += 5
        elif actual_phone:
            phone_score += 2  # Partial credit for having a phone number
            
        actual_fax = facility.get('fax', '')
        if normalize_phone(actual_fax) == normalize_phone(expected_fax):
            phone_score += 5
        elif actual_fax:
            phone_score += 2  # Partial credit for having a fax number
        
        score += phone_score
        if phone_score >= 8:
            subscores["phone_fax_correct"] = True
            feedback_parts.append("✅ Phone/Fax numbers correct")
        elif phone_score > 0:
            feedback_parts.append(f"⚠️ Phone/Fax partially correct (score: {phone_score}/10)")
        else:
            feedback_parts.append("❌ Phone/Fax not entered or incorrect")
        
        # CRITERION 5: Tax ID and NPI present (10 points)
        tax_npi_score = 0
        
        actual_ein = facility.get('federal_ein', '')
        # Remove dashes for comparison
        if re.sub(r'\D', '', str(actual_ein)) == re.sub(r'\D', '', expected_ein):
            tax_npi_score += 5
        elif actual_ein:
            tax_npi_score += 2  # Partial credit
            
        actual_npi = facility.get('facility_npi', '')
        if str(actual_npi) == str(expected_npi):
            tax_npi_score += 5
        elif actual_npi:
            tax_npi_score += 2  # Partial credit
        
        score += tax_npi_score
        if tax_npi_score >= 8:
            subscores["tax_npi_present"] = True
            feedback_parts.append("✅ Tax ID and NPI correct")
        elif tax_npi_score > 0:
            feedback_parts.append(f"⚠️ Tax ID/NPI partially correct (score: {tax_npi_score}/10)")
        else:
            feedback_parts.append("❌ Tax ID and NPI not entered")
        
        # CRITERION 6: Service location flag (10 points)
        actual_service = facility.get('service_location', '')
        if str(actual_service) in ['1', 'true', 'True', 'yes', 'Yes']:
            score += 10
            subscores["service_location"] = True
            feedback_parts.append("✅ Service Location flag set")
        else:
            feedback_parts.append(f"❌ Service Location not set (value: '{actual_service}')")
        
        # CRITERION 7: Billing location flag (10 points)
        actual_billing = facility.get('billing_location', '')
        if str(actual_billing) in ['1', 'true', 'True', 'yes', 'Yes']:
            score += 10
            subscores["billing_location"] = True
            feedback_parts.append("✅ Billing Location flag set")
        else:
            feedback_parts.append(f"❌ Billing Location not set (value: '{actual_billing}')")
        
        # Check if facility was newly created (anti-gaming)
        if facility_is_new or current_count > initial_count:
            subscores["newly_created"] = True
            feedback_parts.append("✅ Facility was newly created during task")
        else:
            feedback_parts.append("⚠️ Cannot confirm facility was created during task")
            # Penalize potential gaming
            score = int(score * 0.7)
        
        # Determine pass/fail
        # Must have facility_exists and score >= 70
        key_criteria_met = subscores["facility_exists"]
        passed = score >= 70 and key_criteria_met
        
        return {
            "passed": passed,
            "score": min(100, score),
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "initial_count": initial_count,
                "current_count": current_count,
                "facility_data": facility
            }
        }
        
    except FileNotFoundError:
        logger.error("Result file not found")
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export may have failed"
        }
    except json.JSONDecodeError as e:
        logger.error(f"JSON decode error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to parse result JSON: {e}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }