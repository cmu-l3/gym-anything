#!/usr/bin/env python3
"""
Verifier for Chrome DevTools LocalStorage Manipulation Task (localstorage_editor@1)
Task: Use DevTools Application panel to add localStorage entries

Verification Strategy:
- Extract localStorage data via CDP (Chrome DevTools Protocol)
- Validate required key-value pairs exist
- Check values match exactly (case-sensitive)
- Ensure no corruption of localStorage

Required entries:
- user_preference: "dark_mode"
- session_count: "5"
"""

import logging
import sys
import os
import json
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using standalone methods")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for localstorage_editor@1 task.
    
    Verifies that localStorage entries were correctly added via DevTools:
    - user_preference: "dark_mode"
    - session_count: "5"
    
    Scoring:
    - 100%: Both entries correct
    - 75%: Both entries present but one has wrong value
    - 50%: Only one entry present and correct
    - 25%: Some entries present but all values wrong
    - 0%: No entries found or extraction failed
    
    Pass threshold: 75% (both entries must be present)
    
    Args:
        traj: Trajectory data (not used)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with 'passed' (bool), 'score' (int 0-100), and 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in environment"
        }

    # Expected localStorage entries
    expected_entries = {
        "user_preference": "dark_mode",
        "session_count": "5"
    }

    try:
        # Extract localStorage data from container
        storage_data, error_msg = extract_localstorage_data(copy_from_env)
        
        if storage_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to extract localStorage data: {error_msg}"
            }
        
        # Verify localStorage entries
        verification_result = verify_localstorage_entries(storage_data, expected_entries)
        
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


def extract_localstorage_data(copy_from_env) -> Tuple[Optional[Dict[str, str]], str]:
    """
    Extract localStorage data from the container.
    
    Args:
        copy_from_env: Function to copy files from container to host
        
    Returns:
        Tuple of (localStorage_dict or None, error_message)
    """
    temp_file = None
    try:
        # Create temporary file
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_file.close()
        
        # Copy localStorage data extracted by export_result.sh
        logger.info("Copying localStorage data from container...")
        copy_from_env("/tmp/localstorage_data.json", temp_file.name)
        
        # Check if file was copied successfully
        if not os.path.exists(temp_file.name) or os.path.getsize(temp_file.name) == 0:
            return None, "LocalStorage data file is empty or not found"
        
        # Parse JSON
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            data = json.load(f)
        
        # Check for extraction errors
        if "error" in data:
            error_msg = data["error"]
            logger.warning(f"LocalStorage extraction reported error: {error_msg}")
            return None, f"CDP extraction error: {error_msg}"
        
        # Extract localStorage object
        if "localStorage" in data and data.get("success"):
            storage = data["localStorage"]
            logger.info(f"Successfully extracted localStorage with {len(storage)} entries")
            logger.info(f"Entries: {list(storage.keys())}")
            return storage, ""
        else:
            return None, "LocalStorage data not found in extraction result"
        
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse localStorage JSON: {e}")
        return None, f"JSON parse error: {e}"
    except Exception as e:
        logger.error(f"Error extracting localStorage: {e}")
        return None, f"Extraction error: {e}"
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def verify_localstorage_entries(
    actual_storage: Dict[str, str],
    expected_entries: Dict[str, str]
) -> Dict[str, Any]:
    """
    Verify that localStorage contains expected entries with correct values.
    
    Args:
        actual_storage: Actual localStorage contents
        expected_entries: Expected key-value pairs
        
    Returns:
        Verification result dict with passed, score, and feedback
    """
    if not actual_storage:
        return {
            "passed": False,
            "score": 0,
            "feedback": "LocalStorage is empty - no entries were added",
            "details": {
                "expected": expected_entries,
                "actual": {},
                "missing": list(expected_entries.keys()),
                "wrong_values": [],
                "extra": []
            }
        }
    
    # Analyze entries
    missing_keys = []
    wrong_values = []
    correct_entries = []
    
    for key, expected_value in expected_entries.items():
        if key not in actual_storage:
            missing_keys.append(key)
            logger.warning(f"Missing key: {key}")
        else:
            actual_value = actual_storage[key]
            # Compare as strings (localStorage stores everything as strings)
            if str(actual_value) == str(expected_value):
                correct_entries.append(key)
                logger.info(f"✓ Correct entry: {key} = {actual_value}")
            else:
                wrong_values.append({
                    'key': key,
                    'expected': expected_value,
                    'actual': actual_value
                })
                logger.warning(f"✗ Wrong value for {key}: expected '{expected_value}', got '{actual_value}'")
    
    # Identify extra entries (not required but not necessarily wrong)
    extra_keys = [k for k in actual_storage.keys() if k not in expected_entries]
    
    # Calculate score
    total_required = len(expected_entries)
    correct_count = len(correct_entries)
    
    if correct_count == total_required:
        score = 100
        passed = True
        feedback = f"✅ Perfect! All {total_required} localStorage entries are correct"
    elif correct_count == total_required - 1 and len(wrong_values) == 1:
        score = 75
        passed = True
        wrong = wrong_values[0]
        feedback = f"✓ Both entries present, but '{wrong['key']}' has wrong value: '{wrong['actual']}' (expected: '{wrong['expected']}')"
    elif correct_count > 0:
        score = 50
        passed = False
        feedback = f"Partial success: {correct_count}/{total_required} entries correct"
    elif len(missing_keys) < total_required:
        # Some entries present but all wrong values
        score = 25
        passed = False
        feedback = f"Entries present but values are incorrect"
    else:
        score = 0
        passed = False
        feedback = f"No required entries found in localStorage"
    
    # Build detailed feedback
    feedback_parts = [feedback]
    
    if missing_keys:
        feedback_parts.append(f"\nMissing keys: {', '.join(missing_keys)}")
    
    if wrong_values:
        for wrong in wrong_values:
            feedback_parts.append(
                f"\nWrong value for '{wrong['key']}': got '{wrong['actual']}', expected '{wrong['expected']}'"
            )
    
    if correct_entries:
        feedback_parts.append(f"\nCorrect entries: {', '.join(correct_entries)}")
    
    if extra_keys:
        feedback_parts.append(f"\nExtra entries (not required): {', '.join(extra_keys)}")
    
    final_feedback = "".join(feedback_parts)
    
    logger.info(f"Verification complete: score={score}, passed={passed}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": final_feedback,
        "details": {
            "expected": expected_entries,
            "actual": actual_storage,
            "missing": missing_keys,
            "wrong_values": wrong_values,
            "correct": correct_entries,
            "extra": extra_keys,
            "correct_count": correct_count,
            "total_required": total_required
        }
    }
