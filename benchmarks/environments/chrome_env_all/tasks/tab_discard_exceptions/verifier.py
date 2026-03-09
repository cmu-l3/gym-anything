#!/usr/bin/env python3
"""
Verifier for Chrome Memory Saver Configuration Task (tab_discard_exceptions@1)
Task: Configure Memory Saver feature and add site-specific tab discard exceptions

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON to extract Memory Saver configuration
- Verify Memory Saver is enabled
- Check that site exceptions list contains required sites (mail.google.com, calendar.google.com)
- Validate exception list format and persistence
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
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
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


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for tab_discard_exceptions@1.
    
    Verifies that:
    1. Memory Saver is enabled
    2. Site exceptions are properly configured
    3. Required sites (mail.google.com, calendar.google.com) are in exception list
    4. Configuration is properly persisted
    
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
        # Extract Memory Saver configuration from Preferences
        prefs_data, error_msg = get_preferences_data(copy_from_env)
        
        if prefs_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to retrieve Chrome preferences: {error_msg}"
            }
        
        # Verify Memory Saver configuration
        verification_result = verify_memory_saver_config(prefs_data)
        
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


def get_preferences_data(copy_from_env) -> Tuple[Optional[Dict], str]:
    """
    Retrieve and parse Chrome Preferences file from container.
    
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
                
                if prefs_data:
                    logger.info("Successfully parsed preferences using utilities")
                    return prefs_data, ""
                else:
                    logger.warning("Utility-based parsing returned empty, trying fallback")
        
        # Fallback: Manual extraction
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        # Try multiple possible locations
        possible_paths = [
            "/tmp/chrome_preferences_final.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        prefs_data = None
        source_path = None
        
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy from: {container_path}")
                copy_from_env(container_path, temp_file.name)
                
                # Check if file was copied successfully
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    with open(temp_file.name, 'r', encoding='utf-8') as f:
                        prefs_data = json.load(f)
                    source_path = container_path
                    logger.info(f"✓ Successfully copied and parsed from: {container_path}")
                    break
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if prefs_data is None:
            return None, "Could not access Preferences file from any known location"
        
        return prefs_data, ""
        
    except json.JSONDecodeError as e:
        return None, f"Failed to parse Preferences JSON: {e}"
    except Exception as e:
        return None, f"Error retrieving preferences: {e}"
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def verify_memory_saver_config(prefs_dict: Dict) -> Dict[str, Any]:
    """
    Verify Memory Saver is enabled and exceptions are configured.
    
    Chrome stores Memory Saver settings in various locations depending on version:
    - performance_tuning.high_efficiency_mode
    - profile.memory_saver_mode
    - performance.high_efficiency_mode
    - etc.
    
    Args:
        prefs_dict: Parsed Chrome Preferences dictionary
        
    Returns:
        Verification result with passed, score, and detailed feedback
    """
    # Required sites for task
    required_sites = ["mail.google.com", "calendar.google.com"]
    optional_sites = ["meet.google.com", "docs.google.com"]
    
    # Try to find Memory Saver configuration in various possible locations
    memory_saver_enabled = False
    exceptions_list = []
    config_found = False
    
    # Possible paths where Memory Saver settings might be stored
    possible_config_paths = [
        ("performance_tuning", "high_efficiency_mode"),
        ("performance", "high_efficiency_mode"),
        ("profile", "memory_saver_mode"),
        ("profile", "tab_discard_exceptions"),
        ("browser", "memory_saver"),
    ]
    
    logger.info("Searching for Memory Saver configuration...")
    
    for path in possible_config_paths:
        try:
            section = prefs_dict
            path_str = ".".join(path)
            
            # Navigate to the section
            for key in path:
                if key not in section:
                    break
                section = section[key]
            else:
                # Successfully navigated to section
                logger.info(f"Found configuration section at: {path_str}")
                config_found = True
                
                # Check if Memory Saver is enabled
                if isinstance(section, dict):
                    # Check various possible enable keys
                    if section.get("state") == "enabled" or section.get("state") == 1:
                        memory_saver_enabled = True
                    elif section.get("enabled") is True:
                        memory_saver_enabled = True
                    elif section.get("mode") == "enabled":
                        memory_saver_enabled = True
                    
                    # Get exception list
                    if "exceptions" in section:
                        exceptions_list = section.get("exceptions", [])
                    elif "exception_list" in section:
                        exceptions_list = section.get("exception_list", [])
                    elif "sites" in section:
                        exceptions_list = section.get("sites", [])
                    
                    if memory_saver_enabled or exceptions_list:
                        logger.info(f"Using configuration from: {path_str}")
                        logger.info(f"  Enabled: {memory_saver_enabled}")
                        logger.info(f"  Exceptions: {exceptions_list}")
                        break
        except Exception as e:
            logger.debug(f"Error checking path {path}: {e}")
            continue
    
    # If no standard path worked, try broader search
    if not config_found or not exceptions_list:
        logger.info("Standard paths not found, trying broader search...")
        exceptions_list, memory_saver_enabled = search_for_memory_saver_config(prefs_dict)
    
    # Normalize exception list (handle various formats)
    exceptions_list = normalize_exceptions(exceptions_list)
    
    logger.info(f"Final configuration state:")
    logger.info(f"  Memory Saver enabled: {memory_saver_enabled}")
    logger.info(f"  Exceptions count: {len(exceptions_list)}")
    logger.info(f"  Exceptions: {exceptions_list}")
    
    # Verify required sites are in exceptions
    found_required = []
    found_optional = []
    
    for site in required_sites:
        if any(normalize_site(site) == normalize_site(exc) for exc in exceptions_list):
            found_required.append(site)
    
    for site in optional_sites:
        if any(normalize_site(site) == normalize_site(exc) for exc in exceptions_list):
            found_optional.append(site)
    
    required_count = len(found_required)
    optional_count = len(found_optional)
    total_exceptions = len(exceptions_list)
    
    logger.info(f"Site verification:")
    logger.info(f"  Required sites found: {required_count}/2 - {found_required}")
    logger.info(f"  Optional sites found: {optional_count} - {found_optional}")
    
    # Calculate score based on criteria
    criteria = {
        "memory_saver_enabled": memory_saver_enabled,
        "has_exceptions": total_exceptions > 0,
        "required_sites_present": required_count >= 2,
        "well_configured": required_count == 2 and (optional_count >= 1 or total_exceptions >= 3)
    }
    
    criteria_met = sum(criteria.values())
    
    # Scoring logic
    if not memory_saver_enabled:
        score = 0
        feedback = "❌ Memory Saver is not enabled. Please enable it in chrome://settings/performance"
    elif required_count == 0:
        score = 25
        feedback = f"⚠ Memory Saver enabled but no required site exceptions found. Please add {', '.join(required_sites)}"
    elif required_count == 1:
        score = 50
        missing = [s for s in required_sites if s not in found_required][0]
        feedback = f"⚠ Memory Saver enabled but missing required site: {missing}"
    elif required_count == 2 and optional_count == 0 and total_exceptions == 2:
        score = 85
        feedback = f"✓ Memory Saver enabled with both required sites ({', '.join(found_required)}). Consider adding optional sites for full credit."
    elif required_count == 2:
        score = 100
        all_sites = found_required + found_optional
        feedback = f"✅ Memory Saver perfectly configured with {total_exceptions} exception(s): {', '.join(all_sites[:4])}{'...' if len(all_sites) > 4 else ''}"
    else:
        score = 60
        feedback = "⚠ Partial Memory Saver configuration detected"
    
    passed = score >= 75
    
    # Build detailed feedback
    feedback_parts = [feedback]
    feedback_parts.append(f"\nConfiguration Details:")
    feedback_parts.append(f"  • Memory Saver: {'✓ Enabled' if memory_saver_enabled else '✗ Not enabled'}")
    feedback_parts.append(f"  • Total exceptions: {total_exceptions}")
    feedback_parts.append(f"  • Required sites ({required_count}/2): {', '.join(found_required) if found_required else 'None'}")
    if found_optional:
        feedback_parts.append(f"  • Optional sites: {', '.join(found_optional)}")
    
    if not passed:
        feedback_parts.append(f"\nTo pass (75%+), ensure:")
        if not memory_saver_enabled:
            feedback_parts.append(f"  1. Enable Memory Saver in chrome://settings/performance")
        if required_count < 2:
            feedback_parts.append(f"  2. Add required sites: {', '.join(required_sites)}")
    
    final_feedback = "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": final_feedback,
        "details": {
            "memory_saver_enabled": memory_saver_enabled,
            "exceptions_count": total_exceptions,
            "required_sites_found": required_count,
            "optional_sites_found": optional_count,
            "exceptions": exceptions_list,
            "found_required": found_required,
            "found_optional": found_optional,
            "criteria": criteria
        }
    }


