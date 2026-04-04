#!/usr/bin/env python3
"""
Verifier for Chrome Startup Pages Configuration Task (startup_pages_config@1)

Task: Configure Chrome to automatically open multiple productivity pages on startup

Verification Strategy:
- Parse Chrome Preferences JSON file
- Check session.restore_on_startup == 4 (open specific pages)
- Validate session.startup_urls contains 2-4 URLs
- Verify each URL is properly formatted (valid web URL)
- Check URLs are appropriate for productivity (not obviously inappropriate)
- Ensure no duplicate URLs

Scoring:
- 100%: All 4 criteria met (mode correct, valid count, all URLs valid, no duplicates)
- 75-99%: 3/4 criteria met (one minor issue)
- 50-74%: 2/4 criteria met (multiple issues)
- 0-49%: <2 criteria met (task failed)

Pass threshold: 75% (requires at least 3 out of 4 criteria)
"""

import logging
import sys
import os
import json
import re
import tempfile
from pathlib import Path
from urllib.parse import urlparse
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../..', 'utils'))
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
    Main verification function for startup_pages_config@1.
    
    Verifies that Chrome startup pages were properly configured.
    
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
            "feedback": "copy_from_env function not available in environment"
        }

    try:
        # Extract startup configuration from Preferences
        prefs_data, error_msg = get_preferences_from_container(copy_from_env)
        
        if prefs_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to retrieve Chrome Preferences: {error_msg}"
            }
        
        # Verify startup pages configuration
        result = verify_startup_pages_configuration(prefs_data)
        
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


def get_preferences_from_container(copy_from_env) -> Tuple[Optional[Dict], str]:
    """
    Retrieve and parse Chrome Preferences file from container.
    
    Args:
        copy_from_env: Function to copy files from container to host
        
    Returns:
        Tuple of (preferences_dict or None, error_message)
    """
    temp_file = None
    try:
        # Create temporary file
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_path = temp_file.name
        temp_file.close()
        
        # Try multiple possible locations
        possible_paths = [
            "/tmp/chrome_preferences.json",
            "/tmp/chrome_startup_prefs_backup.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        prefs_data = None
        source_path = None
        
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy Preferences from: {container_path}")
                copy_from_env(container_path, temp_path)
                
                # Check if file was copied successfully
                if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
                    with open(temp_path, 'r', encoding='utf-8') as f:
                        prefs_data = json.load(f)
                    
                    # Check if it's the error placeholder
                    if prefs_data.get('error') == 'preferences_not_found':
                        logger.warning("Found error placeholder in preferences")
                        continue
                    
                    source_path = container_path
                    logger.info(f"✓ Successfully loaded Preferences from: {container_path}")
                    break
                    
            except json.JSONDecodeError as e:
                logger.warning(f"Failed to parse JSON from {container_path}: {e}")
                continue
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if prefs_data is None:
            return None, "Could not retrieve Preferences file from any known location"
        
        return prefs_data, ""
        
    except Exception as e:
        return None, f"Error retrieving Preferences: {str(e)}"
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_path):
            try:
                os.unlink(temp_path)
            except:
                pass


