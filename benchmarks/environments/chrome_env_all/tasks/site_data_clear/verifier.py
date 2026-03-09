#!/usr/bin/env python3
"""
Verifier for Chrome Complete Site Data Deletion Task (site_data_clear@1)
Task: Remove all stored data for example.org domain using Chrome's site data settings

Verification Strategy:
- Check Cookies database for any remaining cookies for target domain
- Check Preferences file for any permissions or settings for target domain
- Check for custom zoom levels for the domain
- Ensure comprehensive data removal across all storage types

Scoring:
- 100%: All 4 criteria met (complete data removal)
- 75%: 3/4 criteria met (good removal with minor remnants)
- 50%: 2/4 criteria met (partial removal)
- <50%: Incomplete or failed deletion
"""

import logging
import sys
import os
import json
import sqlite3
import tempfile
import re
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
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


# Task configuration
TARGET_DOMAIN = "example.org"


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for site_data_clear@1.
    
    Verifies that all site data has been removed for the target domain.
    
    Args:
        traj: Trajectory data (not used)
        env_info: Environment info including copy_from_env function
        task_info: Task configuration
        
    Returns:
        Dict with passed, score, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in environment"
        }

    try:
        # Extract Chrome data files
        data_files = extract_chrome_data_files(copy_from_env)
        
        if not data_files['cookies_path'] and not data_files['prefs_path']:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to access Chrome data files for verification"
            }
        
        # Perform multi-criteria verification
        verification_result = verify_site_data_removal(
            data_files['cookies_path'],
            data_files['prefs_path'],
            TARGET_DOMAIN
        )
        
        # Cleanup temporary files
        cleanup_temp_files(data_files)
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


