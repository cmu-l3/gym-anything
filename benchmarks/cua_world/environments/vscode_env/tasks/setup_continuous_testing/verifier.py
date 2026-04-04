#!/usr/bin/env python3
"""
Verifier for setup_continuous_testing@1
Checks that VSCode is configured for continuous testing workflow
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


def verify_continuous_testing_setup(traj, env_info, task_info):
    """
    Verify continuous testing configuration.
    
    Checks:
    1. User settings.json exists and is valid JSON (required)
    2. pytest is enabled (required) 
    3. Auto-test discovery on save is enabled (required)
    4. Auto-save is configured (recommended)
    5. Workspace settings configured (bonus)
    
    Returns:
        dict: {"passed": bool, "score": int, "feedback": str}
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "❌ Copy function not available"
        }
    
    temp_dir = tempfile.mkdtemp(prefix='vscode_testing_verify_')
    
    try:
        feedback_parts = []
        score = 0.0
        max_score = 5.0
        metadata = {}
        
        # Step 1: Verify user settings.json (required)
        user_settings_path = "/home/ga/.config/Code/User/settings.json"
        user_settings_verified = verify_user_settings(
            user_settings_path, 
            copy_from_env, 
            temp_dir,
            feedback_parts, 
            metadata
        )
        
        if not user_settings_verified:
            # Critical failure - settings file doesn't exist or is invalid
            return {
                "passed": False,
                "score": 0,
                "feedback": "\n".join(feedback_parts)
            }
        
        score += 1.0  # Settings file exists and is valid
        
        # Step 2: Check pytest enabled (required - 1.5 points)
        if metadata.get("pytest_enabled"):
            score += 1.5
            feedback_parts.append("✅ pytest is enabled (python.testing.pytestEnabled: true)")
        else:
            feedback_parts.append("❌ pytest is NOT enabled (python.testing.pytestEnabled should be true)")
        
        # Step 3: Check auto-test discovery on save (required - 1.5 points)
        if metadata.get("auto_discover_enabled"):
            score += 1.5
            feedback_parts.append("✅ Auto-test discovery on save is enabled")
        else:
            feedback_parts.append("❌ Auto-test discovery on save is NOT enabled (python.testing.autoTestDiscoverOnSaveEnabled should be true)")
        
        # Step 4: Check auto-save configured (recommended - 0.5 points)
        auto_save_mode = metadata.get("auto_save_mode", "off")
        if auto_save_mode != "off":
            score += 0.5
            feedback_parts.append(f"✅ Auto-save is configured (files.autoSave: '{auto_save_mode}')")
        else:
            feedback_parts.append("⚠️ Auto-save is not enabled (recommended: set files.autoSave to 'afterDelay')")
        
        # Step 5: Check workspace settings (bonus - 0.5 points)
        workspace_settings_path = "/home/ga/workspace/data_processor/.vscode/settings.json"
        workspace_configured = check_workspace_settings(
            workspace_settings_path,
            copy_from_env,
            temp_dir,
            metadata
        )
        if workspace_configured:
            score += 0.5
            feedback_parts.append("✅ Bonus: Workspace-specific settings configured")
        
        # Calculate final result
        score_percentage = int((score / max_score) * 100)
        passed = score >= 4.0  # Need at least 4/5 points
        
        # Add summary
        if passed:
            feedback_parts.append(f"\n✅ Task completed successfully! Score: {score:.1f}/{max_score} ({score_percentage}%)")
            feedback_parts.append("Continuous testing workflow is now active.")
        else:
            feedback_parts.append(f"\n❌ Task incomplete. Score: {score:.1f}/{max_score} ({score_percentage}%)")
            feedback_parts.append(f"Required: At least 4.0 points to pass.")
            
            # Provide specific guidance
            if not metadata.get("pytest_enabled"):
                feedback_parts.append("→ Enable pytest in Settings (Ctrl+,) or set python.testing.pytestEnabled to true")
            if not metadata.get("auto_discover_enabled"):
                feedback_parts.append("→ Enable auto-discover: set python.testing.autoTestDiscoverOnSaveEnabled to true")
        
        return {
            "passed": passed,
            "score": score_percentage,
            "feedback": "\n".join(feedback_parts)
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        # Cleanup temp directory
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)


