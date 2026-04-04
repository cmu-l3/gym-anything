#!/usr/bin/env python3
"""
Verifier for Exclude Heavy Directories task
"""

import sys
import os
import json
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_pattern(pattern):
    """Normalize a glob pattern for comparison"""
    # Remove leading/trailing asterisks and slashes for comparison
    normalized = pattern.strip('*').strip('/')
    return normalized.lower()


def check_directory_excluded(exclusions_dict, directory_name):
    """
    Check if a directory is excluded in the given exclusions dict
    
    Args:
        exclusions_dict: Dictionary of exclusion patterns
        directory_name: Directory name to check (e.g., 'node_modules')
    
    Returns:
        bool: True if directory is found in any pattern
    """
    if not isinstance(exclusions_dict, dict):
        return False
    
    for pattern in exclusions_dict.keys():
        normalized = normalize_pattern(pattern)
        if directory_name.lower() in normalized:
            return True
    
    return False


def verify_exclusion_setting(settings, setting_key, required_dirs):
    """
    Verify that a settings key contains exclusions for all required directories
    
    Args:
        settings: Parsed settings.json dict
        setting_key: Key to check (e.g., 'files.watcherExclude')
        required_dirs: List of directory names that must be excluded
    
    Returns:
        (success: bool, found_dirs: list, missing_dirs: list, message: str)
    """
    if setting_key not in settings:
        return False, [], required_dirs, f"Setting '{setting_key}' not found"
    
    exclusions = settings[setting_key]
    
    if not isinstance(exclusions, dict):
        return False, [], required_dirs, f"Setting '{setting_key}' must be a dictionary"
    
    found = []
    missing = []
    
    for dir_name in required_dirs:
        if check_directory_excluded(exclusions, dir_name):
            found.append(dir_name)
        else:
            missing.append(dir_name)
    
    if missing:
        return False, found, missing, f"Missing exclusions for: {', '.join(missing)}"
    
    return True, found, [], f"All directories excluded: {', '.join(found)}"


def verify_exclusion_settings(traj, env_info, task_info):
    """
    Main verification function for exclude_heavy_directories task
    
    Verifies that workspace settings.json properly excludes heavy directories
    from file watching, search, and explorer view.
    
    Returns:
        Dictionary with 'passed', 'score', and 'feedback' keys
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }
    
    temp_dir = tempfile.mkdtemp(prefix='vscode_verify_exclude_')
    
    try:
        # Copy settings file exported by export_result.sh
        settings_path = "/tmp/workspace_settings.json"
        local_settings = os.path.join(temp_dir, "settings.json")
        
        try:
            copy_from_env(settings_path, local_settings)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to copy settings file: {str(e)}"
            }
        
        # Check if file exists and has content
        if not os.path.exists(local_settings):
            return {
                "passed": False,
                "score": 0,
                "feedback": "Settings file not found at /home/ga/workspace/monorepo_project/.vscode/settings.json"
            }
        
        if os.path.getsize(local_settings) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Settings file is empty"
            }
        
        # Parse JSON
        try:
            with open(local_settings, 'r', encoding='utf-8') as f:
                settings = json.load(f)
        except json.JSONDecodeError as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Invalid JSON in settings file: {str(e)}"
            }
        
        # Required directories to exclude
        required_dirs = ['node_modules', 'build', '.venv', 'vendor', 'logs']
        
        # Check all three exclusion settings
        criteria = []
        feedback_parts = []
        
        # 1. Check files.watcherExclude
        watcher_ok, watcher_found, watcher_missing, watcher_msg = verify_exclusion_setting(
            settings, 'files.watcherExclude', required_dirs
        )
        criteria.append(watcher_ok)
        if watcher_ok:
            feedback_parts.append(f"✅ files.watcherExclude: {watcher_msg}")
        else:
            feedback_parts.append(f"❌ files.watcherExclude: {watcher_msg}")
        
        # 2. Check search.exclude
        search_ok, search_found, search_missing, search_msg = verify_exclusion_setting(
            settings, 'search.exclude', required_dirs
        )
        criteria.append(search_ok)
        if search_ok:
            feedback_parts.append(f"✅ search.exclude: {search_msg}")
        else:
            feedback_parts.append(f"❌ search.exclude: {search_msg}")
        
        # 3. Check files.exclude
        files_ok, files_found, files_missing, files_msg = verify_exclusion_setting(
            settings, 'files.exclude', required_dirs
        )
        criteria.append(files_ok)
        if files_ok:
            feedback_parts.append(f"✅ files.exclude: {files_msg}")
        else:
            feedback_parts.append(f"❌ files.exclude: {files_msg}")
        
        # All criteria must pass
        all_passed = all(criteria)
        criteria_passed = sum(criteria)
        score = int((criteria_passed / 3) * 100)
        
        feedback = " | ".join(feedback_parts)
        
        if all_passed:
            return {
                "passed": True,
                "score": 100,
                "feedback": f"✅ All exclusion settings configured correctly. {feedback}"
            }
        else:
            return {
                "passed": False,
                "score": score,
                "feedback": f"Incomplete configuration ({criteria_passed}/3 settings correct). {feedback}"
            }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        # Clean up temp directory
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