def extract_chrome_data_files(copy_from_env) -> Dict[str, Optional[str]]:
    """
    Extract Chrome data files from container.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Dict with paths to extracted files
    """
    result = {
        'cookies_path': None,
        'prefs_path': None
    }
    
    # Try using utilities if available
    if UTILS_AVAILABLE:
        try:
            success, files, error = setup_chrome_verification(
                copy_from_env,
                ["Cookies", "Preferences"],
                user="ga",
                profile="Default"
            )
            
            if success:
                result['cookies_path'] = files.get("Cookies")
                result['prefs_path'] = files.get("Preferences")
                logger.info("Successfully extracted files using utilities")
                return result
        except Exception as e:
            logger.warning(f"Utility-based extraction failed: {e}, trying fallback")
    
    # Fallback: Manual extraction
    try:
        # Try to copy from verification directory
        verification_paths = [
            "/tmp/site_data_verification/Cookies",
            "/home/ga/.config/google-chrome-cdp/Default/Cookies",
            "/home/ga/.config/google-chrome/Default/Cookies"
        ]
        
        for container_path in verification_paths:
            try:
                temp_cookies = tempfile.NamedTemporaryFile(delete=False, suffix='.db')
                temp_cookies.close()
                
                copy_from_env(container_path, temp_cookies.name)
                
                if os.path.exists(temp_cookies.name) and os.path.getsize(temp_cookies.name) > 0:
                    result['cookies_path'] = temp_cookies.name
                    logger.info(f"Successfully copied Cookies from: {container_path}")
                    break
                else:
                    os.unlink(temp_cookies.name)
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                if os.path.exists(temp_cookies.name):
                    os.unlink(temp_cookies.name)
        
        # Try to copy Preferences
        prefs_paths = [
            "/tmp/site_data_verification/Preferences",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        for container_path in prefs_paths:
            try:
                temp_prefs = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
                temp_prefs.close()
                
                copy_from_env(container_path, temp_prefs.name)
                
                if os.path.exists(temp_prefs.name) and os.path.getsize(temp_prefs.name) > 0:
                    result['prefs_path'] = temp_prefs.name
                    logger.info(f"Successfully copied Preferences from: {container_path}")
                    break
                else:
                    os.unlink(temp_prefs.name)
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                if os.path.exists(temp_prefs.name):
                    os.unlink(temp_prefs.name)
        
    except Exception as e:
        logger.error(f"Error extracting files: {e}")
    
    return result


def verify_site_data_removal(cookies_path: Optional[str], prefs_path: Optional[str], 
                             domain: str) -> Dict[str, Any]:
    """
    Verify that all site data has been removed for the domain.
    
    Checks 4 criteria:
    1. Cookies removed
    2. Permissions cleared
    3. Settings cleared (zoom levels)
    4. No domain references in preferences
    
    Args:
        cookies_path: Path to Cookies database
        prefs_path: Path to Preferences file
        domain: Target domain to check
        
    Returns:
        Verification result dict
    """
    criteria_results = {
        "cookies_cleared": False,
        "permissions_cleared": False,
        "settings_cleared": False,
        "no_pref_references": False
    }
    
    feedback_parts = []
    
    # Criterion 1: Check cookies are removed
    if cookies_path and os.path.exists(cookies_path):
        cookies_ok, cookie_count, cookie_msg = check_cookies_removed(cookies_path, domain)
        criteria_results["cookies_cleared"] = cookies_ok
        feedback_parts.append(f"{'✓' if cookies_ok else '✗'} Cookies: {cookie_msg}")
        logger.info(f"Cookie check: {cookie_msg} (passed={cookies_ok})")
    else:
        feedback_parts.append("⚠ Cookies: Database not accessible")
        logger.warning("Cookies database not available for verification")
    
    # Criteria 2-4: Check Preferences file
    if prefs_path and os.path.exists(prefs_path):
        try:
            with open(prefs_path, 'r', encoding='utf-8') as f:
                prefs = json.load(f)
            
            # Criterion 2: Check permissions cleared
            perms_ok, perms_msg = check_permissions_cleared(prefs, domain)
            criteria_results["permissions_cleared"] = perms_ok
            feedback_parts.append(f"{'✓' if perms_ok else '✗'} Permissions: {perms_msg}")
            logger.info(f"Permissions check: {perms_msg} (passed={perms_ok})")
            
            # Criterion 3: Check settings cleared (zoom levels)
            settings_ok, settings_msg = check_settings_cleared(prefs, domain)
            criteria_results["settings_cleared"] = settings_ok
            feedback_parts.append(f"{'✓' if settings_ok else '✗'} Settings: {settings_msg}")
            logger.info(f"Settings check: {settings_msg} (passed={settings_ok})")
            
            # Criterion 4: Check no other references to domain
            refs_ok, refs_msg = check_no_domain_references(prefs, domain)
            criteria_results["no_pref_references"] = refs_ok
            feedback_parts.append(f"{'✓' if refs_ok else '✗'} Pref References: {refs_msg}")
            logger.info(f"References check: {refs_msg} (passed={refs_ok})")
            
        except json.JSONDecodeError as e:
            feedback_parts.append(f"⚠ Preferences: Failed to parse JSON - {e}")
            logger.error(f"Failed to parse Preferences: {e}")
        except Exception as e:
            feedback_parts.append(f"⚠ Preferences: Error checking - {e}")
            logger.error(f"Error checking preferences: {e}")
    else:
        feedback_parts.append("⚠ Preferences: File not accessible")
        logger.warning("Preferences file not available for verification")
    
    # Calculate score
    criteria_met = sum(criteria_results.values())
    score = int((criteria_met / 4.0) * 100)
    passed = score >= 75  # Need at least 3/4 criteria
    
    # Build final feedback
    feedback = f"Site Data Deletion Verification for {domain}\n"
    feedback += "=" * 50 + "\n"
    feedback += f"Criteria met: {criteria_met}/4\n"
    feedback += "\n".join(feedback_parts)
    feedback += "\n" + "=" * 50
    feedback += f"\nFinal Score: {score}%"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    if not passed:
        feedback += f"\n\nNote: At least 3 out of 4 criteria must be met to pass."
        feedback += f"\nSome site data for {domain} may still remain."
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": criteria_results
    }