def verify_user_settings(settings_path, copy_fn, temp_dir, feedback_parts, metadata):
    """
    Verify user settings.json exists and has correct pytest configuration.
    
    Returns:
        bool: True if settings file is valid, False otherwise
    """
    try:
        local_settings_path = os.path.join(temp_dir, "user_settings.json")
        
        # Copy settings file from container
        try:
            copy_fn(settings_path, local_settings_path)
        except Exception as e:
            feedback_parts.append(f"❌ Failed to copy settings file: {e}")
            return False
        
        # Check file exists and has content
        if not os.path.exists(local_settings_path):
            feedback_parts.append(f"❌ Settings file not found at {settings_path}")
            return False
        
        if os.path.getsize(local_settings_path) == 0:
            feedback_parts.append(f"❌ Settings file is empty")
            return False
        
        # Parse JSON
        try:
            with open(local_settings_path, 'r', encoding='utf-8') as f:
                settings = json.load(f)
        except json.JSONDecodeError as e:
            feedback_parts.append(f"❌ Settings file is not valid JSON: {e}")
            return False
        
        # Extract configuration values
        pytest_enabled = settings.get("python.testing.pytestEnabled", False)
        auto_discover = settings.get("python.testing.autoTestDiscoverOnSaveEnabled", False)
        auto_save = settings.get("files.autoSave", "off")
        pytest_args = settings.get("python.testing.pytestArgs", [])
        
        # Store in metadata
        metadata["pytest_enabled"] = pytest_enabled
        metadata["auto_discover_enabled"] = auto_discover
        metadata["auto_save_mode"] = auto_save
        metadata["pytest_args"] = pytest_args
        metadata["has_pytest_args"] = len(pytest_args) > 0
        
        feedback_parts.append("✅ Settings file found and parsed successfully")
        
        # Log settings for debugging
        logger.info(f"pytest_enabled: {pytest_enabled}")
        logger.info(f"auto_discover_enabled: {auto_discover}")
        logger.info(f"auto_save: {auto_save}")
        logger.info(f"pytest_args: {pytest_args}")
        
        return True
        
    except Exception as e:
        logger.error(f"Error verifying user settings: {e}", exc_info=True)
        feedback_parts.append(f"❌ Error reading settings: {e}")
        return False


def check_workspace_settings(settings_path, copy_fn, temp_dir, metadata):
    """
    Check if workspace settings exist and have test configuration (bonus points).
    
    Returns:
        bool: True if workspace settings have pytest config, False otherwise
    """
    try:
        local_workspace_path = os.path.join(temp_dir, "workspace_settings.json")
        
        try:
            copy_fn(settings_path, local_workspace_path)
        except:
            # Workspace settings are optional
            metadata["workspace_settings_exist"] = False
            return False
        
        if not os.path.exists(local_workspace_path) or os.path.getsize(local_workspace_path) == 0:
            metadata["workspace_settings_exist"] = False
            return False
        
        # Parse workspace settings
        try:
            with open(local_workspace_path, 'r', encoding='utf-8') as f:
                settings = json.load(f)
        except:
            metadata["workspace_settings_exist"] = False
            return False
        
        # Check if workspace has any pytest configuration
        has_pytest_config = (
            settings.get("python.testing.pytestEnabled") is not None or
            "python.testing.pytestArgs" in settings or
            "python.testing.autoTestDiscoverOnSaveEnabled" in settings
        )
        
        metadata["workspace_settings_exist"] = True
        metadata["workspace_has_pytest_config"] = has_pytest_config
        
        logger.info(f"Workspace settings found with pytest config: {has_pytest_config}")
        
        return has_pytest_config
        
    except Exception as e:
        logger.debug(f"Workspace settings check failed (optional): {e}")
        metadata["workspace_settings_exist"] = False
        return False
