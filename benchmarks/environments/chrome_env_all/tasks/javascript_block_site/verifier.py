#!/usr/bin/env python3
"""
Verifier for Chrome Site-Specific JavaScript Blocking Task (javascript_block_site@1)
Task: Block JavaScript on localhost:8888 test page using Chrome's site settings

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON and navigate to profile.content_settings.exceptions.javascript
- Look for block rule matching localhost:8888
- Verify setting value is 2 (BLOCK) not 1 (ALLOW)
- Validate pattern format and timestamp
"""

import logging
import sys
import os
import json
import re
import tempfile
from pathlib import Path
from typing import Dict, Tuple, Optional, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import (
        parse_preferences,
        cleanup_verification_temp
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


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for javascript_block_site@1.
    
    Verifies that JavaScript blocking was correctly configured for the target domain.
    
    Args:
        traj: Trajectory data (not used)
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
        # Get target domain
        target_domain = get_target_domain(copy_from_env)
        logger.info(f"Target domain for JS blocking: {target_domain}")
        
        # Get JavaScript settings from Chrome Preferences
        prefs_data = get_preferences(copy_from_env)
        
        if prefs_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to retrieve Chrome Preferences file"
            }
        
        # Verify JavaScript blocking configuration
        result = verify_javascript_blocking(prefs_data, target_domain)
        
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


def get_target_domain(copy_from_env) -> str:
    """
    Get the target domain that should be blocked.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Target domain string (e.g., "localhost:8888")
    """
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
        temp_path = temp_file.name
        temp_file.close()
        
        copy_from_env("/tmp/js_block_target_domain.txt", temp_path)
        
        with open(temp_path, 'r') as f:
            domain = f.read().strip()
        
        os.unlink(temp_path)
        
        return domain if domain else "localhost:8888"
        
    except Exception as e:
        logger.warning(f"Could not read target domain, using default: {e}")
        return "localhost:8888"


