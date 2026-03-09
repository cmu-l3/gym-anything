#!/usr/bin/env python3
"""
Verifier for fix_syntax_highlighting@1 task
Checks if .tpl files are correctly associated with HTML language mode in VSCode settings
"""

import sys
import os
import json
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import cleanup_verification_temp

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_syntax_highlighting_config(traj, env_info, task_info):
    """
    Verify that .tpl files are associated with HTML in VSCode settings.
    
    Success Criteria:
    1. files.associations setting exists
    2. *.tpl is mapped to html (case-insensitive)
    3. Configuration is persisted in user or workspace settings
    
    Args:
        traj: Agent trajectory (not used)
        env_info: Environment info dict containing 'copy_from_env' function
        task_info: Task info dict (not used)
        
    Returns:
        Dict with keys:
        - "passed" (bool): Whether task was completed successfully
        - "score" (int): Score 0-100
        - "feedback" (str): Human-readable feedback message
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Internal error: copy function not available"
        }

    temp_dir = tempfile.mkdtemp(prefix='vscode_verify_syntax_')

    try:
        results_dir = "/tmp/syntax_highlighting_results"
        
        # Paths to settings files in container
        user_settings_container = f"{results_dir}/user_settings.json"
        workspace_settings_container = f"{results_dir}/workspace_settings.json"
        
        # Local paths for copied files
        local_user_settings = os.path.join(temp_dir, "user_settings.json")
        local_workspace_settings = os.path.join(temp_dir, "workspace_settings.json")
        
        # Try to copy both settings files
        user_settings_exists = False
        workspace_settings_exists = False
        
        try:
            copy_from_env(user_settings_container, local_user_settings)
            if os.path.exists(local_user_settings) and os.path.getsize(local_user_settings) > 2:
                user_settings_exists = True
                logger.info("✓ User settings file retrieved")
        except Exception as e:
            logger.warning(f"Could not copy user settings: {e}")
        
        try:
            copy_from_env(workspace_settings_container, local_workspace_settings)
            if os.path.exists(local_workspace_settings) and os.path.getsize(local_workspace_settings) > 2:
                workspace_settings_exists = True
                logger.info("✓ Workspace settings file retrieved")
        except Exception as e:
            logger.warning(f"Could not copy workspace settings: {e}")
        
        # If neither settings file exists, task failed
        if not user_settings_exists and not workspace_settings_exists:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ No settings files found. You need to configure file associations in VSCode settings (Ctrl+, then search 'files associations')."
            }
        
        # Check settings files for the correct association
        found_association = False
        correct_association = False
        settings_location = None
        actual_value = None
        all_associations = {}
        
        # Build list of settings to check
        settings_to_check = []
        if user_settings_exists:
            settings_to_check.append(("user", local_user_settings))
        if workspace_settings_exists:
            settings_to_check.append(("workspace", local_workspace_settings))
        
        # Check each settings file
        for location, settings_path in settings_to_check:
            try:
                with open(settings_path, 'r', encoding='utf-8') as f:
                    settings = json.load(f)
                
                logger.info(f"Checking {location} settings")
                
                # Check if files.associations exists
                if "files.associations" in settings:
                    associations = settings["files.associations"]
                    logger.info(f"Found files.associations in {location}: {list(associations.keys())}")
                    
                    # Store for debugging feedback
                    all_associations[location] = list(associations.keys())
                    
                    # Check for *.tpl association (exact match required)
                    if "*.tpl" in associations:
                        found_association = True
                        actual_value = associations["*.tpl"]
                        settings_location = location
                        logger.info(f"Found *.tpl → '{actual_value}' in {location}")
                        
                        # Check if correctly set to "html" (case-insensitive)
                        if actual_value.lower() == "html":
                            correct_association = True
                            logger.info("✓ Correct association found!")
                            break  # Found correct config, stop checking
                        else:
                            logger.warning(f"Association value '{actual_value}' is not 'html'")
                else:
                    logger.info(f"No files.associations key in {location} settings")
            
            except json.JSONDecodeError as e:
                logger.error(f"Failed to parse {location} settings as JSON: {e}")
                continue
            except Exception as e:
                logger.error(f"Error reading {location} settings: {e}")
                continue
        
        # Determine result based on what was found
        if correct_association:
            # Perfect - correct association found
            return {
                "passed": True,
                "score": 100,
                "feedback": f"✅ Perfect! .tpl files are correctly associated with HTML in {settings_location} settings. Syntax highlighting will now work for .tpl files."
            }
        
        elif found_association:
            # Association exists but wrong value
            return {
                "passed": False,
                "score": 30,
                "feedback": f"⚠️ Found *.tpl association in {settings_location} settings, but it's set to '{actual_value}' instead of 'html'. Change the value to 'html' for proper syntax highlighting."
            }
        
        else:
            # No association found - provide helpful feedback
            if all_associations:
                # Settings exist but don't have .tpl
                locations = ", ".join(all_associations.keys())
                feedback = f"❌ No *.tpl association found. Settings checked: {locations}. "
                feedback += "Add '\"*.tpl\": \"html\"' to the 'files.associations' object in settings.json. "
                feedback += "You can access this via: Settings (Ctrl+,) > search 'files associations' > Add Item."
            else:
                # No files.associations key at all
                checked = ", ".join([loc for loc, _ in settings_to_check])
                feedback = f"❌ No 'files.associations' setting found in {checked}. "
                feedback += "Open Settings (Ctrl+,), search 'files associations', and add: *.tpl → html"
            
            return {
                "passed": False,
                "score": 0,
                "feedback": feedback
            }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    
    finally:
        # Clean up temporary directory
        cleanup_verification_temp(temp_dir)
