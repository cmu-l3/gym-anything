#!/usr/bin/env python3
"""
Verifier for Chrome Automatic Downloads Permission Configuration Task
Task: Allow automatic downloads for https://download-test.example.com

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON and navigate to profile.content_settings.exceptions.automatic_downloads
- Verify an entry exists for the target website
- Validate the permission setting value is 1 (allow), not 2 (block)
- Check URL format is correct (https with optional port)
- Ensure proper JSON structure and no corruption

Scoring:
- 100%: Perfect configuration with correct permission entry
- 75-99%: Permission exists and allows downloads but with minor format issues
- 50-74%: Permission entry found but with significant issues
- 0-49%: Permission not found, blocked, or file corrupted
"""

import logging
import sys
import os
import json
import re
import tempfile
from pathlib import Path
from typing import Dict, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import (
        copy_chrome_file,
        parse_preferences,
        cleanup_verification_temp
    )
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    
    def parse_preferences(path):
        """Fallback preferences parser"""
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    
    def cleanup_verification_temp():
        """Fallback cleanup"""
        pass


def extract_target_site_from_task(task_info: Dict) -> str:
    """Extract target site from task metadata"""
    return task_info.get('metadata', {}).get('target_site', 'https://download-test.example.com')


def copy_preferences_file(copy_from_env) -> Tuple[bool, str, str]:
    """
    Copy Chrome Preferences file from container.
    
    Returns:
        Tuple of (success: bool, local_path: str, error_message: str)
    """
    try:
        # Try multiple possible locations
        possible_paths = [
            "/tmp/chrome_preferences.json",
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
                    logger.info(f"✓ Successfully copied Preferences from: {container_path}")
                    return True, temp_path, ""
                else:
                    os.unlink(temp_path)
                    
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                if os.path.exists(temp_path):
                    try:
                        os.unlink(temp_path)
                    except:
                        pass
                continue
        
        return False, "", "Could not copy Preferences file from any known location"
        
    except Exception as e:
        logger.error(f"Error copying Preferences file: {e}", exc_info=True)
        return False, "", f"Error copying Preferences: {str(e)}"


def find_automatic_downloads_permission(prefs: Dict, target_site: str) -> Tuple[bool, Optional[Dict], str]:
    """
    Find automatic downloads permission entry for target site.
    
    Args:
        prefs: Parsed Preferences JSON
        target_site: Target website URL (e.g., https://download-test.example.com)
        
    Returns:
        Tuple of (found: bool, permission_data: Dict or None, url_pattern: str)
    """
    try:
        # Navigate to automatic_downloads exceptions
        exceptions = prefs.get('profile', {}).get('content_settings', {}).get('exceptions', {})
        auto_downloads = exceptions.get('automatic_downloads', {})
        
        if not auto_downloads:
            logger.info("No automatic_downloads section found in preferences")
            return False, None, ""
        
        # Extract domain from target site
        target_domain = target_site.replace('https://', '').replace('http://', '').rstrip('/')
        
        logger.info(f"Searching for automatic downloads permission for domain: {target_domain}")
        logger.info(f"Available permission entries: {list(auto_downloads.keys())}")
        
        # Search for matching entry
        for url_pattern, permission_data in auto_downloads.items():
            # Chrome stores URLs in various formats:
            # - https://example.com:443,*
            # - [*.]example.com
            # - https://example.com
            
            url_pattern_lower = url_pattern.lower()
            
            # Check if target domain is in the URL pattern
            if target_domain in url_pattern_lower:
                logger.info(f"✓ Found matching permission entry: {url_pattern}")
                return True, permission_data, url_pattern
        
        logger.info(f"No permission entry found for {target_domain}")
        return False, None, ""
        
    except Exception as e:
        logger.error(f"Error searching for permission: {e}", exc_info=True)
        return False, None, ""


def validate_permission_entry(permission_data: Dict, url_pattern: str) -> Tuple[int, str]:
    """
    Validate the permission entry quality.
    
    Args:
        permission_data: Permission data dictionary from Preferences
        url_pattern: URL pattern string
        
    Returns:
        Tuple of (score: int, feedback: str)
    """
    issues = []
    score = 100
    
    # Check setting value
    setting_value = permission_data.get('setting')
    
    if setting_value is None:
        return 0, "Permission entry exists but has no 'setting' field"
    
    if setting_value == 2:  # 2 = blocked
        return 0, f"Permission is set to BLOCK (2) instead of ALLOW (1)"
    
    if setting_value != 1:  # 1 = allowed
        return 50, f"Permission has unexpected setting value: {setting_value} (expected 1 for allow)"
    
    # Check for timestamp (optional but good practice)
    if 'last_modified' not in permission_data:
        issues.append("Missing 'last_modified' timestamp")
        score -= 10
    
    # Validate URL pattern format
    if not url_pattern.startswith('http'):
        issues.append("URL pattern doesn't start with http/https")
        score -= 5
    
    # Generate feedback
    if score == 100:
        feedback = f"✓ Perfect configuration: Automatic downloads ALLOWED for {url_pattern}"
    else:
        feedback = f"✓ Automatic downloads ALLOWED with minor issues: {'; '.join(issues)}"
    
    return score, feedback


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for automatic_downloads_allow@1 task.
    
    Verifies:
    1. Preferences file is accessible
    2. Permission entry exists for target site
    3. Permission is set to ALLOW (1), not BLOCK (2)
    4. Valid URL format and structure
    
    Pass threshold: 75% (requires correct permission allowing automatic downloads)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available"
        }
    
    # Extract target site from task info
    target_site = extract_target_site_from_task(task_info)
    logger.info(f"Verifying automatic downloads permission for: {target_site}")
    
    try:
        # Step 1: Copy Preferences file
        success, prefs_path, error = copy_preferences_file(copy_from_env)
        
        if not success:
            cleanup_verification_temp()
            return {
                "passed": False,
                "score": 0,
                "feedback": f"✗ Could not access Preferences file: {error}"
            }
        
        # Step 2: Parse Preferences
        try:
            prefs = parse_preferences(prefs_path)
        except json.JSONDecodeError as e:
            os.unlink(prefs_path)
            cleanup_verification_temp()
            return {
                "passed": False,
                "score": 0,
                "feedback": f"✗ Could not parse Preferences file (corrupted JSON): {str(e)}"
            }
        except Exception as e:
            os.unlink(prefs_path)
            cleanup_verification_temp()
            return {
                "passed": False,
                "score": 0,
                "feedback": f"✗ Error parsing Preferences: {str(e)}"
            }
        
        if not prefs:
            os.unlink(prefs_path)
            cleanup_verification_temp()
            return {
                "passed": False,
                "score": 0,
                "feedback": "✗ Preferences file is empty or invalid"
            }
        
        # Step 3: Find automatic downloads permission
        found, permission_data, url_pattern = find_automatic_downloads_permission(prefs, target_site)
        
        if not found:
            os.unlink(prefs_path)
            cleanup_verification_temp()
            return {
                "passed": False,
                "score": 0,
                "feedback": f"✗ No automatic downloads permission found for {target_site}\n"
                           f"Expected: Permission entry in Settings > Site Settings > Automatic downloads"
            }
        
        # Step 4: Validate permission entry
        score, feedback = validate_permission_entry(permission_data, url_pattern)
        
        # Cleanup
        os.unlink(prefs_path)
        cleanup_verification_temp()
        
        # Determine pass/fail
        passed = score >= 75
        
        # Build detailed feedback
        detailed_feedback = [
            f"{'✅' if passed else '❌'} Automatic Downloads Permission Configuration",
            f"Target site: {target_site}",
            f"URL pattern found: {url_pattern}",
            f"Setting value: {permission_data.get('setting')} (1=allow, 2=block)",
            f"Score: {score}/100",
            "",
            feedback
        ]
        
        if not passed:
            detailed_feedback.append("\nNote: Score must be ≥75 to pass")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": "\n".join(detailed_feedback),
            "details": {
                "target_site": target_site,
                "url_pattern": url_pattern,
                "setting_value": permission_data.get('setting'),
                "has_timestamp": 'last_modified' in permission_data,
                "permission_data": permission_data
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"✗ Verification error: {str(e)}"
        }
