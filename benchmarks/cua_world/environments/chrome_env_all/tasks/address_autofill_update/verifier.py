#!/usr/bin/env python3
"""
Verifier for Chrome Address Autofill Update Task (address_autofill_update@1)
Task: Remove outdated address and add new current address to Chrome autofill

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON to extract autofill.profile_address_data_manager.profiles
- Verify old address (742 Evergreen Terrace) is NOT present
- Verify new address (1640 Riverside Drive) IS present
- Check all required fields of new address (city, state, ZIP)
- Calculate score based on criteria met

Scoring:
- 50 points: Old address removed
- 25 points: New address present
- 25 points: New address has correct fields (city, state, ZIP)
Pass threshold: 75% (need old address removed + new address with correct fields)
"""

import logging
import sys
import os
import json
import tempfile
from pathlib import Path
from typing import Dict, Any, List, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.abspath(__file__), '../../../', 'utils'))
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


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for address_autofill_update@1.
    
    Verifies:
    1. Old address (742 Evergreen Terrace) is removed
    2. New address (1640 Riverside Drive) is present
    3. New address has correct city (Metropolis)
    4. New address has correct state (NY)
    5. New address has correct ZIP (10001)
    
    Args:
        traj: Trajectory data (not used)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration
        
    Returns:
        Dict with 'passed', 'score', and 'feedback'
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in environment"
        }

    try:
        # Extract autofill profiles from Chrome Preferences
        profiles, error_msg = extract_autofill_profiles(copy_from_env)
        
        if profiles is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to extract autofill data: {error_msg}"
            }
        
        # Perform verification
        result = verify_address_changes(profiles)
        
        # Cleanup
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


