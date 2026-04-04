#!/usr/bin/env python3
"""
Verifier for Chrome Protocol Handler Registration Task (protocol_handler_register@1)
Task: Register a custom protocol handler for mailto: links

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON and extract protocol_handler section
- Verify mailto handler is registered
- Check handler URL matches expected pattern
- Validate handler configuration is properly formatted
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
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../..', 'utils'))
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
        """Fallback cleanup function"""
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for protocol_handler_register@1.
    
    Verifies that a mailto: protocol handler has been successfully registered
    in Chrome through the registerProtocolHandler Web API.
    
    Verification Criteria (4 total, need 3+ to pass):
    1. Handler Registered: protocol_handler section contains mailto entry
    2. Correct Protocol: Entry specifies "protocol": "mailto"
    3. Valid URL: Handler URL contains expected pattern with %s placeholder
    4. Properly Formatted: JSON structure is valid and properly saved
    
    Scoring:
    - 100%: All 4 criteria met
    - 75-99%: 3/4 criteria met (passing)
    - 50-74%: 2/4 criteria met (failing)
    - 0-49%: <2 criteria met (significant failure)
    
    Pass threshold: 75% (requires at least 3 out of 4 criteria)
    
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
        # Extract preferences data
        prefs_data, error_msg = extract_preferences(copy_from_env)
        
        if prefs_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to extract Chrome Preferences: {error_msg}"
            }
        
        # Verify protocol handler registration
        result = verify_protocol_handler(prefs_data)
        
        # Clean up temporary files
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


def extract_preferences(copy_from_env) -> Tuple[Optional[Dict], str]:
    """
    Extract Chrome Preferences file from container.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (preferences_dict or None, error_message)
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
                prefs_data = parse_preferences(prefs_path)
                cleanup_verification_temp()
                return prefs_data, ""
            else:
                logger.warning(f"Utility-based extraction failed: {error}, trying fallback")
        
        # Fallback: Manual extraction
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        # Try multiple possible locations
        possible_paths = [
            "/tmp/chrome_preferences.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences",
            "/home/ga/.config/chromium/Default/Preferences"
        ]
        
        prefs_data = None
        source_path = None
        
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy Preferences from: {container_path}")
                copy_from_env(container_path, temp_file.name)
                
                # Check if file was copied successfully and has content
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    with open(temp_file.name, 'r', encoding='utf-8') as f:
                        prefs_data = json.load(f)
                    source_path = container_path
                    logger.info(f"✓ Successfully loaded Preferences from: {container_path}")
                    break
                    
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if prefs_data is None:
            return None, "Could not copy Preferences file from any known location"
        
        return prefs_data, ""
        
    except json.JSONDecodeError as e:
        return None, f"Failed to parse Preferences JSON: {e}"
    except Exception as e:
        return None, f"Error extracting Preferences: {e}"
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def verify_protocol_handler(prefs_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that mailto: protocol handler was successfully registered.
    
    Checks the protocol_handler section in Chrome Preferences for:
    1. Presence of registered_protocols array
    2. Entry with protocol: "mailto"
    3. Valid handler URL with %s placeholder
    4. Proper JSON structure
    
    Args:
        prefs_data: Parsed Chrome Preferences dictionary
        
    Returns:
        Verification result with passed, score, feedback, and details
    """
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    # Get protocol_handler section
    protocol_handler = prefs_data.get('protocol_handler', {})
    
    if not protocol_handler:
        feedback = "✗ Protocol handler section not found in Preferences.\n"
        feedback += "This suggests the registration process was not completed."
        return {
            "passed": False,
            "score": 0,
            "feedback": feedback,
            "details": {
                "handler_found": False,
                "protocol_correct": False,
                "url_valid": False,
                "structure_valid": False
            }
        }
    
    logger.info(f"Protocol handler section found: {json.dumps(protocol_handler, indent=2)}")
    
    # Criterion 1: Handler registered in protocol_handler section
    registered_protocols = protocol_handler.get('registered_protocols', [])
    excluded_schemes = protocol_handler.get('excluded_schemes', {})
    
    handler_found = False
    mailto_handler = None
    
    if isinstance(registered_protocols, list) and len(registered_protocols) > 0:
        for handler in registered_protocols:
            if handler.get('protocol') == 'mailto':
                handler_found = True
                mailto_handler = handler
                break
    
    if handler_found:
        feedback_parts.append("✓ Handler registered: mailto protocol handler found in Preferences")
        criteria_met += 1
    else:
        feedback_parts.append("✗ Handler not registered: No mailto handler found in registered_protocols")
    
    # Criterion 2: Correct protocol specified
    protocol_correct = False
    if mailto_handler:
        if mailto_handler.get('protocol') == 'mailto':
            protocol_correct = True
            feedback_parts.append("✓ Correct protocol: Handler specifies 'mailto' protocol")
            criteria_met += 1
        else:
            feedback_parts.append(f"✗ Wrong protocol: Handler has protocol '{mailto_handler.get('protocol')}'")
    else:
        feedback_parts.append("✗ Protocol not verified: No mailto handler to check")
    
    # Criterion 3: Valid URL with %s placeholder
    url_valid = False
    handler_url = None
    
    if mailto_handler:
        handler_url = mailto_handler.get('url', '')
        
        # Check for %s placeholder (required for protocol handlers)
        if '%s' in handler_url:
            # Check that URL looks reasonable
            if handler_url.startswith(('http://', 'https://', 'file://')):
                url_valid = True
                feedback_parts.append(f"✓ Valid URL: Handler URL contains required placeholder: {handler_url[:60]}...")
                criteria_met += 1
            else:
                feedback_parts.append(f"⚠ URL pattern present but scheme unusual: {handler_url[:60]}...")
                criteria_met += 0.5  # Partial credit
        else:
            feedback_parts.append(f"✗ Invalid URL: Handler URL missing required %s placeholder: {handler_url[:60]}...")
    else:
        feedback_parts.append("✗ URL not verified: No mailto handler to check")
    
    # Criterion 4: Properly formatted structure
    structure_valid = False
    
    if mailto_handler:
        # Check required fields are present
        required_fields = ['protocol', 'url']
        has_required = all(field in mailto_handler for field in required_fields)
        
        # Check that excluded_schemes doesn't block mailto
        mailto_not_excluded = not excluded_schemes.get('mailto', False)
        
        if has_required and mailto_not_excluded:
            structure_valid = True
            feedback_parts.append("✓ Properly formatted: Handler has required fields and is not excluded")
            criteria_met += 1
        else:
            if not has_required:
                feedback_parts.append("✗ Incomplete structure: Handler missing required fields")
            if not mailto_not_excluded:
                feedback_parts.append("✗ Handler excluded: mailto is in excluded_schemes")
    else:
        feedback_parts.append("✗ Structure not verified: No mailto handler to check")
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75  # Need at least 3/4 criteria (75%)
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*60}"
    feedback += f"\nCriteria met: {criteria_met}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    if handler_url:
        feedback += f"\n\nRegistered handler URL: {handler_url}"
    
    # Additional guidance if failed
    if not passed:
        feedback += "\n\n❌ Task incomplete. To complete:"
        feedback += "\n  1. Click the 'Register as Email Handler' button on the test page"
        feedback += "\n  2. Look for the permission prompt in Chrome's address bar"
        feedback += "\n  3. Click 'Allow' to grant the permission"
        feedback += "\n  4. The handler will be saved in Chrome's Preferences"
    
    logger.info(f"Verification complete: passed={passed}, score={score}, criteria_met={criteria_met}/{total_criteria}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "handler_found": handler_found,
            "protocol_correct": protocol_correct,
            "url_valid": url_valid,
            "structure_valid": structure_valid,
            "handler_url": handler_url,
            "criteria_met": criteria_met,
            "total_criteria": total_criteria
        }
    }
