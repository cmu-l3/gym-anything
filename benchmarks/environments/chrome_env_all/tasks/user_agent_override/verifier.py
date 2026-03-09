#!/usr/bin/env python3
"""
Verifier for Chrome User Agent Override Task (user_agent_override@1)
Task: Configure DevTools to override user agent string to simulate mobile device

Verification Strategy:
1. Primary: Execute JavaScript via CDP to get navigator.userAgent from exported data
2. Check that user agent differs from Chrome's default desktop UA
3. Validate that user agent contains mobile/device identifiers
4. Ensure user agent string is properly formatted
5. Fallback: Check Chrome DevTools Preferences for emulation settings
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
    from chrome_verification_utils import cleanup_verification_temp
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass


# Default Chrome user agent patterns (desktop)
DEFAULT_UA_PATTERNS = [
    r'Mozilla/5\.0.*\(Windows NT.*\).*Chrome/\d+.*Safari',
    r'Mozilla/5\.0.*\(X11; Linux x86_64\).*Chrome/\d+.*Safari',
    r'Mozilla/5\.0.*\(Macintosh.*\).*Chrome/\d+.*Safari',
]

# Mobile/device user agent indicators
MOBILE_INDICATORS = [
    'iPhone', 'iPad', 'iPod', 'iOS',
    'Android', 'Mobile', 'Tablet',
    'Samsung', 'Galaxy', 'Pixel',
    'Nokia', 'BlackBerry', 'Opera Mini',
    'Windows Phone', 'IEMobile',
    'Mobile Safari', 'CriOS',  # Chrome on iOS
]


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for user_agent_override@1 task.
    
    Verifies that Chrome DevTools user agent override was successfully configured.
    
    Scoring:
    - 100%: All 5 criteria met (perfect configuration)
    - 80-99%: 4/5 criteria met (good, passing)
    - 60-79%: 3/5 criteria met (partial, needs improvement)
    - <60%: <3 criteria met (failed)
    
    Pass threshold: 75% (requires at least 4 out of 5 criteria)
    
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
        # Extract user agent from exported data
        user_agent, ua_source = extract_user_agent(copy_from_env)
        
        if not user_agent:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to extract user agent string. DevTools may not have been configured."
            }
        
        logger.info(f"Extracted user agent: {user_agent[:100]}...")
        logger.info(f"Source: {ua_source}")
        
        # Perform multi-criteria verification
        verification_result = verify_user_agent_override(user_agent)
        
        # Add source information to feedback
        verification_result['feedback'] = (
            f"User agent source: {ua_source}\n" + 
            verification_result['feedback']
        )
        
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


def extract_user_agent(copy_from_env) -> Tuple[Optional[str], str]:
    """
    Extract user agent string from various sources.
    
    Tries in order:
    1. Captured user agent from JavaScript execution
    2. Chrome DevTools Preferences
    3. Fallback methods
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (user_agent_string or None, source_description)
    """
    # Method 1: Try to get captured user agent from JavaScript execution
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
        temp_file.close()
        
        copy_from_env("/tmp/user_agent.txt", temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            user_agent = f.read().strip()
        
        os.unlink(temp_file.name)
        
        if user_agent and user_agent != "unknown" and len(user_agent) > 10:
            logger.info("Successfully extracted user agent from JavaScript execution")
            return user_agent, "JavaScript execution via CDP"
    except Exception as e:
        logger.debug(f"Could not extract from JavaScript execution: {e}")
    
    # Method 2: Try to extract from Chrome Preferences (DevTools settings)
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_file.close()
        
        # Try multiple possible locations
        prefs_paths = [
            "/tmp/chrome_preferences.json",
            "/tmp/ua_override_verification/chrome_preferences.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        prefs_data = None
        for prefs_path in prefs_paths:
            try:
                copy_from_env(prefs_path, temp_file.name)
                
                with open(temp_file.name, 'r', encoding='utf-8') as f:
                    prefs_data = json.load(f)
                
                if prefs_data:
                    break
            except Exception as e:
                logger.debug(f"Could not copy from {prefs_path}: {e}")
                continue
        
        os.unlink(temp_file.name)
        
        if prefs_data:
            # Check DevTools preferences for emulation settings
            devtools = prefs_data.get('devtools', {})
            devtools_prefs = devtools.get('preferences', {})
            
            # Check for user agent override in DevTools preferences
            ua_override = devtools_prefs.get('emulation.userAgent', '')
            if ua_override:
                logger.info("Found user agent override in DevTools preferences")
                return ua_override, "Chrome DevTools Preferences"
            
            # Alternative location
            emulation_ua = devtools_prefs.get('network.customUserAgent', '')
            if emulation_ua:
                return emulation_ua, "Chrome Preferences (network.customUserAgent)"
                
    except Exception as e:
        logger.debug(f"Could not extract from Preferences: {e}")
    
    # No user agent found
    logger.warning("Could not extract user agent from any source")
    return None, "none"


def verify_user_agent_override(user_agent: str) -> Dict[str, Any]:
    """
    Verify that user agent override is correctly configured.
    
    Checks 5 criteria:
    1. User agent differs from Chrome default desktop UA
    2. User agent contains mobile/device identifiers
    3. User agent string is properly formatted (valid format)
    4. User agent is not empty or trivially short
    5. User agent doesn't match common error patterns
    
    Args:
        user_agent: The user agent string to verify
        
    Returns:
        Dict with verification results
    """
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    # Criterion 1: User agent differs from Chrome default
    is_default = is_default_chrome_ua(user_agent)
    if not is_default:
        criteria_met += 1
        feedback_parts.append("✓ User agent differs from Chrome default desktop UA")
    else:
        feedback_parts.append("✗ User agent appears to be default Chrome desktop UA (not overridden)")
    
    # Criterion 2: Contains mobile/device identifiers
    has_mobile_indicator = any(
        indicator.lower() in user_agent.lower() 
        for indicator in MOBILE_INDICATORS
    )
    if has_mobile_indicator:
        criteria_met += 1
        matched_indicators = [
            ind for ind in MOBILE_INDICATORS 
            if ind.lower() in user_agent.lower()
        ]
        feedback_parts.append(
            f"✓ User agent contains mobile/device identifiers: {', '.join(matched_indicators[:3])}"
        )
    else:
        feedback_parts.append("⚠ User agent does not contain typical mobile/device identifiers (custom UA?)")
        # Give partial credit if it's clearly not default but custom
        if not is_default and len(user_agent) > 20:
            criteria_met += 0.5
            feedback_parts.append("  (Partial credit for custom non-default UA)")
    
    # Criterion 3: Properly formatted user agent
    is_valid_format = is_valid_user_agent_format(user_agent)
    if is_valid_format:
        criteria_met += 1
        feedback_parts.append("✓ User agent has valid format")
    else:
        feedback_parts.append("✗ User agent format appears invalid or malformed")
    
    # Criterion 4: Not empty or trivially short
    is_adequate_length = len(user_agent) >= 20
    if is_adequate_length:
        criteria_met += 1
        feedback_parts.append(f"✓ User agent has adequate length ({len(user_agent)} characters)")
    else:
        feedback_parts.append(f"✗ User agent too short ({len(user_agent)} characters)")
    
    # Criterion 5: Doesn't match error patterns
    has_no_errors = not contains_error_patterns(user_agent)
    if has_no_errors:
        criteria_met += 1
        feedback_parts.append("✓ No error patterns detected")
    else:
        feedback_parts.append("✗ User agent contains error/unknown patterns")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*60}"
    feedback += f"\nCaptured user agent:\n  {user_agent}"
    feedback += f"\n{'='*60}"
    feedback += f"\nCriteria met: {criteria_met:.1f}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    if passed and has_mobile_indicator:
        feedback += "\n\n🎉 Excellent! DevTools user agent override successfully configured!"
    elif passed:
        feedback += "\n\n✓ User agent override configured (custom UA detected)"
    else:
        feedback += "\n\n❌ User agent override not properly configured or still using default"
    
    logger.info(f"Verification complete: passed={passed}, score={score}, criteria={criteria_met}/{total_criteria}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "user_agent": user_agent,
            "is_default": is_default,
            "has_mobile_indicator": has_mobile_indicator,
            "is_valid_format": is_valid_format,
            "is_adequate_length": is_adequate_length,
            "has_no_errors": has_no_errors,
            "criteria_met": criteria_met,
            "total_criteria": total_criteria
        }
    }


def is_default_chrome_ua(user_agent: str) -> bool:
    """
    Check if user agent matches Chrome's default desktop patterns.
    
    Args:
        user_agent: User agent string to check
        
    Returns:
        True if it matches default Chrome desktop UA
    """
    ua_lower = user_agent.lower()
    
    # Check for desktop OS indicators combined with Chrome
    desktop_indicators = [
        ('windows nt', 'chrome'),
        ('x11; linux x86_64', 'chrome'),
        ('macintosh', 'chrome')
    ]
    
    for os_indicator, browser_indicator in desktop_indicators:
        if os_indicator in ua_lower and browser_indicator in ua_lower:
            # Further check: should NOT have mobile indicators
            if not any(mobile.lower() in ua_lower for mobile in MOBILE_INDICATORS):
                return True
    
    # Check against regex patterns
    for pattern in DEFAULT_UA_PATTERNS:
        if re.search(pattern, user_agent, re.IGNORECASE):
            return True
    
    return False


def is_valid_user_agent_format(user_agent: str) -> bool:
    """
    Check if user agent string has valid format.
    
    Valid formats typically start with Mozilla/5.0 or contain browser identifiers.
    
    Args:
        user_agent: User agent string to validate
        
    Returns:
        True if format appears valid
    """
    if not user_agent or len(user_agent) < 10:
        return False
    
    # Most user agents start with Mozilla/5.0 or similar
    if re.match(r'^Mozilla/\d\.\d', user_agent):
        return True
    
    # Or contain common browser/device identifiers
    valid_indicators = [
        'Chrome', 'Safari', 'Firefox', 'Edge', 'Opera',
        'iPhone', 'iPad', 'Android', 'Mobile',
        'AppleWebKit', 'Gecko', 'KHTML'
    ]
    
    if any(indicator in user_agent for indicator in valid_indicators):
        return True
    
    # Custom user agents might not follow standard format but should be non-trivial
    if len(user_agent) > 15 and not user_agent.lower() in ['unknown', 'error', 'none', 'null']:
        return True
    
    return False


def contains_error_patterns(user_agent: str) -> bool:
    """
    Check if user agent contains error/unknown patterns.
    
    Args:
        user_agent: User agent string to check
        
    Returns:
        True if error patterns detected
    """
    error_patterns = [
        'unknown', 'error', 'none', 'null', 'undefined',
        'not available', 'n/a', 'ERROR', 'UNKNOWN'
    ]
    
    ua_lower = user_agent.lower()
    
    for pattern in error_patterns:
        if pattern.lower() == ua_lower or pattern.lower() in ua_lower[:20]:
            return True
    
    return False