def extract_autofill_profiles(copy_from_env) -> Tuple[Optional[List[Dict]], str]:
    """
    Extract autofill address profiles from Chrome Preferences file.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (profiles list or None, error message)
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
                prefs = parse_preferences(files["Preferences"])
                profiles = prefs.get('autofill', {}).get('profile_address_data_manager', {}).get('profiles', [])
                logger.info(f"Extracted {len(profiles)} address profile(s) using utilities")
                return profiles, ""
            else:
                logger.warning(f"Utility-based extraction failed: {error}, trying fallback")
        
        # Fallback: Manual extraction
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        # Try multiple possible locations
        possible_paths = [
            "/tmp/chrome_preferences_autofill.json",
            "/tmp/chrome_preferences.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        prefs = None
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy from: {container_path}")
                copy_from_env(container_path, temp_file.name)
                
                # Check if file was copied successfully
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    with open(temp_file.name, 'r', encoding='utf-8') as f:
                        prefs = json.load(f)
                    logger.info(f"Successfully copied and parsed from: {container_path}")
                    break
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if prefs is None:
            return None, "Could not access Preferences file from any known location"
        
        # Extract autofill profiles
        profiles = prefs.get('autofill', {}).get('profile_address_data_manager', {}).get('profiles', [])
        logger.info(f"Extracted {len(profiles)} address profile(s) from Preferences")
        
        return profiles, ""
        
    except json.JSONDecodeError as e:
        return None, f"Failed to parse Preferences JSON: {e}"
    except Exception as e:
        return None, f"Error extracting autofill profiles: {e}"
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def verify_address_changes(profiles: List[Dict]) -> Dict[str, Any]:
    """
    Verify that old address was removed and new address was added correctly.
    
    Criteria:
    1. Old address (742 Evergreen Terrace) NOT present (50 points)
    2. New address (1640 Riverside Drive) present (25 points)
    3. New address city is Metropolis (5 points)
    4. New address state is NY (10 points)
    5. New address ZIP is 10001 (10 points)
    
    Args:
        profiles: List of address profile dictionaries
        
    Returns:
        Verification result dict
    """
    score = 0
    feedback_parts = []
    
    logger.info(f"Verifying {len(profiles)} address profile(s)")
    
    # Log all addresses for debugging
    for i, profile in enumerate(profiles, 1):
        street = profile.get('street-address', 'N/A')
        city = profile.get('city', 'N/A')
        state = profile.get('state', 'N/A')
        logger.info(f"  Address {i}: {street}, {city}, {state}")
    
    # Criterion 1: Old address should NOT be present (50 points)
    old_address_found = False
    for profile in profiles:
        street = profile.get('street-address', '').lower()
        if '742 evergreen terrace' in street or '742evergreenterrace' in street.replace(' ', ''):
            old_address_found = True
            break
    
    if not old_address_found:
        score += 50
        feedback_parts.append("✓ Old address (742 Evergreen Terrace) successfully removed")
        logger.info("✓ Old address removed")
    else:
        feedback_parts.append("✗ Old address (742 Evergreen Terrace) still present in autofill data")
        logger.info("✗ Old address still present")
    
    # Criteria 2-5: New address should be present with correct details
    new_address_profile = None
    for profile in profiles:
        street = profile.get('street-address', '').lower()
        # Look for new address (flexible matching)
        if '1640 riverside drive' in street or '1640riverside' in street.replace(' ', ''):
            new_address_profile = profile
            break
    
    if new_address_profile:
        score += 25
        feedback_parts.append("✓ New address (1640 Riverside Drive) added to autofill")
        logger.info("✓ New address found")
        
        # Check individual fields
        city = new_address_profile.get('city', '').lower()
        state = new_address_profile.get('state', '').upper()
        zip_code = new_address_profile.get('zip', '')
        
        # City check (5 points)
        if city == 'metropolis':
            score += 5
            feedback_parts.append("✓ City correct: Metropolis")
            logger.info("✓ City correct")
        else:
            feedback_parts.append(f"✗ City incorrect: '{new_address_profile.get('city', 'N/A')}' (expected: Metropolis)")
            logger.info(f"✗ City incorrect: {city}")
        
        # State check (10 points)
        if state == 'NY':
            score += 10
            feedback_parts.append("✓ State correct: NY")
            logger.info("✓ State correct")
        else:
            feedback_parts.append(f"✗ State incorrect: '{new_address_profile.get('state', 'N/A')}' (expected: NY)")
            logger.info(f"✗ State incorrect: {state}")
        
        # ZIP code check (10 points)
        if zip_code == '10001':
            score += 10
            feedback_parts.append("✓ ZIP code correct: 10001")
            logger.info("✓ ZIP correct")
        else:
            feedback_parts.append(f"✗ ZIP code incorrect: '{zip_code}' (expected: 10001)")
            logger.info(f"✗ ZIP incorrect: {zip_code}")
        
    else:
        feedback_parts.append("✗ New address (1640 Riverside Drive) not found in autofill data")
        logger.info("✗ New address not found")
    
    # Calculate pass/fail
    passed = score >= 75
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nFinal Score: {score}/100"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    if passed:
        feedback += "\n\nAutofill address successfully updated! Old address removed and new address added with correct details."
    else:
        if not old_address_found and not new_address_profile:
            feedback += "\n\nBoth old address removal and new address addition are incomplete."
        elif old_address_found:
            feedback += "\n\nOld address was not removed. Please delete it from Chrome Settings > Autofill > Addresses."
        elif not new_address_profile:
            feedback += "\n\nNew address was not added. Please add it via Chrome Settings > Autofill > Addresses > Add."
        else:
            feedback += "\n\nNew address was added but contains incorrect field values."
    
    logger.info(f"Verification complete: passed={passed}, score={score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "total_addresses": len(profiles),
            "old_address_removed": not old_address_found,
            "new_address_present": new_address_profile is not None,
            "new_address_details": {
                "city_correct": new_address_profile.get('city', '').lower() == 'metropolis' if new_address_profile else False,
                "state_correct": new_address_profile.get('state', '').upper() == 'NY' if new_address_profile else False,
                "zip_correct": new_address_profile.get('zip', '') == '10001' if new_address_profile else False
            } if new_address_profile else None
        }
    }