def verify_startup_pages_configuration(prefs_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that startup pages were properly configured in Chrome Preferences.
    
    Checks 4 criteria:
    1. Startup mode is set to 4 (open specific pages)
    2. URL count is between 2-4 (reasonable range)
    3. All URLs are valid web URLs
    4. No duplicate URLs
    
    Args:
        prefs_data: Parsed Chrome Preferences JSON
        
    Returns:
        Verification result with passed, score, and detailed feedback
    """
    session = prefs_data.get('session', {})
    restore_mode = session.get('restore_on_startup', 1)
    startup_urls = session.get('startup_urls', [])
    
    logger.info(f"Startup mode: {restore_mode}")
    logger.info(f"Startup URLs ({len(startup_urls)}): {startup_urls}")
    
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    # Criterion 1: Startup mode is set to "Open a specific page or set of pages" (mode 4)
    mode_correct = (restore_mode == 4)
    if mode_correct:
        feedback_parts.append("✓ Startup mode correctly set to 'Open a specific page or set of pages'")
        criteria_met += 1
        logger.info("✓ Criterion 1: Mode correct (4)")
    else:
        mode_names = {
            1: "Open the New Tab page (default)",
            4: "Open a specific page or set of pages",
            5: "Continue where you left off"
        }
        current_mode_name = mode_names.get(restore_mode, f"Unknown mode ({restore_mode})")
        feedback_parts.append(f"✗ Startup mode is '{current_mode_name}', should be mode 4")
        logger.info(f"✗ Criterion 1: Mode incorrect ({restore_mode}, expected 4)")
    
    # Criterion 2: URL count is between 2-4 (reasonable range for productivity pages)
    url_count = len(startup_urls)
    count_valid = (2 <= url_count <= 4)
    if count_valid:
        feedback_parts.append(f"✓ Good number of startup pages configured ({url_count})")
        criteria_met += 1
        logger.info(f"✓ Criterion 2: Count valid ({url_count})")
    else:
        if url_count == 0:
            feedback_parts.append("✗ No startup pages configured")
        elif url_count == 1:
            feedback_parts.append("✗ Only 1 startup page (expected 2-4 for productivity workflow)")
        elif url_count > 4:
            feedback_parts.append(f"✗ Too many startup pages ({url_count}), may slow down browser")
        logger.info(f"✗ Criterion 2: Count invalid ({url_count}, expected 2-4)")
    
    # Criterion 3: All URLs are valid web URLs
    all_urls_valid = True
    invalid_urls = []
    
    for url in startup_urls:
        if not is_valid_web_url(url):
            all_urls_valid = False
            invalid_urls.append(url)
    
    if all_urls_valid and url_count > 0:
        feedback_parts.append(f"✓ All {url_count} URLs are properly formatted")
        criteria_met += 1
        logger.info("✓ Criterion 3: All URLs valid")
    else:
        if url_count == 0:
            feedback_parts.append("✗ No URLs to validate")
        else:
            feedback_parts.append(f"✗ Invalid URLs detected: {invalid_urls}")
        logger.info(f"✗ Criterion 3: Invalid URLs found: {invalid_urls}")
    
    # Criterion 4: No duplicate URLs
    unique_urls = list(set(normalize_url(url) for url in startup_urls))
    no_duplicates = (len(unique_urls) == len(startup_urls) and len(startup_urls) > 0)
    
    if no_duplicates:
        feedback_parts.append("✓ No duplicate URLs detected")
        criteria_met += 1
        logger.info("✓ Criterion 4: No duplicates")
    else:
        if len(startup_urls) == 0:
            feedback_parts.append("⚠ No URLs to check for duplicates")
        else:
            feedback_parts.append(f"✗ Duplicate URLs detected ({len(startup_urls)} total, {len(unique_urls)} unique)")
        logger.info(f"✗ Criterion 4: Duplicates found ({len(startup_urls)} total, {len(unique_urls)} unique)")
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75  # Need at least 3/4 criteria
    
    # Build detailed feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nCriteria met: {criteria_met}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    
    if passed:
        feedback += f"\n{'='*50}"
        feedback += "\n✅ PASSED - Startup pages successfully configured!"
        feedback += f"\n\nConfigured startup URLs:"
        for i, url in enumerate(startup_urls, 1):
            feedback += f"\n  {i}. {url}"
    else:
        feedback += f"\n{'='*50}"
        feedback += "\n❌ FAILED - Startup pages not properly configured"
        feedback += "\n\nPlease ensure you:"
        feedback += "\n  1. Navigate to chrome://settings"
        feedback += "\n  2. Find the 'On startup' section"
        feedback += "\n  3. Select 'Open a specific page or set of pages'"
        feedback += "\n  4. Add 2-4 productivity URLs (email, calendar, etc.)"
    
    logger.info(f"Verification complete: passed={passed}, score={score}, criteria={criteria_met}/{total_criteria}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "restore_mode": restore_mode,
            "startup_urls": startup_urls,
            "url_count": url_count,
            "criteria_met": criteria_met,
            "mode_correct": mode_correct,
            "count_valid": count_valid,
            "all_urls_valid": all_urls_valid,
            "no_duplicates": no_duplicates
        }
    }


def is_valid_web_url(url: str) -> bool:
    """
    Validate that a string is a properly formatted web URL.
    
    Args:
        url: URL string to validate
        
    Returns:
        True if valid web URL, False otherwise
    """
    if not url or not isinstance(url, str):
        return False
    
    # Basic URL pattern check
    url_pattern = re.compile(
        r'^https?://'  # http:// or https://
        r'(?:(?:[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?\.)+[A-Z]{2,6}\.?|'  # domain...
        r'localhost|'  # localhost...
        r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})'  # ...or ip
        r'(?::\d+)?'  # optional port
        r'(?:/?|[/?]\S+)$', re.IGNORECASE)
    
    if not url_pattern.match(url):
        return False
    
    # Additional validation using urlparse
    try:
        parsed = urlparse(url)
        return all([
            parsed.scheme in ['http', 'https'],
            parsed.netloc,  # Must have a network location (domain)
            len(url) < 2048  # Reasonable URL length limit
        ])
    except Exception:
        return False


def normalize_url(url: str) -> str:
    """
    Normalize URL for comparison (remove trailing slashes, convert to lowercase).
    
    Args:
        url: URL to normalize
        
    Returns:
        Normalized URL string
    """
    if not url:
        return ""
    
    # Remove trailing slashes
    url = url.rstrip('/')
    # Convert to lowercase for case-insensitive comparison
    url = url.lower()
    
    return url
