#!/usr/bin/env python3
"""
Verifier for Chrome Homepage Button Configuration Task (homepage_button_config@1)
Task: Enable Chrome's home button and set Wikipedia as homepage

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON to extract browser.show_home_button and browser.homepage
- Verify both settings are correctly configured
- Provide detailed multi-criteria feedback

Scoring:
- 100%: All 4 criteria met (perfect configuration)
- 75-99%: 3/4 criteria met (one setting correct, one with minor issues)
- 50-74%: 2/4 criteria met (partial configuration)
- 25-49%: 1/4 criteria met (minimal progress)
- 0-24%: <1 criteria met (failed)

Pass threshold: 75% (requires at least 3 out of 4 criteria)
"""

import logging
import sys
import os
import json
import tempfile
from pathlib import Path
from typing import Dict, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utilities to path
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
    
    def parse_preferences(path):
        """Fallback parse_preferences if utils not available"""
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    
    def cleanup_verification_temp():
        """Fallback cleanup function"""
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for homepage_button_config@1 task.
    
    Verifies:
    1. Home button is enabled (browser.show_home_button = true)
    2. Homepage URL contains wikipedia.org domain
    3. Homepage URL is properly formatted with protocol
    4. Both settings are persisted in Preferences file
    
    Args:
        traj: Trajectory data (not used for this verification)
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

    try:
        # Extract preferences from container
        prefs_data, error_msg = extract_preferences_from_container(copy_from_env)
        
        if prefs_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to extract preferences: {error_msg}"
            }
        
        # Perform multi-criteria verification
        verification_result = verify_homepage_configuration(
            prefs_data,
            expected_domain="wikipedia.org"
        )
        
        # Clean up temporary files
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


