#!/usr/bin/env python3
"""
Verifier for Chrome Autofill Address Configuration Task (autofill_address@1)
Task: Add a complete mailing address to Chrome autofill settings

Expected Address:
- Name: John Anderson
- Street: 742 Evergreen Terrace
- City: Springfield
- State: Illinois (or IL)
- ZIP: 62701
- Phone: 555-0123

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON and extract autofill.profile array
- Search for matching address entry with required fields
- Validate field values with fuzzy matching for flexibility
- Score based on number of correctly filled fields
"""

import logging
import sys
import os
import json
import re
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import (
        setup_chrome_verification,
        cleanup_verification_temp,
        parse_preferences
    )
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass


# Expected address data for verification
EXPECTED_ADDRESS = {
    'name': 'John Anderson',
    'street': '742 Evergreen Terrace',
    'city': 'Springfield',
    'state_full': 'Illinois',
    'state_abbr': 'IL',
    'zip': '62701',
    'phone': '555-0123',
    'phone_digits': '5550123'
}


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for autofill_address@1 task.
    
    Verifies that a complete mailing address has been added to Chrome autofill.
    
    Args:
        traj: Trajectory data (not used for this verification)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with passed (bool), score (int 0-100), and feedback (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in environment"
        }

    try:
        # Extract autofill addresses from Chrome Preferences
        addresses, error_msg = extract_autofill_addresses(copy_from_env)
        
        if addresses is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to extract autofill addresses: {error_msg}"
            }
        
        if len(addresses) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No autofill addresses found. Please add an address in Chrome Settings → Autofill and passwords → Addresses and more."
            }
        
        # Find and validate the expected address
        result = validate_autofill_address(addresses, EXPECTED_ADDRESS)
        
        # Clean up
        cleanup_verification_temp()
        
        return result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def extract_autofill_addresses(copy_from_env) -> Tuple[Optional[List[Dict]], str]:
    """
    Extract autofill address entries from Chrome Preferences file.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (addresses_list or None, error_message)
    """
    temp_file = None
    try:
        # Try using utilities if available
        if UTILS_AVAILABLE:
            success, files, error = setup_chrome_verification(
                copy_from_env,
                ["Preferences"],
                user="ga",
                profile="Default"
            )
            
            if success:
                prefs_path = files["Preferences"]
                prefs = parse_preferences(prefs_path)
                cleanup_verification_temp()
                
                if prefs:
                    addresses = extract_addresses_from_prefs(prefs)
                    return addresses, ""
                else:
                    logger.warning("Utility-based extraction returned empty preferences")
        
        # Fallback: Manual extraction
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        # Try multiple possible locations
        paths_to_try = [
            "/tmp/chrome_preferences_autofill.json",
            "/tmp/Preferences",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        prefs = None
        for container_path in paths_to_try:
            try:
                logger.info(f"Trying to copy Preferences from: {container_path}")
                copy_from_env(container_path, temp_file.name)
                
                # Check if file was copied successfully
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    with open(temp_file.name, 'r', encoding='utf-8') as f:
                        prefs = json.load(f)
                    logger.info(f"✓ Successfully loaded Preferences from: {container_path}")
                    break
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if prefs is None:
            return None, "Could not copy Preferences file from any known location"
        
        # Extract addresses from preferences
        addresses = extract_addresses_from_prefs(prefs)
        
        return addresses, ""
        
    except json.JSONDecodeError as e:
        return None, f"Failed to parse Preferences JSON: {e}"
    except Exception as e:
        return None, f"Error extracting autofill addresses: {e}"
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def extract_addresses_from_prefs(prefs: Dict) -> List[Dict]:
    """
    Extract address entries from Chrome Preferences JSON structure.
    
    Chrome stores autofill data in multiple possible structures:
    - autofill.profile (array of address objects)
    - Each field may be a string or an array of strings
    
    Args:
        prefs: Parsed Chrome Preferences dictionary
        
    Returns:
        List of address dictionaries with normalized field names
    """
    addresses = []
    
    # Navigate to autofill.profile
    autofill = prefs.get('autofill', {})
    profiles = autofill.get('profile', [])
    
    if not isinstance(profiles, list):
        logger.warning(f"autofill.profile is not a list: {type(profiles)}")
        return addresses
    
    logger.info(f"Found {len(profiles)} autofill profile(s)")
    
    for idx, profile in enumerate(profiles):
        if not isinstance(profile, dict):
            continue
        
        # Extract and normalize address fields
        # Chrome may store fields as strings or arrays
        address = {
            'name': extract_field_value(profile, ['name_full', 'name']),
            'name_first': extract_field_value(profile, ['name_first']),
            'name_last': extract_field_value(profile, ['name_last']),
            'street': extract_field_value(profile, ['address_home_line1', 'street_address']),
            'street2': extract_field_value(profile, ['address_home_line2']),
            'city': extract_field_value(profile, ['address_home_city', 'city']),
            'state': extract_field_value(profile, ['address_home_state', 'state']),
            'zip': extract_field_value(profile, ['address_home_zip', 'postal_code', 'zip']),
            'country': extract_field_value(profile, ['address_home_country', 'country']),
            'phone': extract_field_value(profile, ['phone_home_whole_number', 'phone']),
            'guid': profile.get('guid', ''),
        }
        
        # Log the extracted address for debugging
        logger.info(f"Address {idx + 1}: name={address['name']}, street={address['street']}, "
                   f"city={address['city']}, state={address['state']}, zip={address['zip']}")
        
        addresses.append(address)
    
    return addresses


def extract_field_value(profile: Dict, field_names: List[str]) -> str:
    """
    Extract field value from profile, handling both string and array formats.
    
    Args:
        profile: Profile dictionary
        field_names: List of possible field names to try
        
    Returns:
        Extracted string value or empty string
    """
    for field_name in field_names:
        if field_name in profile:
            value = profile[field_name]
            
            # Handle array format (Chrome sometimes stores as arrays)
            if isinstance(value, list):
                if len(value) > 0:
                    return str(value[0])
                else:
                    return ""
            
            # Handle string format
            elif isinstance(value, str):
                return value
            
            # Handle other types
            else:
                return str(value)
    
    return ""


def normalize_string(s: str) -> str:
    """Normalize string for comparison (lowercase, remove extra whitespace)"""
    return re.sub(r'\s+', ' ', s.lower().strip())


def normalize_phone(phone: str) -> str:
    """Extract digits from phone number for comparison"""
    return ''.join(filter(str.isdigit, phone))


def validate_autofill_address(addresses: List[Dict], expected: Dict) -> Dict[str, Any]:
    """
    Validate that the expected address exists in the autofill addresses.
    
    Uses fuzzy matching to accommodate minor variations in formatting.
    
    Scoring:
    - 100%: All 6 core fields match (name, street, city, state, zip, phone)
    - 85-99%: 5/6 core fields match
    - 70-84%: 4/6 core fields match
    - 50-69%: 3/6 core fields match
    - <50%: <3 core fields match
    
    Pass threshold: 75% (at least 5/6 fields)
    
    Args:
        addresses: List of address dictionaries from Chrome
        expected: Expected address values
        
    Returns:
        Verification result with passed, score, and feedback
    """
    best_match = None
    best_score = 0
    best_matches_detail = {}
    
    # Check each address for the best match
    for addr in addresses:
        matches = {}
        match_count = 0
        
        # Check name (full name or first+last)
        addr_name_normalized = normalize_string(addr['name'])
        expected_name_normalized = normalize_string(expected['name'])
        
        name_match = False
        if expected_name_normalized in addr_name_normalized or addr_name_normalized in expected_name_normalized:
            name_match = True
        elif addr['name_first'] and addr['name_last']:
            full_name_from_parts = normalize_string(f"{addr['name_first']} {addr['name_last']}")
            if expected_name_normalized == full_name_from_parts:
                name_match = True
        
        matches['name'] = name_match
        if name_match:
            match_count += 1
        
        # Check street address
        addr_street_normalized = normalize_string(addr['street'])
        expected_street_normalized = normalize_string(expected['street'])
        street_match = expected_street_normalized in addr_street_normalized or addr_street_normalized in expected_street_normalized
        matches['street'] = street_match
        if street_match:
            match_count += 1
        
        # Check city
        addr_city_normalized = normalize_string(addr['city'])
        expected_city_normalized = normalize_string(expected['city'])
        city_match = addr_city_normalized == expected_city_normalized
        matches['city'] = city_match
        if city_match:
            match_count += 1
        
        # Check state (handle full name or abbreviation)
        addr_state_normalized = normalize_string(addr['state'])
        state_match = (
            addr_state_normalized == normalize_string(expected['state_full']) or
            addr_state_normalized == normalize_string(expected['state_abbr'])
        )
        matches['state'] = state_match
        if state_match:
            match_count += 1
        
        # Check ZIP code
        addr_zip = addr['zip'].strip()
        zip_match = addr_zip == expected['zip']
        matches['zip'] = zip_match
        if zip_match:
            match_count += 1
        
        # Check phone number (normalize by removing non-digits)
        addr_phone_digits = normalize_phone(addr['phone'])
        expected_phone_digits = expected['phone_digits']
        phone_match = addr_phone_digits == expected_phone_digits or expected_phone_digits in addr_phone_digits
        matches['phone'] = phone_match
        if phone_match:
            match_count += 1
        
        # Keep track of best match
        if match_count > best_score:
            best_score = match_count
            best_match = addr
            best_matches_detail = matches
    
    # Calculate final score and generate feedback
    total_fields = 6
    score = int((best_score / total_fields) * 100)
    passed = score >= 75  # Need at least 5/6 fields (83%)
    
    feedback_parts = []
    feedback_parts.append(f"Autofill Address Verification: {best_score}/{total_fields} fields matched")
    feedback_parts.append("")
    
    if best_match:
        feedback_parts.append("Field-by-field validation:")
        feedback_parts.append(f"  ✓ Name: {'✓ MATCH' if best_matches_detail['name'] else '✗ MISMATCH'}")
        feedback_parts.append(f"    Expected: {expected['name']}")
        feedback_parts.append(f"    Found: {best_match['name']}")
        
        feedback_parts.append(f"  ✓ Street: {'✓ MATCH' if best_matches_detail['street'] else '✗ MISMATCH'}")
        feedback_parts.append(f"    Expected: {expected['street']}")
        feedback_parts.append(f"    Found: {best_match['street']}")
        
        feedback_parts.append(f"  ✓ City: {'✓ MATCH' if best_matches_detail['city'] else '✗ MISMATCH'}")
        feedback_parts.append(f"    Expected: {expected['city']}")
        feedback_parts.append(f"    Found: {best_match['city']}")
        
        feedback_parts.append(f"  ✓ State: {'✓ MATCH' if best_matches_detail['state'] else '✗ MISMATCH'}")
        feedback_parts.append(f"    Expected: {expected['state_full']} or {expected['state_abbr']}")
        feedback_parts.append(f"    Found: {best_match['state']}")
        
        feedback_parts.append(f"  ✓ ZIP Code: {'✓ MATCH' if best_matches_detail['zip'] else '✗ MISMATCH'}")
        feedback_parts.append(f"    Expected: {expected['zip']}")
        feedback_parts.append(f"    Found: {best_match['zip']}")
        
        feedback_parts.append(f"  ✓ Phone: {'✓ MATCH' if best_matches_detail['phone'] else '✗ MISMATCH'}")
        feedback_parts.append(f"    Expected: {expected['phone']}")
        feedback_parts.append(f"    Found: {best_match['phone']}")
    else:
        feedback_parts.append("No matching address found in autofill data.")
    
    feedback_parts.append("")
    feedback_parts.append(f"Score: {score}%")
    
    if passed:
        if score == 100:
            feedback_parts.append("✅ Perfect! All address fields correctly configured.")
        else:
            feedback_parts.append("✅ Address successfully added with minor variations.")
    else:
        missing_fields = [field for field, matched in best_matches_detail.items() if not matched]
        feedback_parts.append(f"❌ Address incomplete. Missing or incorrect fields: {', '.join(missing_fields)}")
    
    feedback = "\n".join(feedback_parts)
    
    logger.info(f"Verification complete: passed={passed}, score={score}, matches={best_score}/{total_fields}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "total_addresses_found": len(addresses),
            "best_match_score": best_score,
            "field_matches": best_matches_detail
        }
    }
