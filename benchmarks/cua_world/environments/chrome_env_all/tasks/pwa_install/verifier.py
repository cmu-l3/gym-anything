#!/usr/bin/env python3
"""
Verifier for Chrome PWA Installation Task (pwa_install@1)
Task: Install a Progressive Web App with 'Open as window' configuration

Verification Strategy:
- Check Chrome Preferences for web_apps entries
- Look for desktop shortcut files (.desktop)
- Verify Web Applications directory exists
- Validate launch mode is set to standalone/window
- Confirm URL association is correct
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
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../utils'))
try:
    from chrome_verification_utils import (
        cleanup_verification_temp,
        parse_preferences
    )
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for PWA installation task.
    
    Verifies:
    1. Preferences file contains web app entry
    2. Desktop shortcut exists (optional but desired)
    3. Web Applications directory has app data
    4. Launch mode is standalone/window
    5. URL association is correct
    6. Proper app name configuration
    
    Scoring:
    - 100%: All 6 criteria met (perfect installation)
    - 85-99%: 5/6 criteria met (very good)
    - 75-84%: 4/6 criteria met (good, passing)
    - 60-74%: 3/6 criteria met (partial)
    - <60%: <3 criteria met (failed)
    
    Pass threshold: 75% (at least 4 out of 6 criteria)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available"
        }
    
    # Expected PWA parameters
    expected_url = "http://localhost:8080/"
    expected_app_name = "Test PWA Application"
    
    criteria_met = 0
    total_criteria = 6
    feedback_parts = []
    details = {}
    
    try:
        # Criterion 1: Check Preferences for web_apps entry
        logger.info("Checking Preferences for web app entry...")
        prefs_ok, prefs_feedback, prefs_details = check_preferences_entry(
            copy_from_env, expected_url
        )
        
        if prefs_ok:
            criteria_met += 1
            feedback_parts.append(f"✓ {prefs_feedback}")
        else:
            feedback_parts.append(f"✗ {prefs_feedback}")
        details.update(prefs_details)
        
        # Criterion 2: Check for desktop shortcut
        logger.info("Checking for desktop shortcut...")
        shortcut_ok, shortcut_feedback = check_desktop_shortcut(
            copy_from_env, expected_url
        )
        
        if shortcut_ok:
            criteria_met += 1
            feedback_parts.append(f"✓ {shortcut_feedback}")
        else:
            # Desktop shortcut is nice-to-have but not critical
            # Give partial credit
            criteria_met += 0.3
            feedback_parts.append(f"⚠ {shortcut_feedback} (partial credit)")
        
        # Criterion 3: Check Web Applications directory
        logger.info("Checking Web Applications directory...")
        webapp_dir_ok, webapp_dir_feedback = check_web_applications_dir(
            copy_from_env
        )
        
        if webapp_dir_ok:
            criteria_met += 1
            feedback_parts.append(f"✓ {webapp_dir_feedback}")
        else:
            feedback_parts.append(f"✗ {webapp_dir_feedback}")
        
        # Criterion 4: Verify launch mode is standalone
        logger.info("Checking launch mode configuration...")
        launch_mode_ok, launch_mode_feedback = check_launch_mode(
            prefs_details.get('web_apps_data', {}), expected_url
        )
        
        if launch_mode_ok:
            criteria_met += 1
            feedback_parts.append(f"✓ {launch_mode_feedback}")
        else:
            feedback_parts.append(f"✗ {launch_mode_feedback}")
        
        # Criterion 5: Verify URL association
        logger.info("Checking URL association...")
        url_ok, url_feedback = check_url_association(
            prefs_details.get('web_apps_data', {}), expected_url
        )
        
        if url_ok:
            criteria_met += 1
            feedback_parts.append(f"✓ {url_feedback}")
        else:
            feedback_parts.append(f"✗ {url_feedback}")
        
        # Criterion 6: Check app name configuration
        logger.info("Checking app name configuration...")
        name_ok, name_feedback = check_app_name(
            prefs_details.get('web_apps_data', {}), expected_app_name
        )
        
        if name_ok:
            criteria_met += 1
            feedback_parts.append(f"✓ {name_feedback}")
        else:
            # Name mismatch is minor, give partial credit
            criteria_met += 0.5
            feedback_parts.append(f"⚠ {name_feedback} (partial credit)")
        
        # Calculate final score
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75
        
        # Build final feedback
        feedback = "\n".join(feedback_parts)
        feedback += f"\n\n{'='*50}"
        feedback += f"\nCriteria met: {criteria_met:.1f}/{total_criteria}"
        feedback += f"\nFinal score: {score}%"
        feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
        
        if not passed:
            feedback += "\n\nTo complete this task successfully, ensure you:"
            feedback += "\n1. Use Chrome's install feature (address bar icon or menu)"
            feedback += "\n2. Check 'Open as window' option in the installation dialog"
            feedback += "\n3. Complete the installation process"
        
        logger.info(f"Verification complete: passed={passed}, score={score}")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "details": {
                "criteria_met": round(criteria_met, 1),
                "total_criteria": total_criteria,
                **details
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        cleanup_verification_temp()


def check_preferences_entry(copy_from_env, expected_url: str) -> Tuple[bool, str, Dict]:
    """Check if Preferences file contains web app entry."""
    try:
        # Try to copy Preferences file
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        # Try multiple possible locations
        prefs_paths = [
            "/tmp/pwa_verification/Preferences.json",
            "/tmp/Preferences.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        prefs_data = None
        for prefs_path in prefs_paths:
            try:
                logger.info(f"Trying to copy Preferences from: {prefs_path}")
                copy_from_env(prefs_path, temp_file.name)
                
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    with open(temp_file.name, 'r', encoding='utf-8') as f:
                        prefs_data = json.load(f)
                    logger.info(f"Successfully loaded Preferences from: {prefs_path}")
                    break
            except Exception as e:
                logger.debug(f"Failed to copy from {prefs_path}: {e}")
                continue
        
        if not prefs_data:
            return False, "Could not access Preferences file", {"web_apps_data": {}}
        
        # Look for web_apps entries
        web_apps = prefs_data.get('web_apps', {})
        
        if not web_apps:
            return False, "No web apps registered in Preferences", {"web_apps_data": {}}
        
        # Check if our PWA is registered
        pwa_found = False
        for app_id, app_data in web_apps.items():
            start_url = app_data.get('start_url', '')
            if 'localhost:8080' in start_url:
                pwa_found = True
                break
        
        if pwa_found:
            return True, "Web app registered in Chrome Preferences", {"web_apps_data": web_apps}
        else:
            return False, "PWA not found in web_apps registry", {"web_apps_data": web_apps}
        
    except json.JSONDecodeError as e:
        return False, f"Failed to parse Preferences JSON: {e}", {"web_apps_data": {}}
    except Exception as e:
        return False, f"Error checking Preferences: {e}", {"web_apps_data": {}}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)


def check_desktop_shortcut(copy_from_env, expected_url: str) -> Tuple[bool, str]:
    """Check if desktop shortcut was created."""
    try:
        # Look for .desktop files in verification directory
        temp_dir = tempfile.mkdtemp()
        
        # Try to copy any .desktop files from verification directory
        desktop_files = []
        for i in range(10):  # Check up to 10 possible desktop files
            try:
                temp_file = os.path.join(temp_dir, f"app_{i}.desktop")
                copy_from_env(f"/tmp/pwa_verification/chrome-*.desktop", temp_file)
                if os.path.exists(temp_file) and os.path.getsize(temp_file) > 0:
                    desktop_files.append(temp_file)
            except:
                break
        
        # Also try looking for specific files
        try:
            temp_file = os.path.join(temp_dir, "test_pwa.desktop")
            copy_from_env("/home/ga/Desktop/chrome-*.desktop", temp_file)
            if os.path.exists(temp_file):
                desktop_files.append(temp_file)
        except:
            pass
        
        if not desktop_files:
            return False, "No desktop shortcut found"
        
        # Check if any .desktop file references our PWA
        for desktop_file in desktop_files:
            try:
                with open(desktop_file, 'r') as f:
                    content = f.read()
                
                if 'localhost:8080' in content and '--app=' in content:
                    return True, "Desktop shortcut created successfully"
            except:
                continue
        
        return False, "Desktop shortcut found but doesn't reference PWA correctly"
        
    except Exception as e:
        return False, f"Could not verify desktop shortcut: {e}"
    finally:
        # Cleanup temp directory
        import shutil
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)


def check_web_applications_dir(copy_from_env) -> Tuple[bool, str]:
    """Check if Web Applications directory exists with app data."""
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        temp_file.close()
        
        try:
            copy_from_env("/tmp/pwa_verification/web_apps_dir.txt", temp_file.name)
            
            if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                with open(temp_file.name, 'r') as f:
                    web_apps_dir = f.read().strip()
                
                if web_apps_dir:
                    return True, f"Web Applications directory present"
        except:
            pass
        
        # Try to check for manifest files
        try:
            manifest_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
            manifest_file.close()
            
            copy_from_env("/tmp/pwa_verification/Manifest*.json", manifest_file.name)
            
            if os.path.exists(manifest_file.name) and os.path.getsize(manifest_file.name) > 0:
                return True, "Web app manifest files found"
        except:
            pass
        
        return False, "Web Applications directory not found or empty"
        
    except Exception as e:
        return False, f"Could not verify Web Applications directory: {e}"
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)


def check_launch_mode(web_apps_data: Dict, expected_url: str) -> Tuple[bool, str]:
    """Verify app is configured to launch in standalone/window mode."""
    if not web_apps_data:
        return False, "No web apps data available to check launch mode"
    
    for app_id, app_data in web_apps_data.items():
        start_url = app_data.get('start_url', '')
        
        if 'localhost:8080' in start_url:
            # Check display mode
            display_mode = app_data.get('display_mode', '')
            user_display_mode = app_data.get('user_display_mode', '')
            
            # Valid standalone modes
            valid_modes = ['standalone', 'window', 'minimal-ui']
            
            if display_mode in valid_modes or user_display_mode in valid_modes:
                return True, f"Launch mode set to '{display_mode or user_display_mode}' (standalone)"
            else:
                return False, f"Launch mode is '{display_mode}' (should be standalone/window)"
    
    return False, "Could not find launch mode configuration for PWA"


def check_url_association(web_apps_data: Dict, expected_url: str) -> Tuple[bool, str]:
    """Verify app is associated with correct URL."""
    if not web_apps_data:
        return False, "No web apps data available to check URL"
    
    for app_id, app_data in web_apps_data.items():
        start_url = app_data.get('start_url', '')
        
        if 'localhost:8080' in start_url:
            # Normalize URLs for comparison
            if start_url.rstrip('/') == expected_url.rstrip('/') or 'localhost:8080' in start_url:
                return True, f"URL association correct: {start_url}"
    
    return False, "PWA not associated with expected URL (localhost:8080)"


def check_app_name(web_apps_data: Dict, expected_name: str) -> Tuple[bool, str]:
    """Verify app has correct name."""
    if not web_apps_data:
        return False, "No web apps data available to check name"
    
    for app_id, app_data in web_apps_data.items():
        start_url = app_data.get('start_url', '')
        
        if 'localhost:8080' in start_url:
            app_name = app_data.get('name', '')
            
            # Check for exact match or close match
            if app_name == expected_name:
                return True, f"App name correct: '{app_name}'"
            elif 'pwa' in app_name.lower() or 'test' in app_name.lower():
                return True, f"App name acceptable: '{app_name}'"
            else:
                return False, f"App name mismatch: '{app_name}' (expected '{expected_name}')"
    
    return False, "Could not find app name configuration"
