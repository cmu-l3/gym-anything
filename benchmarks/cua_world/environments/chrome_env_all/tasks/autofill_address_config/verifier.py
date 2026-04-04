#!/usr/bin/env python3
"""
Verifier for Chrome Autofill Address Configuration Task (autofill_address_config@1)
Task: Add a complete address entry to Chrome autofill settings

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON and navigate to autofill.profiles section
- Find the most recently added/modified profile
- Validate required fields: name, street, city, postal code, country
- Check optional fields: organization, state, phone, email
- Award points based on completeness and accuracy

Scoring:
- 100%: All required fields + 3+ optional fields with correct data
- 85-99%: All required fields + some optional fields
- 70-84%: All required fields present with minor issues
- 50-69%: Address exists but incomplete or with data issues
- 0-49%: No valid address found or critical fields missing

Pass threshold: 70% (requires complete required fields)
"""

import logging
import sys
import os
import json
import tempfile
import re
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../..', 'utils'))
try:
    from chrome_verification_utils import (
        cleanup_verification_temp,
        parse_preferences
    )
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    
    def parse_preferences(path):
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    
    def cleanup_verification_temp():
        pass


# Expected address data
EXPECTED_ADDRESS = {
    "name": "John Anderson",
    "organization": "Tech Innovations Inc",
    "street": "742 Evergreen Terrace",
    "city": "Springfield",
    "state": "IL",
    "zipcode": "62701",
    "country": "US",
    "phone": "555-0123",
    "email": "john.anderson@techinnovations.com"
}


def normalize_text(text: str) -> str:
    """Normalize text for comparison (lowercase, remove extra spaces)"""
    if not text:
        return ""
    return re.sub(r'\s+', ' ', str(text).lower().strip())


def extract_autofill_profiles(prefs_data: Dict) -> List[Dict]:
    """
    Extract autofill profiles from Chrome Preferences.
    
    Args:
        prefs_data: Parsed Preferences JSON
        
    Returns:
        List of autofill profile dictionaries
    """
    try:
        # Try standard location
        autofill = prefs_data.get('autofill', {})
        profiles = autofill.get('profiles', [])
        
        if not profiles:
            # Try alternative singular form
            profile = autofill.get('profile', None)
            if profile:
                profiles = [profile]
        
        logger.info(f"Found {len(profiles)} autofill profile(s)")
        return profiles
        
    except Exception as e:
        logger.error(f"Error extracting profiles: {e}")
        return []


def find_matching_profile(profiles: List[Dict], expected: Dict) -> Optional[Dict]:
    """
    Find the profile that best matches expected address data.
    Prioritizes most recently modified profile with matching name/city.
    
    Args:
        profiles: List of autofill profiles
        expected: Expected address data
        
    Returns:
        Best matching profile or None
    """
    if not profiles:
        return None
    
    # If only one profile, return it
    if len(profiles) == 1:
        return profiles[0]
    
    # Score each profile by how well it matches
    scored_profiles = []
    for profile in profiles:
        score = 0
        
        # Check name match (most important)
        name_fields = ['name_full', 'full_name', 'name']
        for field in name_fields:
            if field in profile:
                if normalize_text(expected['name']) in normalize_text(profile[field]):
                    score += 10
                    break
        
        # Check city match
        city_fields = ['city', 'locality']
        for field in city_fields:
            if field in profile:
                if normalize_text(expected['city']) in normalize_text(profile[field]):
                    score += 5
                    break
        
        # Check zipcode match
        zip_fields = ['zipcode', 'zip', 'postal_code']
        for field in zip_fields:
            if field in profile:
                if expected['zipcode'] in str(profile[field]):
                    score += 5
                    break
        
        # Prioritize recently modified
        mod_date = profile.get('modification_date', 0)
        scored_profiles.append((score, mod_date, profile))
    
    # Sort by score (descending), then by modification date (descending)
    scored_profiles.sort(key=lambda x: (x[0], x[1]), reverse=True)
    
    best_profile = scored_profiles[0][2]
    logger.info(f"Selected profile with score {scored_profiles[0][0]}, mod_date {scored_profiles[0][1]}")
    
    return best_profile


def validate_address_field(profile: Dict, field_names: List[str], expected_value: str, 
                          exact_match: bool = False) -> Tuple[bool, str, str]:
    """
    Validate a single address field with flexible field name matching.
    
    Args:
        profile: Autofill profile to check
        field_names: List of possible field names to try
        expected_value: Expected value for the field
        exact_match: If True, requires exact match; otherwise allows substring
        
    Returns:
        Tuple of (field_present, actual_value, matched_field_name)
    """
    for field_name in field_names:
        if field_name in profile:
            actual_value = str(profile[field_name]).strip()
            
            if not actual_value:
                continue
            
            if exact_match:
                if normalize_text(actual_value) == normalize_text(expected_value):
                    return True, actual_value, field_name
            else:
                # Substring match
                if normalize_text(expected_value) in normalize_text(actual_value):
                    return True, actual_value, field_name
                # Reverse check for partial matches
                if normalize_text(actual_value) in normalize_text(expected_value):
                    return True, actual_value, field_name
            
            # Found field but value doesn't match - still return it
            return False, actual_value, field_name
    
    return False, "", ""


