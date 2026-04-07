#!/usr/bin/env python3
"""
Verifier for Add External Provider task in OpenEMR

Verifies that an external referring physician was added to the Address Book
with the correct details.

Uses copy_from_env to read pre-exported verification data from the container.
"""

import sys
import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_phone(phone_str):
    """Normalize phone number for comparison (extract digits only)."""
    if not phone_str:
        return ""
    return re.sub(r'\D', '', str(phone_str))


def normalize_string(s):
    """Normalize string for comparison (lowercase, strip whitespace)."""
    if not s:
        return ""
    return str(s).lower().strip()


def verify_add_external_provider(traj, env_info, task_info):
    """
    Verify that the external provider was added to OpenEMR's Address Book.
    
    Expected provider details (from task metadata):
    - Name: Sarah Mitchell
    - City: Springfield
    - State: MA
    - Zip: 01103
    - Phone: (413) 555-7890
    - Specialty: Gastroenterology
    - NPI: 1234567893
    
    Scoring (100 points total):
    - Entry exists with matching criteria: 30 points
    - Correct name (Mitchell): 15 points
    - Correct city/state (Springfield, MA): 15 points
    - Correct phone (413-555-7890): 10 points
    - Correct address (456 Medical Center): 10 points
    - Specialty documented (Gastroenterology): 10 points
    - Newly created during task: 10 points
    
    Pass threshold: 60 points with entry_exists
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Copy function not available"
        }
    
    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected = metadata.get('expected_provider', {})
    
    # Default expected values
    expected_name = expected.get('name', 'Sarah Mitchell')
    expected_city = expected.get('city', 'Springfield')
    expected_state = expected.get('state', 'MA')
    expected_zip = expected.get('zip', '01103')
    expected_phone = expected.get('phone', '413-555-7890')
    expected_street = expected.get('street', '456 Medical Center Drive')
    expected_specialty = expected.get('specialty', 'Gastroenterology')
    expected_npi = expected.get('npi', '1234567893')
    
    # Normalize expected values
    expected_phone_digits = normalize_phone(expected_phone)
    expected_name_lower = normalize_string(expected_name)
    expected_city_lower = normalize_string(expected_city)
    expected_state_lower = normalize_string(expected_state)
    expected_specialty_lower = normalize_string(expected_specialty)
    
    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/add_external_provider_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
        
        score = 0
        feedback_parts = []
        subscores = {
            "entry_exists": False,
            "correct_name": False,
            "correct_city_state": False,
            "correct_phone": False,
            "correct_address": False,
            "specialty_documented": False,
            "newly_created": False
        }
        
        # Extract data from result
        entry_found = result.get('entry_found', False)
        new_entry_created = result.get('new_entry_created', False)
        entry = result.get('entry', {})
        
        initial_addr = result.get('initial_address_count', 0)
        current_addr = result.get('current_address_count', 0)
        initial_user = result.get('initial_user_abook_count', 0)
        current_user = result.get('current_user_abook_count', 0)
        
        logger.info(f"Entry found: {entry_found}, New entry: {new_entry_created}")
        logger.info(f"Address counts: {initial_addr} -> {current_addr}")
        logger.info(f"User abook counts: {initial_user} -> {current_user}")
        logger.info(f"Entry data: {entry}")
        
        # CRITERION 1: Entry exists (30 points)
        if entry_found:
            score += 30
            subscores["entry_exists"] = True
            feedback_parts.append("✓ Address book entry found")
        else:
            feedback_parts.append("✗ No matching address book entry found")
            # Check if any entries were added at all
            if current_addr > initial_addr or current_user > initial_user:
                feedback_parts.append("Note: New entry was added but doesn't match expected criteria")
            else:
                feedback_parts.append("Note: No new entries were added to the database")
            
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }
        
        # CRITERION 2: Correct name (15 points)
        entry_name = normalize_string(entry.get('name', ''))
        # Check if "mitchell" appears in the name
        if 'mitchell' in entry_name or 'sarah' in entry_name:
            score += 15
            subscores["correct_name"] = True
            feedback_parts.append(f"✓ Name contains expected value (found: {entry.get('name', 'N/A')})")
        else:
            feedback_parts.append(f"✗ Name mismatch (expected contains 'Mitchell', got: {entry.get('name', 'N/A')})")
        
        # CRITERION 3: Correct city/state (15 points)
        entry_city = normalize_string(entry.get('city', ''))
        entry_state = normalize_string(entry.get('state', ''))
        
        city_match = expected_city_lower in entry_city or entry_city in expected_city_lower
        state_match = (entry_state == expected_state_lower or 
                       entry_state == 'massachusetts' or 
                       expected_state_lower in entry_state)
        
        if city_match and state_match:
            score += 15
            subscores["correct_city_state"] = True
            feedback_parts.append(f"✓ City/State correct ({entry.get('city', 'N/A')}, {entry.get('state', 'N/A')})")
        elif city_match or state_match:
            score += 7  # Partial credit
            feedback_parts.append(f"~ City/State partial match ({entry.get('city', 'N/A')}, {entry.get('state', 'N/A')})")
        else:
            feedback_parts.append(f"✗ City/State mismatch (expected: {expected_city}, {expected_state})")
        
        # CRITERION 4: Correct phone (10 points)
        entry_phone = normalize_phone(entry.get('phone', ''))
        if entry_phone and (expected_phone_digits in entry_phone or entry_phone in expected_phone_digits):
            score += 10
            subscores["correct_phone"] = True
            feedback_parts.append(f"✓ Phone correct ({entry.get('phone', 'N/A')})")
        elif entry_phone and len(entry_phone) >= 7:
            # Partial credit if they entered a phone number
            score += 3
            feedback_parts.append(f"~ Phone entered but doesn't match expected ({entry.get('phone', 'N/A')})")
        else:
            feedback_parts.append(f"✗ Phone not found or incorrect")
        
        # CRITERION 5: Correct address (10 points)
        entry_street = normalize_string(entry.get('street', ''))
        # Check for key parts of address
        address_parts_found = 0
        if '456' in entry_street:
            address_parts_found += 1
        if 'medical' in entry_street:
            address_parts_found += 1
        if 'center' in entry_street:
            address_parts_found += 1
        
        if address_parts_found >= 2:
            score += 10
            subscores["correct_address"] = True
            feedback_parts.append(f"✓ Address correct ({entry.get('street', 'N/A')})")
        elif address_parts_found == 1:
            score += 5
            feedback_parts.append(f"~ Address partial match ({entry.get('street', 'N/A')})")
        elif entry_street:
            score += 2
            feedback_parts.append(f"~ Street address entered but doesn't match expected")
        else:
            feedback_parts.append(f"✗ Street address not found")
        
        # CRITERION 6: Specialty documented (10 points)
        entry_specialty = normalize_string(entry.get('specialty', ''))
        entry_org = normalize_string(entry.get('organization', ''))
        
        # Check if gastroenterology is mentioned anywhere
        gastro_found = ('gastro' in entry_specialty or 
                        'gastro' in entry_org or
                        'gi ' in entry_specialty or 
                        'gi ' in entry_org)
        
        if gastro_found:
            score += 10
            subscores["specialty_documented"] = True
            feedback_parts.append(f"✓ Specialty documented (Gastroenterology)")
        elif entry_specialty or entry_org:
            score += 3
            feedback_parts.append(f"~ Specialty/Org entered but not Gastroenterology ({entry.get('specialty', '')} / {entry.get('organization', '')})")
        else:
            feedback_parts.append(f"✗ Specialty not documented")
        
        # CRITERION 7: Newly created during task (10 points)
        if new_entry_created:
            score += 10
            subscores["newly_created"] = True
            feedback_parts.append("✓ Entry newly created during task")
        else:
            feedback_parts.append("~ Could not confirm entry was newly created")
        
        # Determine pass/fail
        # Must have entry_exists (30 pts) and reasonable additional criteria
        passed = score >= 60 and subscores["entry_exists"]
        
        # Build final feedback
        feedback = " | ".join(feedback_parts)
        
        logger.info(f"Final score: {score}/100, Passed: {passed}")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores,
            "details": {
                "entry_found": entry_found,
                "entry_data": entry,
                "new_entry_created": new_entry_created,
                "counts": {
                    "addresses": {"initial": initial_addr, "current": current_addr},
                    "users_abook": {"initial": initial_user, "current": current_user}
                }
            }
        }
        
    except FileNotFoundError:
        logger.error("Result file not found - export may have failed")
        return {
            "passed": False,
            "score": 0,
            "feedback": "Verification failed: Could not find exported result file. The export script may have failed.",
            "subscores": {}
        }
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification failed: Could not parse result file - {str(e)}",
            "subscores": {}
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
            "subscores": {}
        }