def search_for_memory_saver_config(prefs_dict: Dict) -> Tuple[List[str], bool]:
    """
    Perform a broader search through preferences for Memory Saver related settings.
    
    Args:
        prefs_dict: Full preferences dictionary
        
    Returns:
        Tuple of (exceptions_list, memory_saver_enabled)
    """
    exceptions = []
    enabled = False
    
    def recursive_search(obj, path=""):
        """Recursively search for Memory Saver related keys"""
        nonlocal exceptions, enabled
        
        if isinstance(obj, dict):
            for key, value in obj.items():
                current_path = f"{path}.{key}" if path else key
                
                # Look for enable-related keys
                if key in ["enabled", "state", "mode"] and isinstance(value, (bool, str, int)):
                    if value in [True, "enabled", 1, "on"]:
                        if any(keyword in path.lower() for keyword in ["memory", "saver", "efficiency", "discard"]):
                            enabled = True
                            logger.info(f"Found enabled flag at: {current_path}")
                
                # Look for exception lists
                if key in ["exceptions", "exception_list", "sites", "allowed_sites", "excluded_sites"]:
                    if isinstance(value, list):
                        if any(keyword in path.lower() for keyword in ["memory", "saver", "discard", "tab"]):
                            exceptions.extend([str(v) for v in value if isinstance(v, str)])
                            logger.info(f"Found exception list at: {current_path} with {len(value)} items")
                
                # Recurse into nested structures
                recursive_search(value, current_path)
    
    recursive_search(prefs_dict)
    
    return exceptions, enabled


def normalize_exceptions(exceptions_list: List) -> List[str]:
    """
    Normalize exception list to handle various formats.
    
    Args:
        exceptions_list: Raw exception list from preferences
        
    Returns:
        List of normalized domain strings
    """
    normalized = []
    
    for item in exceptions_list:
        if isinstance(item, str):
            normalized.append(item)
        elif isinstance(item, dict):
            # Sometimes exceptions are stored as objects with 'site' or 'domain' key
            if 'site' in item:
                normalized.append(str(item['site']))
            elif 'domain' in item:
                normalized.append(str(item['domain']))
            elif 'url' in item:
                normalized.append(str(item['url']))
    
    return normalized


def normalize_site(site: str) -> str:
    """
    Normalize site URL for comparison.
    
    Args:
        site: Site URL or domain
        
    Returns:
        Normalized domain string
    """
    # Remove protocols
    site = site.replace('https://', '').replace('http://', '')
    # Remove trailing slashes
    site = site.rstrip('/')
    # Remove www prefix
    site = site.replace('www.', '')
    # Convert to lowercase
    site = site.lower()
    return site
