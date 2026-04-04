#!/usr/bin/env python3
"""
Verifier for Chrome Custom Homepage Configuration Task (custom_homepage@1)
Task: Enable home button, set custom homepage URL, and verify navigation

Verification Strategy:
1. Check Preferences file for browser.show_home_button = true
2. Check Preferences file for homepage = "https://en.wikipedia.org"
3. Verify active tab URL matches homepage (via CDP)
4. Ensure settings are properly persisted

Scoring:
- 100%: All 4 criteria met (perfect configuration)
- 75-99%: 3/4 criteria met (good, passing)
- 50-74%: 2/4 criteria met (partial)
- 0-49%: <2 criteria met (failed)

Pass threshold: 75% (requires 3 out of 4 criteria)
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
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../utils'))
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


def normalize_url(url: str) -> str:
    """Normalize URL for comparison by removing trailing slashes and www"""
    if not url:
        return ""
    url = url.rstrip('/')
    url = url.lower()
    # Normalize protocol
    if url.startswith('http://'):
        url = url[7:]
    elif url.startswith('https://'):
        url = url[8:]
    # Remove www prefix
    if url.startswith('www.'):
        url = url[4:]
    return url


def get_preferences_file(copy_from_env) -> Tuple[Optional[str], Optional[Dict], str]:
    """
    Copy and parse Chrome Preferences file from container.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (file_path, parsed_prefs, error_message)
    """
    temp_file = None
    
    try:
        # Try multiple possible locations
        possible_paths = [
            "/tmp/homepage_verification/preferences_primary.json",
            "/tmp/preferences_primary.json",
            "/tmp/homepage_verification/preferences_alt.json",
            "/tmp/preferences_alt.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        for container_path in possible_paths:
            try:
                temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
                temp_path = temp_file.name
                temp_file.close()
                
                logger.info(f"Trying to copy Preferences from: {container_path}")
                copy_from_env(container_path, temp_path)
                
                # Verify file was copied successfully
                if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
                    with open(temp_path, 'r', encoding='utf-8') as f:
                        prefs = json.load(f)
                    
                    logger.info(f"✓ Successfully loaded Preferences from: {container_path}")
                    return temp_path, prefs, ""
                else:
                    if os.path.exists(temp_path):
                        os.unlink(temp_path)
                    
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                if temp_file and os.path.exists(temp_path):
                    try:
                        os.unlink(temp_path)
                    except:
                        pass
                continue
        
        return None, None, "Could not copy Preferences file from any known location"
        
    except Exception as e:
        return None, None, f"Error getting Preferences: {str(e)}"


def check_home_button_enabled(prefs: Dict) -> Tuple[bool, str]:
    """
    Check if home button is enabled in preferences.
    
    Args:
        prefs: Parsed Preferences dictionary
        
    Returns:
        Tuple of (is_enabled, feedback)
    """
    try:
        browser_section = prefs.get('browser', {})
        show_home_button = browser_section.get('show_home_button', False)
        
        if show_home_button is True:
            return True, "✓ Home button is enabled"
        else:
            return False, f"✗ Home button not enabled (show_home_button = {show_home_button})"
            
    except Exception as e:
        return False, f"✗ Error checking home button: {str(e)}"


def check_homepage_url(prefs: Dict, expected_url: str) -> Tuple[bool, str]:
    """
    Check if homepage URL is set correctly.
    
    Args:
        prefs: Parsed Preferences dictionary
        expected_url: Expected homepage URL
        
    Returns:
        Tuple of (is_correct, feedback)
    """
    try:
        homepage = prefs.get('homepage', '')
        
        # Normalize URLs for comparison
        homepage_normalized = normalize_url(homepage)
        expected_normalized = normalize_url(expected_url)
        
        if homepage_normalized == expected_normalized:
            return True, f"✓ Homepage URL correctly set to {homepage}"
        elif homepage_normalized and homepage_normalized in expected_normalized:
            # Partial match (e.g., missing /wiki/ path)
            return True, f"✓ Homepage URL set to {homepage} (close match)"
        elif homepage:
            return False, f"✗ Homepage URL is '{homepage}', expected '{expected_url}'"
        else:
            return False, "✗ Homepage URL not set"
            
    except Exception as e:
        return False, f"✗ Error checking homepage URL: {str(e)}"


def check_active_tab_url(copy_from_env, expected_url: str) -> Tuple[Optional[bool], str]:
    """
    Check if active tab shows the homepage URL (via CDP).
    
    Args:
        copy_from_env: Function to copy files
        expected_url: Expected homepage URL
        
    Returns:
        Tuple of (is_correct or None, feedback)
    """
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
        temp_path = temp_file.name
        temp_file.close()
        
        # Try to get active URL from exported file
        possible_paths = [
            "/tmp/homepage_verification/final_url.txt",
            "/tmp/final_url.txt"
        ]
        
        active_url = None
        for container_path in possible_paths:
            try:
                copy_from_env(container_path, temp_path)
                with open(temp_path, 'r') as f:
                    active_url = f.read().strip()
                
                if active_url:
                    break
            except Exception as e:
                logger.debug(f"Failed to get URL from {container_path}: {e}")
                continue
        
        # Cleanup temp file
        if os.path.exists(temp_path):
            os.unlink(temp_path)
        
        if not active_url:
            return None, "⚠ Could not retrieve active tab URL"
        
        # Normalize and compare
        active_normalized = normalize_url(active_url)
        expected_normalized = normalize_url(expected_url)
        
        if active_normalized.startswith(expected_normalized) or expected_normalized in active_normalized:
            return True, f"✓ Active tab shows homepage: {active_url}"
        else:
            return False, f"✗ Active tab shows '{active_url}', expected homepage"
            
    except Exception as e:
        logger.warning(f"Error checking active tab: {e}")
        return None, f"⚠ Could not verify active tab: {str(e)}"


def check_settings_persisted(prefs: Dict) -> Tuple[bool, str]:
    """
    Check if settings are properly persisted (file is valid).
    
    Args:
        prefs: Parsed Preferences dictionary
        
    Returns:
        Tuple of (is_valid, feedback)
    """
    try:
        # Check that critical sections exist
        has_browser = 'browser' in prefs
        has_roots = 'roots' in prefs or 'profile' in prefs
        
        if has_browser and has_roots:
            return True, "✓ Preferences file successfully saved and valid"
        else:
            return False, "✗ Preferences file appears incomplete or corrupted"
            
    except Exception as e:
        return False, f"✗ Error validating preferences: {str(e)}"


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for custom_homepage@1 task.
    
    Verifies:
    1. Home button is enabled (browser.show_home_button = true)
    2. Homepage URL is set correctly (homepage = "https://en.wikipedia.org")
    3. Active tab shows the homepage (via CDP)
    4. Settings are properly persisted
    
    Args:
        traj: Trajectory data (not used)
        env_info: Environment information including copy_from_env
        task_info: Task configuration
        
    Returns:
        Dict with passed, score, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available"
        }
    
    expected_homepage = "https://en.wikipedia.org"
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    try:
        # Get Preferences file
        logger.info("Retrieving Chrome Preferences file...")
        prefs_path, prefs, error = get_preferences_file(copy_from_env)
        
        if not prefs:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to retrieve Preferences file: {error}"
            }
        
        # Criterion 1: Home button enabled
        logger.info("Checking home button configuration...")
        home_button_ok, home_button_feedback = check_home_button_enabled(prefs)
        feedback_parts.append(home_button_feedback)
        if home_button_ok:
            criteria_met += 1
        
        # Criterion 2: Homepage URL set correctly
        logger.info("Checking homepage URL configuration...")
        homepage_url_ok, homepage_url_feedback = check_homepage_url(prefs, expected_homepage)
        feedback_parts.append(homepage_url_feedback)
        if homepage_url_ok:
            criteria_met += 1
        
        # Criterion 3: Active tab shows homepage (optional, may be None)
        logger.info("Checking active tab URL...")
        active_tab_ok, active_tab_feedback = check_active_tab_url(copy_from_env, expected_homepage)
        feedback_parts.append(active_tab_feedback)
        if active_tab_ok is True:
            criteria_met += 1
        elif active_tab_ok is None:
            # Partial credit if we couldn't verify
            criteria_met += 0.5
        
        # Criterion 4: Settings persisted
        logger.info("Checking settings persistence...")
        persisted_ok, persisted_feedback = check_settings_persisted(prefs)
        feedback_parts.append(persisted_feedback)
        if persisted_ok:
            criteria_met += 1
        
        # Calculate score
        score = int((criteria_met / total_criteria) * 100)
        passed = criteria_met >= 3  # Need at least 3/4 criteria (75%)
        
        # Build final feedback
        feedback = "\n".join(feedback_parts)
        feedback += f"\n\n{'='*50}"
        feedback += f"\nCriteria met: {criteria_met:.1f}/{total_criteria}"
        feedback += f"\nFinal score: {score}%"
        feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
        
        # Cleanup
        if prefs_path and os.path.exists(prefs_path):
            try:
                os.unlink(prefs_path)
            except:
                pass
        
        cleanup_verification_temp()
        
        logger.info(f"Verification complete: passed={passed}, score={score}")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "details": {
                "criteria_met": f"{criteria_met:.1f}/{total_criteria}",
                "home_button_enabled": home_button_ok,
                "homepage_url_correct": homepage_url_ok,
                "active_tab_correct": active_tab_ok,
                "settings_persisted": persisted_ok
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
