#!/usr/bin/env python3
"""
Verifier for Chrome Search Engine Configuration Task (search_engine_config@1)
Task: Change default search engine from Google to DuckDuckGo

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON and extract default_search_provider_data section
- Check multiple fields (keyword, short_name, name, search_url) for DuckDuckGo markers
- Require at least 2 out of 4 markers for pass (75% threshold)
- Provide detailed feedback on configuration status
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
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../..', 'utils'))
try:
    from chrome_verification_utils import (
        setup_chrome_verification,
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
    Main verification function for search_engine_config@1 task.
    
    Verifies that DuckDuckGo was successfully set as the default search engine.
    
    Args:
        traj: Agent trajectory (list of states/actions/observations)
        env_info: Environment information including copy_from_env function
        task_info: Task specification information
        
    Returns:
        Dict with 'passed' (bool), 'score' (int 0-100), and 'feedback' (str) keys
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available in environment"
        }

    try:
        # Step 1: Extract Preferences file from container
        prefs_data, error_msg = extract_preferences_from_container(copy_from_env)
        
        if prefs_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to retrieve Chrome Preferences: {error_msg}"
            }
        
        # Step 2: Check if settings page was accessed (optional - adds context)
        settings_accessed = check_settings_access_in_trajectory(traj, copy_from_env)
        
        # Step 3: Verify search engine configuration
        verification_result = verify_search_engine_configuration(prefs_data, settings_accessed)
        
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
    
    Tries multiple possible locations for the Preferences file.
    
    Args:
        copy_from_env: Function to copy files from container to host
        
    Returns:
        Tuple of (preferences_dict or None, error_message)
    """
    # Try using utilities if available
    if UTILS_AVAILABLE:
        try:
            success, files, error = setup_chrome_verification(
                copy_from_env,
                ["Preferences"],
                user="ga",
                profile="Default"
            )
            
            if success:
                prefs_path = files["Preferences"]
                prefs = parse_preferences(prefs_path)
                logger.info("✓ Successfully extracted Preferences using utilities")
                return prefs, ""
            else:
                logger.warning(f"Utility-based extraction failed: {error}, trying fallback")
        except Exception as e:
            logger.warning(f"Exception in utility extraction: {e}, trying fallback")
    
    # Fallback: Manual extraction
    temp_file = None
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()
        
        # Try multiple possible locations
        possible_paths = [
            "/tmp/chrome_preferences_after_task.json",
            "/tmp/preferences_export.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences",
            "/home/ga/.config/chromium/Default/Preferences"
        ]
        
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy from: {container_path}")
                copy_from_env(container_path, temp_path)
                
                # Check if file was copied and has content
                if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
                    with open(temp_path, 'r', encoding='utf-8') as f:
                        prefs_data = json.load(f)
                    
                    # Check if it's an error marker file
                    if "error" in prefs_data:
                        logger.warning(f"Error marker found in copied file: {prefs_data.get('error')}")
                        continue
                    
                    logger.info(f"✓ Successfully copied and parsed Preferences from: {container_path}")
                    os.unlink(temp_path)
                    return prefs_data, ""
                    
            except json.JSONDecodeError as e:
                logger.debug(f"JSON decode error for {container_path}: {e}")
                continue
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        # If we get here, none of the paths worked
        if temp_file and os.path.exists(temp_path):
            os.unlink(temp_path)
        
        return None, "Could not access Preferences file from any known location"
        
    except Exception as e:
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass
        return None, f"Error extracting Preferences: {str(e)}"


def check_settings_access_in_trajectory(traj, copy_from_env) -> bool:
    """
    Check if agent accessed Chrome settings page during task execution.
    
    This is optional verification that adds context but isn't required for pass/fail.
    
    Args:
        traj: Agent trajectory
        copy_from_env: Function to copy files from container
        
    Returns:
        bool: True if settings page was accessed
    """
    try:
        # Try to get final URL from export script
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        temp_file.close()
        
        try:
            copy_from_env("/tmp/final_active_url.txt", temp_file.name)
            with open(temp_file.name, 'r') as f:
                final_url = f.read().strip()
            os.unlink(temp_file.name)
            
            if "chrome://settings" in final_url.lower():
                logger.info("✓ Settings page detected in final URL")
                return True
        except:
            pass
        
        # Also check trajectory if available
        if traj:
            for state in traj:
                url = str(state.get('url', '')).lower() if isinstance(state, dict) else str(state).lower()
                if 'chrome://settings' in url or 'settings/search' in url:
                    logger.info("✓ Settings page detected in trajectory")
                    return True
        
        logger.info("Settings page access not detected (not required)")
        return False
        
    except Exception as e:
        logger.debug(f"Could not check settings access: {e}")
        return False


