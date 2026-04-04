#!/usr/bin/env python3
"""
Verifier for Screen Share Preparation task

Verifies that VSCode was configured for professional screen sharing by checking:
1. Editor font size (18-22px)
2. Terminal font size (16-20px)
3. Zoom level (>=130%)
4. Theme changed to light/presentation theme
5. Minimap disabled
6. Work files still exist in workspace
7. Settings file was modified (not default)
"""

import sys
import os
import logging
import tempfile
import json

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import parse_vscode_settings

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_screen_share_ready(traj, env_info, task_info):
    """
    Verify that VSCode is prepared for screen sharing.
    
    Checks 7 criteria, needs 5+ to pass (71%):
    1. Editor font size: 18-22px
    2. Terminal font size: 16-20px  
    3. Zoom level: >= 130% (1.3)
    4. Theme: Light or High Contrast
    5. Minimap disabled
    6. Work files exist
    7. Settings were actually changed
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='vscode_screenshare_verify_')
    
    try:
        # Copy settings.json exported by export_result.sh
        settings_remote = "/tmp/vscode_settings.json"
        settings_local = os.path.join(temp_dir, "settings.json")
        
        try:
            copy_from_env(settings_remote, settings_local)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to copy settings.json: {str(e)}"
            }
        
        if not os.path.exists(settings_local) or os.path.getsize(settings_local) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Settings file not found or empty"
            }
        
        # Parse settings
        settings = parse_vscode_settings(settings_local)
        if not settings:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to parse settings.json"
            }
        
        # Copy workspace file list
        workspace_files_remote = "/tmp/workspace_files.txt"
        workspace_files_local = os.path.join(temp_dir, "workspace_files.txt")
        workspace_files = []
        
        try:
            copy_from_env(workspace_files_remote, workspace_files_local)
            if os.path.exists(workspace_files_local):
                with open(workspace_files_local, 'r') as f:
                    workspace_files = [line.strip() for line in f.readlines()]
        except Exception as e:
            logger.warning(f"Could not copy workspace files list: {e}")
        
        # Verification criteria
        criteria = {}
        feedback_parts = []
        
        # Criterion 1: Editor font size (18-22px)
        editor_font = settings.get('editor.fontSize', 11)
        if isinstance(editor_font, (int, float)) and 18 <= editor_font <= 22:
            criteria['editor_font'] = True
            feedback_parts.append(f"✅ Editor font: {editor_font}px (readable)")
        else:
            criteria['editor_font'] = False
            feedback_parts.append(f"❌ Editor font: {editor_font}px (need 18-22px)")
        
        # Criterion 2: Terminal font size (16-20px)
        terminal_font = settings.get('terminal.integrated.fontSize', 12)
        if isinstance(terminal_font, (int, float)) and 16 <= terminal_font <= 20:
            criteria['terminal_font'] = True
            feedback_parts.append(f"✅ Terminal font: {terminal_font}px (readable)")
        else:
            criteria['terminal_font'] = False
            feedback_parts.append(f"❌ Terminal font: {terminal_font}px (need 16-20px)")
        
        # Criterion 3: Zoom level (>= 1.3 = 130%)
        zoom_level = settings.get('window.zoomLevel', 0)
        if isinstance(zoom_level, (int, float)) and zoom_level >= 1.3:
            criteria['zoom_level'] = True
            feedback_parts.append(f"✅ Zoom: {zoom_level*100:.0f}% (good for streaming)")
        else:
            criteria['zoom_level'] = False
            zoom_pct = zoom_level * 100 if isinstance(zoom_level, (int, float)) else 100
            feedback_parts.append(f"❌ Zoom: {zoom_pct:.0f}% (need ≥130%)")
        
        # Criterion 4: Theme (light or high-contrast)
        theme = settings.get('workbench.colorTheme', 'Default Dark+')
        presentation_keywords = ['light', 'high contrast', 'solarized light', 'quiet light']
        is_presentation_theme = any(keyword in theme.lower() for keyword in presentation_keywords)
        
        if is_presentation_theme:
            criteria['presentation_theme'] = True
            feedback_parts.append(f"✅ Theme: '{theme}' (presentation-appropriate)")
        else:
            criteria['presentation_theme'] = False
            feedback_parts.append(f"❌ Theme: '{theme}' (need light/high-contrast theme)")
        
        # Criterion 5: Minimap disabled
        minimap_enabled = settings.get('editor.minimap.enabled', True)
        if minimap_enabled == False or minimap_enabled == 'false':
            criteria['minimap_disabled'] = True
            feedback_parts.append("✅ Minimap: disabled (more screen space)")
        else:
            criteria['minimap_disabled'] = False
            feedback_parts.append("❌ Minimap: still enabled (wastes space)")
        
        # Criterion 6: Work files still exist
        work_files = ['presentation_demo.py', 'client_api.js', 'README.md']
        work_files_present = sum(1 for wf in work_files if wf in workspace_files)
        
        if work_files_present >= 2:
            criteria['work_files_exist'] = True
            feedback_parts.append(f"✅ Work files present: {work_files_present}/3")
        else:
            criteria['work_files_exist'] = False
            feedback_parts.append(f"❌ Work files missing: only {work_files_present}/3 found")
        
        # Criterion 7: Settings were actually changed (not all defaults)
        # At least 3 of the key settings should have non-default values
        changes_made = 0
        if editor_font != 11: changes_made += 1
        if terminal_font != 12: changes_made += 1
        if zoom_level != 0: changes_made += 1
        if 'dark' not in theme.lower(): changes_made += 1
        if minimap_enabled == False: changes_made += 1
        
        if changes_made >= 3:
            criteria['settings_modified'] = True
            feedback_parts.append(f"✅ Settings modified ({changes_made} changes detected)")
        else:
            criteria['settings_modified'] = False
            feedback_parts.append(f"❌ Minimal changes ({changes_made}/5 settings modified)")
        
        # Calculate score
        criteria_met = sum(criteria.values())
        total_criteria = len(criteria)
        score = int((criteria_met / total_criteria) * 100)
        
        # Pass threshold: 71% (5 out of 7 criteria)
        passed = criteria_met >= 5
        
        feedback = " | ".join(feedback_parts)
        
        # Add summary
        summary = f"Met {criteria_met}/{total_criteria} criteria"
        if passed:
            summary += " ✅ PASS - VSCode is presentation-ready!"
        else:
            summary += " ❌ FAIL - More configuration needed"
        
        feedback = summary + " | " + feedback
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "criteria_met": criteria
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        # Cleanup temp directory
        if os.path.exists(temp_dir):
            import shutil
            shutil.rmtree(temp_dir, ignore_errors=True)
