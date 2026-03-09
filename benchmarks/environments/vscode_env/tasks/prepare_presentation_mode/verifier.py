#!/usr/bin/env python3
"""
Verifier for Prepare Presentation Mode task
Checks if VSCode has been configured for presentation with readable fonts and clean UI
"""

import sys
import os
import logging
import tempfile
import json
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import parse_vscode_settings, cleanup_verification_temp

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_presentation_mode(traj, env_info, task_info):
    """
    Verify that VSCode has been configured for presentation mode.
    
    Checks 6 criteria:
    1. Editor font size >= 18px
    2. Terminal font size >= 16px
    3. Minimap disabled
    4. Breadcrumbs disabled
    5. Activity bar hidden
    6. (Bonus) Status bar handled
    
    Pass threshold: 67% (4/6 criteria)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='vscode_verify_presentation_')
    
    try:
        # Copy settings files exported by export_result.sh
        user_settings_path = "/tmp/user_settings.json"
        workspace_settings_path = "/tmp/workspace_settings.json"
        
        local_user_settings = os.path.join(temp_dir, "user_settings.json")
        local_workspace_settings = os.path.join(temp_dir, "workspace_settings.json")
        
        user_settings = {}
        workspace_settings = {}
        
        # Copy user settings
        try:
            copy_from_env(user_settings_path, local_user_settings)
            if os.path.exists(local_user_settings) and os.path.getsize(local_user_settings) > 0:
                user_settings = parse_vscode_settings(local_user_settings)
                logger.info(f"User settings loaded: {len(user_settings)} keys")
        except Exception as e:
            logger.warning(f"Could not load user settings: {e}")
        
        # Copy workspace settings
        try:
            copy_from_env(workspace_settings_path, local_workspace_settings)
            if os.path.exists(local_workspace_settings) and os.path.getsize(local_workspace_settings) > 0:
                workspace_settings = parse_vscode_settings(local_workspace_settings)
                logger.info(f"Workspace settings loaded: {len(workspace_settings)} keys")
        except Exception as e:
            logger.warning(f"Could not load workspace settings: {e}")
        
        # Merge settings (workspace overrides user)
        settings = {**user_settings, **workspace_settings}
        
        if not settings:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ No settings found. Settings may not have been saved."
            }
        
        # Track criteria
        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        
        # Criterion 1: Editor font size >= 18
        editor_font = settings.get('editor.fontSize', 11)  # Default is typically 12-14
        if isinstance(editor_font, (int, float)) and editor_font >= 18:
            criteria_passed += 1
            feedback_parts.append(f"✅ Editor font: {editor_font}px (readable)")
        else:
            feedback_parts.append(f"❌ Editor font: {editor_font}px (need ≥18px)")
        
        # Criterion 2: Terminal font size >= 16
        terminal_font = settings.get('terminal.integrated.fontSize', 12)
        if isinstance(terminal_font, (int, float)) and terminal_font >= 16:
            criteria_passed += 1
            feedback_parts.append(f"✅ Terminal font: {terminal_font}px (readable)")
        else:
            feedback_parts.append(f"❌ Terminal font: {terminal_font}px (need ≥16px)")
        
        # Criterion 3: Minimap disabled
        minimap_enabled = settings.get('editor.minimap.enabled', True)
        if minimap_enabled is False or (isinstance(minimap_enabled, str) and minimap_enabled.lower() == 'false'):
            criteria_passed += 1
            feedback_parts.append("✅ Minimap disabled (clean)")
        else:
            feedback_parts.append("❌ Minimap still enabled (distracting)")
        
        # Criterion 4: Breadcrumbs disabled
        breadcrumbs = settings.get('breadcrumbs.enabled', True)
        if breadcrumbs is False or (isinstance(breadcrumbs, str) and breadcrumbs.lower() == 'false'):
            criteria_passed += 1
            feedback_parts.append("✅ Breadcrumbs disabled (more space)")
        else:
            feedback_parts.append("❌ Breadcrumbs still enabled")
        
        # Criterion 5: Activity bar hidden
        activity_bar = settings.get('workbench.activityBar.visible', True)
        if activity_bar is False or (isinstance(activity_bar, str) and activity_bar.lower() == 'false'):
            criteria_passed += 1
            feedback_parts.append("✅ Activity bar hidden (cleaner)")
        else:
            feedback_parts.append("❌ Activity bar still visible")
        
        # Criterion 6: Bonus - check if other presentation-friendly settings exist
        # This is a softer criterion
        bonus_points = 0
        
        # Check if status bar was hidden (optional but good for presentations)
        status_bar = settings.get('workbench.statusBar.visible', True)
        if status_bar is False:
            bonus_points += 0.5
            feedback_parts.append("✅ BONUS: Status bar hidden (extra clean)")
        
        # Check if git decorations were minimized
        git_decorations = settings.get('scm.diffDecorations', 'all')
        if git_decorations in ['none', 'gutter']:
            bonus_points += 0.5
            feedback_parts.append("✅ BONUS: Git decorations minimized")
        
        # Add bonus as partial criterion
        if bonus_points >= 0.5:
            criteria_passed += bonus_points
        
        # Calculate score
        score = (criteria_passed / total_criteria) * 100
        score = min(100, score)  # Cap at 100
        passed = score >= 67  # Need 4/6 criteria (67%)
        
        # Build final feedback
        feedback = " | ".join(feedback_parts)
        summary = f"Score: {score:.0f}% ({criteria_passed:.1f}/{total_criteria} criteria)"
        
        logger.info(f"Verification complete: {summary}")
        logger.info(f"Settings checked: {list(settings.keys())}")
        
        return {
            "passed": passed,
            "score": round(score, 1),
            "feedback": f"{summary} | {feedback}"
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        cleanup_verification_temp(temp_dir)