def verify_autofill_address(profile: Dict, expected: Dict) -> Dict[str, Any]:
    """
    Verify autofill address profile against expected values.
    
    Args:
        profile: Autofill profile to verify
        expected: Expected address data
        
    Returns:
        Dict with verification results
    """
    # Define field mappings (multiple possible field names for each)
    field_mappings = {
        'name': ['name_full', 'full_name', 'name'],
        'organization': ['company_name', 'organization', 'company'],
        'street': ['street_address', 'address_line_1', 'address'],
        'city': ['city', 'locality'],
        'state': ['state', 'region', 'province'],
        'zipcode': ['zipcode', 'zip', 'postal_code'],
        'country': ['country_code', 'country'],
        'phone': ['phone_home_whole_number', 'phone', 'phone_number'],
        'email': ['email', 'email_address']
    }
    
    # Required fields for passing
    required_fields = ['name', 'street', 'city', 'zipcode', 'country']
    
    # Optional fields for bonus points
    optional_fields = ['organization', 'state', 'phone', 'email']
    
    results = {
        'required': {},
        'optional': {},
        'score': 0,
        'feedback_parts': []
    }
    
    # Check required fields
    required_passed = 0
    for field_key in required_fields:
        field_names = field_mappings[field_key]
        expected_val = expected[field_key]
        
        # Country needs special handling (US, USA, United States all acceptable)
        if field_key == 'country':
            found, actual, matched_field = validate_address_field(
                profile, field_names, expected_val
            )
            # Also accept variations
            if not found and matched_field:
                actual_norm = normalize_text(actual)
                if actual_norm in ['us', 'usa', 'united states', 'united states of america']:
                    found = True
        else:
            found, actual, matched_field = validate_address_field(
                profile, field_names, expected_val
            )
        
        results['required'][field_key] = {
            'present': bool(matched_field),
            'correct': found,
            'actual': actual,
            'expected': expected_val
        }
        
        if found:
            required_passed += 1
        elif matched_field and actual:
            results['feedback_parts'].append(
                f"⚠ {field_key.title()}: found '{actual}' but expected '{expected_val}'"
            )
        else:
            results['feedback_parts'].append(
                f"✗ {field_key.title()}: missing (expected '{expected_val}')"
            )
    
    # Check optional fields
    optional_passed = 0
    for field_key in optional_fields:
        field_names = field_mappings[field_key]
        expected_val = expected[field_key]
        
        found, actual, matched_field = validate_address_field(
            profile, field_names, expected_val
        )
        
        results['optional'][field_key] = {
            'present': bool(matched_field),
            'correct': found,
            'actual': actual,
            'expected': expected_val
        }
        
        if found:
            optional_passed += 1
    
    # Calculate score
    # Required fields: 20 points each (5 fields = 100 points possible)
    required_score = (required_passed / len(required_fields)) * 100
    
    # Optional fields: bonus points (5 points each, up to 20 points)
    optional_score = min(optional_passed * 5, 20)
    
    # Final score capped at 100
    final_score = min(int(required_score + optional_score), 100)
    
    results['score'] = final_score
    results['required_passed'] = required_passed
    results['optional_passed'] = optional_passed
    
    # Generate summary feedback
    if required_passed == len(required_fields):
        results['feedback_parts'].insert(0, 
            f"✓ All {len(required_fields)} required fields present and correct"
        )
        if optional_passed > 0:
            results['feedback_parts'].append(
                f"✓ {optional_passed}/{len(optional_fields)} optional fields completed"
            )
    else:
        results['feedback_parts'].insert(0,
            f"Required fields: {required_passed}/{len(required_fields)} correct"
        )
    
    return results


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for autofill_address_config@1.
    
    Verifies that a complete address was added to Chrome autofill settings.
    
    Args:
        traj: Trajectory data (not used)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration
        
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
    
    temp_file = None
    try:
        # Copy Preferences file from container
        logger.info("Copying Chrome Preferences from container...")
        
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_file.close()
        
        # Try multiple possible locations
        copy_success = False
        for container_path in [
            "/tmp/chrome_preferences_autofill.json",
            "/tmp/chrome_preferences.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]:
            try:
                logger.info(f"Trying to copy from: {container_path}")
                copy_from_env(container_path, temp_file.name)
                
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    logger.info(f"✓ Successfully copied from: {container_path}")
                    copy_success = True
                    break
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if not copy_success:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Could not access Chrome Preferences file from any known location"
            }
        
        # Parse Preferences JSON
        logger.info("Parsing Preferences file...")
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            prefs_data = json.load(f)
        
        # Extract autofill profiles
        profiles = extract_autofill_profiles(prefs_data)
        
        if not profiles:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No autofill profiles found. Please add an address in Chrome Settings > Autofill and passwords > Addresses."
            }
        
        # Find the best matching profile
        logger.info("Finding matching profile...")
        target_profile = find_matching_profile(profiles, EXPECTED_ADDRESS)
        
        if not target_profile:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Found {len(profiles)} profile(s) but none match expected address"
            }
        
        # Verify the profile
        logger.info("Verifying address fields...")
        verification = verify_autofill_address(target_profile, EXPECTED_ADDRESS)
        
        score = verification['score']
        passed = score >= 70
        
        # Build feedback
        feedback_lines = [
            f"Chrome Autofill Address Configuration Verification",
            f"{'='*50}",
            ""
        ]
        feedback_lines.extend(verification['feedback_parts'])
        feedback_lines.extend([
            "",
            f"Required fields: {verification['required_passed']}/5 correct",
            f"Optional fields: {verification['optional_passed']}/4 completed",
            f"Final score: {score}/100",
            f"Result: {'✅ PASSED' if passed else '❌ FAILED'}"
        ])
        
        feedback = "\n".join(feedback_lines)
        
        # Log detailed results
        logger.info(f"Verification complete: score={score}, passed={passed}")
        logger.info(f"Required: {verification['required_passed']}/5")
        logger.info(f"Optional: {verification['optional_passed']}/4")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "details": {
                "profiles_found": len(profiles),
                "required_fields": verification['required'],
                "optional_fields": verification['optional']
            }
        }
        
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse Preferences JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to parse Chrome Preferences file: {str(e)}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        # Cleanup temporary file
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass
        
        cleanup_verification_temp()