def get_preferences(copy_from_env) -> Optional[Dict]:
    """
    Copy and parse Chrome Preferences file from container.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Parsed preferences dict or None if failed
    """
    temp_file = None
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_path = temp_file.name
        temp_file.close()
        
        # Try multiple possible locations
        locations = [
            "/tmp/chrome_preferences_export.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        prefs_data = None
        for location in locations:
            try:
                logger.info(f"Trying to copy Preferences from: {location}")
                copy_from_env(location, temp_path)
                
                # Check if file has content
                if os.path.exists(temp_path) and os.path.getsize(temp_path) > 10:
                    with open(temp_path, 'r', encoding='utf-8') as f:
                        prefs_data = json.load(f)
                    logger.info(f"✓ Successfully loaded Preferences from: {location}")
                    break
            except Exception as e:
                logger.debug(f"Failed to copy from {location}: {e}")
                continue
        
        if temp_file and os.path.exists(temp_path):
            os.unlink(temp_path)
        
        return prefs_data
        
    except Exception as e:
        logger.error(f"Error getting preferences: {e}")
        if temp_file and os.path.exists(temp_path):
            os.unlink(temp_path)
        return None


def verify_javascript_blocking(prefs_data: Dict, target_domain: str) -> Dict[str, Any]:
    """
    Verify JavaScript blocking configuration in Chrome Preferences.
    
    Checks:
    1. Block rule exists in content_settings.exceptions.javascript
    2. Rule targets the correct domain
    3. Setting value is 2 (BLOCK) not 1 (ALLOW)
    4. Pattern format is valid
    
    Args:
        prefs_data: Parsed Chrome Preferences JSON
        target_domain: Domain that should be blocked (e.g., "localhost:8888")
        
    Returns:
        Verification result dict with passed, score, and feedback
    """
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    # Navigate to JavaScript exceptions
    try:
        profile = prefs_data.get('profile', {})
        content_settings = profile.get('content_settings', {})
        exceptions = content_settings.get('exceptions', {})
        js_exceptions = exceptions.get('javascript', {})
        
        logger.info(f"Found {len(js_exceptions)} JavaScript exception(s)")
        
        if not js_exceptions:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No JavaScript content settings found in Chrome Preferences. "
                           "Please navigate to chrome://settings/content/javascript and add a block rule.",
                "details": {
                    "criteria_met": 0,
                    "total_criteria": total_criteria,
                    "has_js_settings": False
                }
            }
        
        # Criterion 1: JavaScript settings section exists
        feedback_parts.append("✓ JavaScript content settings section found")
        criteria_met += 1
        
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not navigate Chrome Preferences structure: {e}",
            "details": {"error": str(e)}
        }
    
    # Look for block rule matching target domain
    block_rule_found = False
    correct_setting_value = False
    valid_pattern = False
    matching_pattern = None
    setting_value = None
    
    # Normalize target for comparison
    target_normalized = normalize_domain(target_domain)
    
    for pattern, settings in js_exceptions.items():
        logger.info(f"Checking pattern: {pattern}")
        
        # Extract domain from pattern (patterns are like "localhost:8888,*" or "[*.]localhost:8888,*")
        pattern_domain = extract_domain_from_pattern(pattern)
        pattern_normalized = normalize_domain(pattern_domain)
        
        if target_normalized in pattern_normalized or pattern_normalized in target_normalized:
            logger.info(f"✓ Found matching pattern: {pattern}")
            block_rule_found = True
            matching_pattern = pattern
            setting_value = settings.get('setting')
            
            # Criterion 2: Block rule exists for target domain
            feedback_parts.append(f"✓ Block rule found for domain: {pattern}")
            criteria_met += 1
            
            # Criterion 3: Setting value is 2 (BLOCK)
            # In Chrome: 1 = ALLOW, 2 = BLOCK
            if setting_value == 2:
                correct_setting_value = True
                feedback_parts.append(f"✓ Setting correctly configured to BLOCK (value: {setting_value})")
                criteria_met += 1
            elif setting_value == 1:
                feedback_parts.append(f"✗ Setting is ALLOW (value: {setting_value}), should be BLOCK (value: 2)")
            else:
                feedback_parts.append(f"✗ Unknown setting value: {setting_value}")
            
            # Criterion 4: Pattern format is valid
            if is_valid_pattern(pattern):
                valid_pattern = True
                feedback_parts.append(f"✓ Pattern format is valid")
                criteria_met += 1
            else:
                feedback_parts.append(f"⚠ Pattern format may be non-standard: {pattern}")
                criteria_met += 0.5  # Partial credit
            
            break
    
    if not block_rule_found:
        feedback_parts.append(f"✗ No block rule found for '{target_domain}'")
        feedback_parts.append(f"   Found {len(js_exceptions)} JavaScript rule(s), but none match the target domain")
        
        # Log all patterns for debugging
        if js_exceptions:
            feedback_parts.append("   Existing patterns:")
            for pattern in list(js_exceptions.keys())[:5]:  # Show up to 5
                feedback_parts.append(f"     - {pattern}")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75  # Need at least 3/4 criteria
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nCriteria met: {criteria_met}/{total_criteria}"
    feedback += f"\nScore: {score}%"
    feedback += f"\nResult: {'✅ PASSED' if passed else '❌ FAILED'}"
    
    if not passed:
        feedback += "\n\nTo complete this task:"
        feedback += "\n1. Navigate to chrome://settings/content/javascript"
        feedback += "\n2. Scroll to 'Not allowed to use JavaScript'"
        feedback += "\n3. Click 'Add' button"
        feedback += f"\n4. Enter: {target_domain}"
        feedback += "\n5. Click 'Add' to save"
    
    logger.info(f"Verification complete: passed={passed}, score={score}, criteria={criteria_met}/{total_criteria}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "criteria_met": criteria_met,
            "total_criteria": total_criteria,
            "block_rule_found": block_rule_found,
            "correct_setting_value": correct_setting_value,
            "valid_pattern": valid_pattern,
            "matching_pattern": matching_pattern,
            "setting_value": setting_value,
            "target_domain": target_domain
        }
    }


def normalize_domain(domain: str) -> str:
    """Normalize domain for comparison (lowercase, strip whitespace)"""
    if not domain:
        return ""
    return domain.lower().strip()


def extract_domain_from_pattern(pattern: str) -> str:
    """
    Extract domain from Chrome content settings pattern.
    
    Patterns can be like:
    - "localhost:8888,*"
    - "[*.]localhost:8888,*"
    - "http://localhost:8888,*"
    
    Returns:
        Extracted domain string
    """
    if not pattern:
        return ""
    
    # Remove common pattern suffixes
    domain = pattern.split(',')[0]  # Remove ",*" suffix
    
    # Remove scheme if present
    domain = re.sub(r'^https?://', '', domain)
    
    # Remove wildcard prefix
    domain = re.sub(r'^\[\*\.\]', '', domain)
    
    return domain.strip()


def is_valid_pattern(pattern: str) -> bool:
    """
    Check if pattern format is valid for Chrome content settings.
    
    Valid patterns include:
    - "domain.com,*"
    - "[*.]domain.com,*"
    - "http://domain.com,*"
    - "domain.com:port,*"
    """
    if not pattern:
        return False
    
    # Basic validation: should contain comma
    if ',' not in pattern:
        return False
    
    # Should have domain-like structure
    parts = pattern.split(',')
    if len(parts) < 1:
        return False
    
    domain_part = parts[0]
    
    # Should contain at least one alphanumeric character
    if not re.search(r'[a-zA-Z0-9]', domain_part):
        return False
    
    return True