def check_cookies_removed(cookies_path: str, domain: str) -> Tuple[bool, int, str]:
    """
    Check if all cookies for domain have been removed.
    
    Returns:
        Tuple of (passed, count, message)
    """
    try:
        conn = sqlite3.connect(cookies_path)
        cursor = conn.cursor()
        
        # Check for cookies with host_key matching domain (including subdomains)
        cursor.execute(
            "SELECT COUNT(*) FROM cookies WHERE host_key LIKE ? OR host_key LIKE ?",
            (f"%{domain}%", f"%.{domain}%")
        )
        count = cursor.fetchone()[0]
        conn.close()
        
        if count == 0:
            return True, 0, f"All cookies removed for {domain}"
        else:
            # Get sample cookie names for feedback
            conn = sqlite3.connect(cookies_path)
            cursor = conn.cursor()
            cursor.execute(
                "SELECT name, host_key FROM cookies WHERE host_key LIKE ? OR host_key LIKE ? LIMIT 3",
                (f"%{domain}%", f"%.{domain}%")
            )
            samples = cursor.fetchall()
            conn.close()
            
            sample_str = ", ".join([f"{name} ({host})" for name, host in samples])
            return False, count, f"{count} cookie(s) remain: {sample_str}"
            
    except sqlite3.Error as e:
        logger.error(f"SQLite error checking cookies: {e}")
        return False, -1, f"Database error: {e}"
    except Exception as e:
        logger.error(f"Error checking cookies: {e}")
        return False, -1, f"Error: {e}"


def check_permissions_cleared(prefs: dict, domain: str) -> Tuple[bool, str]:
    """
    Check if permissions for domain have been cleared.
    
    Returns:
        Tuple of (passed, message)
    """
    try:
        exceptions = prefs.get('profile', {}).get('content_settings', {}).get('exceptions', {})
        
        found_permissions = []
        
        for setting_type, settings in exceptions.items():
            if not isinstance(settings, dict):
                continue
                
            for url_pattern in settings.keys():
                if domain in url_pattern:
                    found_permissions.append(f"{setting_type} ({url_pattern})")
        
        if not found_permissions:
            return True, f"No permissions found for {domain}"
        else:
            return False, f"Found {len(found_permissions)} permission(s): {', '.join(found_permissions[:3])}"
            
    except Exception as e:
        logger.error(f"Error checking permissions: {e}")
        return False, f"Error: {e}"


def check_settings_cleared(prefs: dict, domain: str) -> Tuple[bool, str]:
    """
    Check if custom settings (e.g., zoom levels) for domain have been cleared.
    
    Returns:
        Tuple of (passed, message)
    """
    try:
        # Check zoom levels
        zoom_levels = prefs.get('partition', {}).get('per_host_zoom_levels', {})
        
        if domain in zoom_levels:
            zoom_value = zoom_levels[domain]
            return False, f"Custom zoom level ({zoom_value}) still set for {domain}"
        
        # Check other per-site settings
        # (Could expand this to check font sizes, javascript settings, etc.)
        
        return True, f"No custom settings found for {domain}"
        
    except Exception as e:
        logger.error(f"Error checking settings: {e}")
        return False, f"Error: {e}"


def check_no_domain_references(prefs: dict, domain: str) -> Tuple[bool, str]:
    """
    Check that domain doesn't appear anywhere else in preferences.
    
    Returns:
        Tuple of (passed, message)
    """
    try:
        # Convert prefs to JSON string and search for domain
        prefs_str = json.dumps(prefs)
        
        # Count occurrences (case-insensitive)
        count = len(re.findall(re.escape(domain), prefs_str, re.IGNORECASE))
        
        if count == 0:
            return True, f"No references to {domain} in preferences"
        else:
            # Some references might be acceptable (e.g., in history metadata)
            # but we want to flag if there are many
            if count <= 2:
                return True, f"Minimal references ({count}) to {domain} found (acceptable)"
            else:
                return False, f"Multiple references ({count}) to {domain} still in preferences"
            
    except Exception as e:
        logger.error(f"Error checking domain references: {e}")
        return False, f"Error: {e}"


def cleanup_temp_files(data_files: dict):
    """Clean up temporary files."""
    for path in data_files.values():
        if path and os.path.exists(path):
            try:
                os.unlink(path)
                logger.debug(f"Cleaned up temp file: {path}")
            except Exception as e:
                logger.warning(f"Could not clean up {path}: {e}")
