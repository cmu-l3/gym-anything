#!/usr/bin/env python3
"""
Verifier for Configure Offline Mode task
"""

import sys
import os
import json
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import parse_vscode_settings

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_value(value):
    """Normalize setting values for comparison (handle string vs boolean)."""
    if isinstance(value, str):
        value_lower = value.lower()
        if value_lower == 'true':
            return True
        elif value_lower == 'false':
            return False
        return value_lower
    return value


def verify_offline_configuration(traj, env_info, task_info):
    """
    Verify that VSCode is configured for offline work.
    
    Checks 5 critical settings:
    1. update.mode: "none" or "manual"
    2. telemetry.telemetryLevel: "off"
    3. extensions.autoUpdate: false
    4. git.autofetch: false
    5. files.autoSave: enabled ("afterDelay", "onFocusChange", "onWindowChange")
    
    Bonus: files.autoSaveDelay <= 1000ms
    
    Returns:
        Dict with passed (bool), score (0-100), and feedback (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='vscode_offline_verify_')
    
    try:
        # Copy settings files exported by export_result.sh
        user_settings_local = os.path.join(temp_dir, "user_settings.json")
        workspace_settings_local = os.path.join(temp_dir, "workspace_settings.json")
        
        try:
            copy_from_env("/tmp/user_settings.json", user_settings_local)
        except Exception as e:
            logger.warning(f"Failed to copy user settings: {e}")
            # Create empty settings file
            with open(user_settings_local, 'w') as f:
                json.dump({}, f)
        
        try:
            copy_from_env("/tmp/workspace_settings.json", workspace_settings_local)
        except Exception as e:
            logger.warning(f"Failed to copy workspace settings: {e}")
            # Create empty settings file
            with open(workspace_settings_local, 'w') as f:
                json.dump({}, f)
        
        # Parse both settings files
        user_settings = {}
        workspace_settings = {}
        
        if os.path.exists(user_settings_local) and os.path.getsize(user_settings_local) > 0:
            try:
                user_settings = parse_vscode_settings(user_settings_local)
                logger.info(f"Loaded user settings: {list(user_settings.keys())}")
            except Exception as e:
                logger.warning(f"Failed to parse user settings: {e}")
        
        if os.path.exists(workspace_settings_local) and os.path.getsize(workspace_settings_local) > 0:
            try:
                workspace_settings = parse_vscode_settings(workspace_settings_local)
                logger.info(f"Loaded workspace settings: {list(workspace_settings.keys())}")
            except Exception as e:
                logger.warning(f"Failed to parse workspace settings: {e}")
        
        # Combine settings (workspace overrides user)
        all_settings = {**user_settings, **workspace_settings}
        
        if not all_settings:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ No settings.json found in User or Workspace directories"
            }
        
        # Define critical offline configurations
        checks = [
            {
                "key": "update.mode",
                "expected": ["none", "manual"],
                "actual": all_settings.get("update.mode"),
                "description": "Update mode disabled",
                "weight": 1.0
            },
            {
                "key": "telemetry.telemetryLevel",
                "expected": ["off"],
                "actual": all_settings.get("telemetry.telemetryLevel"),
                "description": "Telemetry disabled",
                "weight": 1.0
            },
            {
                "key": "extensions.autoUpdate",
                "expected": [False, "false"],
                "actual": all_settings.get("extensions.autoUpdate"),
                "description": "Extension auto-update disabled",
                "weight": 1.0
            },
            {
                "key": "git.autofetch",
                "expected": [False, "false"],
                "actual": all_settings.get("git.autofetch"),
                "description": "Git auto-fetch disabled",
                "weight": 1.0
            },
            {
                "key": "files.autoSave",
                "expected": ["afterDelay", "afterdelay", "onFocusChange", "onfocuschange", "onWindowChange", "onwindowchange"],
                "actual": all_settings.get("files.autoSave"),
                "description": "Auto-save enabled",
                "weight": 1.0
            }
        ]
        
        # Validate each setting
        passed_checks = 0
        total_checks = len(checks)
        feedback_parts = []
        
        for check in checks:
            actual = check["actual"]
            expected = check["expected"]
            
            # Normalize values for comparison
            actual_normalized = normalize_value(actual)
            expected_normalized = [normalize_value(e) for e in expected]
            
            if actual_normalized in expected_normalized:
                passed_checks += 1
                feedback_parts.append(f"✅ {check['description']}: {actual}")
            else:
                feedback_parts.append(
                    f"❌ {check['description']}: expected {expected}, got {actual}"
                )
        
        # Check auto-save delay for aggressiveness (bonus points)
        autosave_delay = all_settings.get("files.autoSaveDelay", 1000)
        bonus_points = 0.0
        
        try:
            delay_value = int(autosave_delay)
            if delay_value <= 1000:
                feedback_parts.append(f"✅ Aggressive auto-save delay: {delay_value}ms")
                bonus_points = 0.15
            else:
                feedback_parts.append(
                    f"⚠️ Auto-save delay could be more aggressive: {delay_value}ms (recommend ≤1000ms)"
                )
        except (ValueError, TypeError):
            feedback_parts.append(
                f"⚠️ Auto-save delay not configured or invalid: {autosave_delay}"
            )
        
        # Calculate score
        base_score = (passed_checks / total_checks) * 0.85  # 85% for base checks
        total_score = min(1.0, base_score + bonus_points)
        
        # Pass threshold: 70% (at least 4 out of 5 settings correct)
        success = total_score >= 0.70
        
        # Generate detailed feedback
        feedback = "\n".join(feedback_parts)
        feedback += f"\n\n📊 Passed {passed_checks}/{total_checks} critical checks"
        feedback += f"\n🎯 Final Score: {total_score * 100:.1f}%"
        
        if success:
            feedback += "\n✅ VSCode successfully configured for offline work!"
        else:
            feedback += f"\n❌ Need at least 70% to pass (currently {total_score * 100:.1f}%)"
        
        return {
            "passed": success,
            "score": int(total_score * 100),
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
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