def extract_preferences_from_container(copy_from_env) -> Tuple[Optional[Dict], str]:
    """
    Extract Chrome Preferences file from container.
    
    Tries multiple strategies:
    1. Use chrome_verification_utils if available
    2. Copy from /tmp/chrome_preferences_export.json (post-task export)
    3. Copy directly from known Chrome profile locations
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (preferences_dict or None, error_message)
    """
    temp_file = None
    
    try:
        # Strategy 1: Use utilities if available
        if UTILS_AVAILABLE:
            logger.info("Attempting to use chrome_verification_utils...")
            success, files, error = setup_chrome_verification(
                copy_from_env,
                ["Preferences"],
                user="ga",
                profile="Default"
            )
            
            if success:
                prefs_data = parse_preferences(files["Preferences"])
                logger.info("✓ Successfully extracted preferences using utilities")
                return prefs_data, ""
            else:
                logger.warning(f"Utility-based extraction failed: {error}, trying fallback")
        
        # Strategy 2: Copy from post-task export location
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_file.close()
        
        possible_paths = [
            "/tmp/chrome_preferences_export.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences",
            "/home/ga/.config/chromium/Default/Preferences"
        ]
        
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy from: {container_path}")
                copy_from_env(container_path, temp_file.name)
                
                # Check if file was copied successfully
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    with open(temp_file.name, 'r', encoding='utf-8') as f:
                        prefs_data = json.load(f)
                    
                    logger.info(f"✓ Successfully copied and parsed from: {container_path}")
                    return prefs_data, ""
                    
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        # If we get here, all strategies failed
        return None, "Could not copy Preferences file from any known location"
        
    except json.JSONDecodeError as e:
        return None, f"Failed to parse Preferences JSON: {e}"
    except Exception as e:
        return None, f"Error extracting preferences: {e}"
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def verify_homepage_configuration(prefs_data: Dict[str, Any], 
                                 expected_domain: str = "wikipedia.org") -> Dict[str, Any]:
    """
    Verify homepage button and URL configuration.
    
    Checks 4 criteria:
    1. show_home_button is enabled (true)
    2. homepage URL contains expected domain
    3. homepage URL is properly formatted (has protocol)
    4. both settings are present and persisted
    
    Args:
        prefs_data: Parsed Chrome Preferences JSON
        expected_domain: Domain that should be in homepage URL
        
    Returns:
        Dict with passed, score, feedback, and detailed criteria results
    """
    # Extract browser preferences
    browser_prefs = prefs_data.get('browser', {})
    show_home_button = browser_prefs.get('show_home_button', None)
    homepage = browser_prefs.get('homepage', '')
    
    logger.info(f"Extracted settings:")
    logger.info(f"  show_home_button: {show_home_button}")
    logger.info(f"  homepage: {homepage}")
    
    # Initialize criteria tracking
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    # Criterion 1: Home button enabled
    home_button_enabled = show_home_button is True
    if home_button_enabled:
        criteria_met += 1
        feedback_parts.append("✓ Home button is enabled")
        logger.info("✓ Criterion 1 (home button enabled): PASS")
    else:
        feedback_parts.append(f"✗ Home button not enabled (value: {show_home_button})")
        logger.info(f"✗ Criterion 1 (home button enabled): FAIL (value={show_home_button})")
    
    # Criterion 2: Homepage URL contains expected domain
    homepage_lower = homepage.lower() if homepage else ""
    domain_present = expected_domain.lower() in homepage_lower
    
    if domain_present:
        criteria_met += 1
        feedback_parts.append(f"✓ Homepage URL contains '{expected_domain}'")
        logger.info(f"✓ Criterion 2 (domain present): PASS")
    else:
        feedback_parts.append(f"✗ Homepage URL doesn't contain '{expected_domain}' (current: '{homepage}')")
        logger.info(f"✗ Criterion 2 (domain present): FAIL (homepage={homepage})")
    
    # Criterion 3: Homepage URL properly formatted
    url_valid = False
    if homepage:
        # Check for protocol (http:// or https://)
        has_protocol = homepage.startswith('http://') or homepage.startswith('https://')
        # Check for reasonable length
        has_reasonable_length = len(homepage) > 10
        # Check contains at least one dot (domain structure)
        has_domain_structure = '.' in homepage
        
        url_valid = has_protocol and has_reasonable_length and has_domain_structure
    
    if url_valid:
        criteria_met += 1
        feedback_parts.append("✓ Homepage URL properly formatted")
        logger.info("✓ Criterion 3 (URL format): PASS")
    else:
        if not homepage:
            feedback_parts.append("✗ Homepage URL is empty")
        elif not homepage.startswith('http'):
            feedback_parts.append("✗ Homepage URL missing protocol (http:// or https://)")
        else:
            feedback_parts.append("✗ Homepage URL format invalid")
        logger.info(f"✗ Criterion 3 (URL format): FAIL")
    
    # Criterion 4: Settings successfully persisted
    # Check that both settings exist in preferences (not None/missing)
    settings_persisted = (show_home_button is not None) and bool(homepage)
    
    if settings_persisted:
        criteria_met += 1
        feedback_parts.append("✓ Settings successfully persisted to Preferences")
        logger.info("✓ Criterion 4 (persistence): PASS")
    else:
        if show_home_button is None and not homepage:
            feedback_parts.append("✗ Neither setting found in Preferences")
        elif show_home_button is None:
            feedback_parts.append("✗ Home button setting not found in Preferences")
        elif not homepage:
            feedback_parts.append("✗ Homepage URL not saved in Preferences")
        logger.info("✗ Criterion 4 (persistence): FAIL")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75  # Need at least 3/4 criteria
    
    # Generate final feedback
    feedback_header = f"Homepage Configuration Verification: {criteria_met}/{total_criteria} criteria met\n"
    feedback_header += "=" * 60 + "\n"
    
    feedback_body = "\n".join(feedback_parts)
    
    feedback_footer = "\n" + "=" * 60 + "\n"
    feedback_footer += f"Score: {score}%\n"
    
    if passed:
        feedback_footer += "Result: ✅ PASSED - Homepage configuration successful"
    else:
        feedback_footer += "Result: ❌ FAILED - Configuration incomplete"
        feedback_footer += "\n\nTo complete this task:"
        if not home_button_enabled:
            feedback_footer += "\n  • Enable 'Show home button' in Settings > Appearance"
        if not domain_present or not url_valid:
            feedback_footer += "\n  • Set homepage URL to 'https://www.wikipedia.org' in Settings > Appearance"
    
    feedback = feedback_header + feedback_body + feedback_footer
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "criteria_met": criteria_met,
            "total_criteria": total_criteria,
            "show_home_button": show_home_button,
            "homepage": homepage,
            "home_button_enabled": home_button_enabled,
            "domain_present": domain_present,
            "url_valid": url_valid,
            "settings_persisted": settings_persisted
        }
    }


def normalize_url(url: str) -> str:
    """
    Normalize URL for comparison.
    
    Args:
        url: URL string to normalize
        
    Returns:
        Normalized URL string
    """
    if not url:
        return ""
    
    # Remove trailing slashes
    url = url.rstrip('/')
    # Convert to lowercase
    url = url.lower()
    # Remove protocol for comparison
    url = url.replace('https://', '').replace('http://', '')
    # Remove www. prefix
    url = url.replace('www.', '')
    
    return url
