#!/usr/bin/env python3
"""
Verifier for Chrome localStorage DevTools Manipulation Task (localstorage_devtools_edit@1)

Task: Use Chrome DevTools Application panel to add localStorage entries:
  - Key: userPreference, Value: darkMode
  - Key: sessionToken, Value: abc123xyz789

Verification Strategy:
1. Extract localStorage data from container (captured via CDP in export_result.sh)
2. Verify both expected key-value pairs are present
3. Check for exact value matches
4. Ensure no unexpected issues (wrong values, missing keys)

Scoring:
- 100%: Both entries present with correct values
- 75%: Both keys present but one value incorrect
- 50%: Only one correct entry
- 25%: Keys present but values wrong
- 0%: Neither entry present
"""

import logging
import sys
import os
import json
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.abspath(__file__), '../../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass


# Expected localStorage entries
EXPECTED_ENTRIES = {
    "userPreference": "darkMode",
    "sessionToken": "abc123xyz789"
}


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for localstorage_devtools_edit@1.
    
    Args:
        traj: Trajectory data (not used)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with 'passed', 'score', and 'feedback' keys
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in environment"
        }

    try:
        # Extract localStorage data from container
        storage_data = extract_localstorage_data(copy_from_env)
        
        if storage_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to extract localStorage data from container"
            }
        
        # Verify the localStorage entries
        verification_result = verify_localstorage_entries(storage_data)
        
        # Clean up
        cleanup_verification_temp()
        
        return verification_result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def extract_localstorage_data(copy_from_env) -> Dict[str, Any]:
    """
    Extract localStorage data from the container.
    
    Args:
        copy_from_env: Function to copy files from container to host
        
    Returns:
        Dict with localStorage entries, or None if extraction failed
    """
    temp_file = None
    try:
        # Copy the localStorage data file created by export_result.sh
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_file.close()
        
        logger.info("Copying localStorage data from container...")
        copy_from_env("/tmp/localstorage_data.json", temp_file.name)
        
        # Check if file was copied successfully
        if not os.path.exists(temp_file.name) or os.path.getsize(temp_file.name) == 0:
            logger.error("localStorage data file is empty or doesn't exist")
            return None
        
        # Parse JSON
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            data = json.load(f)
        
        logger.info(f"Successfully loaded localStorage data: {json.dumps(data, indent=2)}")
        
        # Extract the entries dict
        entries = data.get('entries', {})
        extraction_method = data.get('extraction_method', 'unknown')
        
        logger.info(f"Extraction method: {extraction_method}")
        logger.info(f"Found {len(entries)} localStorage entries: {list(entries.keys())}")
        
        return entries
        
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse localStorage JSON: {e}")
        return None
    except Exception as e:
        logger.error(f"Error extracting localStorage data: {e}", exc_info=True)
        return None
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def verify_localstorage_entries(storage_data: Dict[str, str]) -> Dict[str, Any]:
    """
    Verify that localStorage contains the expected entries.
    
    Checks:
    1. Key 'userPreference' exists with value 'darkMode'
    2. Key 'sessionToken' exists with value 'abc123xyz789'
    3. Both entries are correct
    
    Args:
        storage_data: Dict of localStorage key-value pairs
        
    Returns:
        Verification result with passed, score, and detailed feedback
    """
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    # Criterion 1: userPreference key exists
    has_user_pref_key = "userPreference" in storage_data
    if has_user_pref_key:
        criteria_met += 1
        feedback_parts.append("✓ Key 'userPreference' exists")
    else:
        feedback_parts.append("✗ Key 'userPreference' not found")
    
    # Criterion 2: userPreference has correct value
    user_pref_value_correct = False
    if has_user_pref_key:
        actual_value = storage_data.get("userPreference", "")
        if actual_value == "darkMode":
            user_pref_value_correct = True
            criteria_met += 1
            feedback_parts.append(f"✓ Value 'userPreference' = 'darkMode' (correct)")
        else:
            feedback_parts.append(f"✗ Value 'userPreference' = '{actual_value}' (expected 'darkMode')")
    else:
        feedback_parts.append("✗ Cannot check value for missing key 'userPreference'")
    
    # Criterion 3: sessionToken key exists
    has_session_key = "sessionToken" in storage_data
    if has_session_key:
        criteria_met += 1
        feedback_parts.append("✓ Key 'sessionToken' exists")
    else:
        feedback_parts.append("✗ Key 'sessionToken' not found")
    
    # Criterion 4: sessionToken has correct value
    session_value_correct = False
    if has_session_key:
        actual_value = storage_data.get("sessionToken", "")
        if actual_value == "abc123xyz789":
            session_value_correct = True
            criteria_met += 1
            feedback_parts.append(f"✓ Value 'sessionToken' = 'abc123xyz789' (correct)")
        else:
            feedback_parts.append(f"✗ Value 'sessionToken' = '{actual_value}' (expected 'abc123xyz789')")
    else:
        feedback_parts.append("✗ Cannot check value for missing key 'sessionToken'")
    
    # Criterion 5: No unexpected extra entries (allow up to 2-3 extra entries as reasonable)
    expected_keys = set(EXPECTED_ENTRIES.keys())
    actual_keys = set(storage_data.keys())
    extra_keys = actual_keys - expected_keys
    
    if len(extra_keys) == 0:
        criteria_met += 1
        feedback_parts.append("✓ No unexpected extra entries")
    elif len(extra_keys) <= 2:
        criteria_met += 0.5  # Partial credit
        feedback_parts.append(f"⚠ Found {len(extra_keys)} extra entry(ies): {list(extra_keys)}")
    else:
        feedback_parts.append(f"✗ Too many extra entries: {list(extra_keys)}")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75  # Need at least 4/5 criteria
    
    # Build detailed feedback
    feedback_header = f"localStorage Verification Results: {criteria_met}/{total_criteria} criteria met\n"
    feedback_header += "="*60 + "\n"
    
    feedback_body = "\n".join(feedback_parts)
    
    feedback_footer = "\n" + "="*60 + "\n"
    if passed:
        feedback_footer += f"✅ Task PASSED (Score: {score}%)\n"
        feedback_footer += "Successfully added both required localStorage entries via DevTools!"
    else:
        feedback_footer += f"❌ Task FAILED (Score: {score}%)\n"
        if not has_user_pref_key and not has_session_key:
            feedback_footer += "No localStorage entries found. Did you add them via DevTools Application panel?"
        elif has_user_pref_key and has_session_key and not (user_pref_value_correct and session_value_correct):
            feedback_footer += "Both keys exist but one or more values are incorrect."
        else:
            feedback_footer += "Missing one or more required localStorage entries."
    
    feedback = feedback_header + feedback_body + feedback_footer
    
    # Log summary
    logger.info(f"Verification complete: passed={passed}, score={score}%")
    logger.info(f"Criteria met: {criteria_met}/{total_criteria}")
    logger.info(f"userPreference: exists={has_user_pref_key}, correct={user_pref_value_correct}")
    logger.info(f"sessionToken: exists={has_session_key}, correct={session_value_correct}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "criteria_met": criteria_met,
            "total_criteria": total_criteria,
            "has_user_pref_key": has_user_pref_key,
            "user_pref_value_correct": user_pref_value_correct,
            "has_session_key": has_session_key,
            "session_value_correct": session_value_correct,
            "extra_keys": list(extra_keys),
            "all_keys": list(actual_keys),
            "storage_data": storage_data
        }
    }