def verify_search_engine_configuration(prefs_data: Dict[str, Any], settings_accessed: bool) -> Dict[str, Any]:
    """
    Verify that DuckDuckGo was configured as the default search engine.
    
    Checks multiple fields in the Preferences JSON for DuckDuckGo markers:
    1. default_search_provider_data.keyword (e.g., "duckduckgo.com")
    2. default_search_provider_data.short_name (e.g., "DuckDuckGo")
    3. default_search_provider_data.name (e.g., "DuckDuckGo")
    4. default_search_provider_data.search_url (contains "duckduckgo.com")
    
    Scoring:
    - All 4 markers found: 100%
    - 3 markers found: 85%
    - 2 markers found: 75% (minimum passing)
    - 1 marker found: 60% (fail)
    - 0 markers found: 0-25% (fail)
    
    Args:
        prefs_data: Parsed Chrome Preferences JSON
        settings_accessed: Whether settings page was accessed
        
    Returns:
        Dict with verification results
    """
    # Extract search provider data
    search_provider = prefs_data.get('default_search_provider_data', {})
    
    if not search_provider:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No search provider configuration found in Preferences file. The search engine may not have been changed.",
            "details": {
                "markers_found": 0,
                "settings_accessed": settings_accessed
            }
        }
    
    # Extract relevant fields
    keyword = search_provider.get('keyword', '').lower()
    short_name = search_provider.get('short_name', '').lower()
    name = search_provider.get('name', '').lower()
    search_url = search_provider.get('search_url', '').lower()
    
    logger.info(f"Search provider configuration:")
    logger.info(f"  keyword: {keyword}")
    logger.info(f"  short_name: {short_name}")
    logger.info(f"  name: {name}")
    logger.info(f"  search_url: {search_url[:80]}...")
    
    # Check for DuckDuckGo markers (case-insensitive substring matching)
    markers = {
        'keyword': 'duckduckgo' in keyword or 'ddg' in keyword,
        'short_name': 'duckduckgo' in short_name,
        'name': 'duckduckgo' in name,
        'search_url': 'duckduckgo.com' in search_url or 'duckduckgo' in search_url
    }
    
    markers_found = sum(markers.values())
    total_markers = len(markers)
    
    # Log marker results
    logger.info(f"DuckDuckGo markers found: {markers_found}/{total_markers}")
    for field, found in markers.items():
        logger.info(f"  {field}: {'✓' if found else '✗'}")
    
    # Determine if it's still Google (failure case)
    is_google = (
        'google' in keyword or
        'google' in short_name.lower() or
        'google' in name.lower() or
        'google.com/search' in search_url
    )
    
    # Calculate score and feedback
    if markers_found >= 4:
        score = 100
        passed = True
        feedback = f"✅ DuckDuckGo successfully configured as default search engine (all {markers_found} markers confirmed)"
    elif markers_found >= 3:
        score = 85
        passed = True
        feedback = f"✅ DuckDuckGo configured as default search engine ({markers_found}/{total_markers} markers found - good)"
    elif markers_found >= 2:
        score = 75
        passed = True
        feedback = f"✅ DuckDuckGo configured as default search engine ({markers_found}/{total_markers} markers found - passing)"
    elif markers_found == 1:
        score = 60
        passed = False
        feedback = f"⚠️ Partial DuckDuckGo configuration detected ({markers_found}/{total_markers} marker) - configuration incomplete"
    else:
        # Check if it's still Google
        if is_google:
            score = 0
            feedback = "❌ Search engine unchanged - still set to Google. Please navigate to chrome://settings and change to DuckDuckGo."
        else:
            score = 25
            feedback = f"❌ DuckDuckGo not configured. Current search engine: {short_name or name or keyword or 'unknown'}"
        passed = False
    
    # Add context about settings access
    if not settings_accessed and not passed:
        feedback += "\n  Note: Chrome settings page was not detected in trajectory - agent may not have accessed settings."
    
    # Provide detailed marker information
    marker_details = []
    for field, found in markers.items():
        status = "✓" if found else "✗"
        value = locals()[field] if field in locals() else search_provider.get(field, '')
        marker_details.append(f"  {status} {field}: {value[:50]}")
    
    detailed_feedback = feedback + "\n\nMarker analysis:\n" + "\n".join(marker_details)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": detailed_feedback,
        "details": {
            "markers_found": markers_found,
            "total_markers": total_markers,
            "marker_details": markers,
            "settings_accessed": settings_accessed,
            "search_engine": {
                "keyword": keyword,
                "short_name": short_name,
                "name": name,
                "search_url": search_url[:100]
            },
            "is_google": is_google
        }
    }
