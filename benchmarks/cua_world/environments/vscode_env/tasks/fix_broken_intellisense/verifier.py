#!/usr/bin/env python3
"""
Verifier for Fix Broken IntelliSense task
"""

import sys
import os
import json
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import (
    parse_vscode_settings,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_intellisense_fixed(traj, env_info, task_info):
    """
    Verify that Python IntelliSense has been fixed by configuring correct interpreter.

    Checks:
    1. Workspace settings contain correct interpreter path (pointing to venv) - 40 points
    2. Pylance extension is installed - 15 points
    3. Python extension is installed - 15 points
    4. Interpreter path actually points to venv directory - 20 points
    5. Settings file is valid JSON and properly formatted - 10 points

    Pass threshold: 70% (requires correct interpreter + extensions present)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='vscode_verify_intellisense_')

    try:
        # Copy exported files from container
        workspace_settings_local = os.path.join(temp_dir, "workspace_settings.json")
        user_settings_local = os.path.join(temp_dir, "user_settings.json")
        extensions_list_local = os.path.join(temp_dir, "extensions_list.txt")
        extensions_dir_local = os.path.join(temp_dir, "extensions_dir.txt")
        venv_path_local = os.path.join(temp_dir, "venv_interpreter_path.txt")

        try:
            copy_from_env("/tmp/workspace_settings.json", workspace_settings_local)
            copy_from_env("/tmp/user_settings.json", user_settings_local)
            copy_from_env("/tmp/extensions_list.txt", extensions_list_local)
            copy_from_env("/tmp/extensions_dir.txt", extensions_dir_local)
            copy_from_env("/tmp/venv_interpreter_path.txt", venv_path_local)
        except Exception as e:
            logger.error(f"Failed to copy verification files: {e}")
            return {"passed": False, "score": 0, "feedback": f"Failed to copy verification files: {str(e)}"}

        score = 0
        max_score = 100
        feedback_parts = []

        # Parse workspace settings
        workspace_settings = {}
        if os.path.exists(workspace_settings_local) and os.path.getsize(workspace_settings_local) > 2:
            try:
                workspace_settings = parse_vscode_settings(workspace_settings_local)
            except Exception as e:
                logger.warning(f"Failed to parse workspace settings: {e}")

        # Parse user settings (fallback if workspace doesn't have interpreter setting)
        user_settings = {}
        if os.path.exists(user_settings_local) and os.path.getsize(user_settings_local) > 2:
            try:
                user_settings = parse_vscode_settings(user_settings_local)
            except Exception as e:
                logger.warning(f"Failed to parse user settings: {e}")

        # Get expected venv paths
        expected_venv_paths = []
        if os.path.exists(venv_path_local):
            with open(venv_path_local, 'r') as f:
                for line in f:
                    path = line.strip()
                    if path and path != "venv interpreter not found":
                        expected_venv_paths.append(path)

        # Criterion 1 & 4: Check if correct interpreter is configured (60 points total)
        interpreter_path = workspace_settings.get('python.defaultInterpreterPath') or \
                          workspace_settings.get('python.pythonPath') or \
                          user_settings.get('python.defaultInterpreterPath') or \
                          user_settings.get('python.pythonPath')

        interpreter_correct = False
        if interpreter_path:
            # Check if interpreter path contains 'venv' and points to python executable
            path_lower = interpreter_path.lower()
            
            # Check if path contains venv indicators
            has_venv_indicator = any(indicator in path_lower for indicator in ['venv', 'ml_project/venv', '.venv'])
            
            # Check if path points to python executable
            is_python_executable = path_lower.endswith('python') or path_lower.endswith('python3') or 'python' in path_lower
            
            # Check if NOT pointing to wrong interpreter
            is_not_global = '/usr/bin/python' not in interpreter_path
            
            if has_venv_indicator and is_python_executable and is_not_global:
                score += 40  # Interpreter path configured correctly
                feedback_parts.append(f"✅ Correct interpreter configured: {interpreter_path}")
                interpreter_correct = True
                
                # Additional points if path matches expected venv paths
                if any(expected_path in interpreter_path or interpreter_path in expected_path 
                       for expected_path in expected_venv_paths):
                    score += 20  # Path matches expected venv location
                    feedback_parts.append("✅ Interpreter path matches venv location")
                elif 'venv' in path_lower:
                    score += 15  # Path contains venv but might not be exact match
                    feedback_parts.append("✅ Interpreter path points to venv")
                else:
                    score += 10  # Has venv indicator but unclear if correct
                    feedback_parts.append("⚠️ Interpreter has venv indicator but path unclear")
            else:
                if not is_not_global:
                    feedback_parts.append(f"❌ Still using global Python: {interpreter_path}")
                elif not has_venv_indicator:
                    feedback_parts.append(f"❌ Interpreter doesn't point to venv: {interpreter_path}")
                else:
                    feedback_parts.append(f"❌ Interpreter path invalid: {interpreter_path}")
        else:
            feedback_parts.append("❌ No interpreter path configured in settings")

        # Criterion 2: Pylance extension installed (15 points)
        pylance_installed = False
        if os.path.exists(extensions_list_local):
            with open(extensions_list_local, 'r') as f:
                extensions_content = f.read().lower()
                if 'pylance' in extensions_content or 'ms-python.vscode-pylance' in extensions_content:
                    score += 15
                    feedback_parts.append("✅ Pylance extension installed")
                    pylance_installed = True

        if not pylance_installed and os.path.exists(extensions_dir_local):
            with open(extensions_dir_local, 'r') as f:
                dir_content = f.read().lower()
                if 'pylance' in dir_content:
                    score += 15
                    feedback_parts.append("✅ Pylance extension found in extensions directory")
                    pylance_installed = True

        if not pylance_installed:
            feedback_parts.append("❌ Pylance extension not found")

        # Criterion 3: Python extension installed (15 points)
        python_installed = False
        if os.path.exists(extensions_list_local):
            with open(extensions_list_local, 'r') as f:
                extensions_content = f.read().lower()
                if 'ms-python.python' in extensions_content or ('python' in extensions_content and 'ms-python' in extensions_content):
                    score += 15
                    feedback_parts.append("✅ Python extension installed")
                    python_installed = True

        if not python_installed and os.path.exists(extensions_dir_local):
            with open(extensions_dir_local, 'r') as f:
                dir_content = f.read().lower()
                if 'ms-python.python' in dir_content or 'python' in dir_content:
                    score += 15
                    feedback_parts.append("✅ Python extension found in extensions directory")
                    python_installed = True

        if not python_installed:
            feedback_parts.append("❌ Python extension not found")

        # Criterion 5: Settings file valid and properly formatted (10 points)
        if workspace_settings and isinstance(workspace_settings, dict):
            score += 10
            feedback_parts.append("✅ Workspace settings file valid")
        else:
            feedback_parts.append("⚠️ Workspace settings file empty or invalid")

        # Calculate final score
        score_percentage = min(100, score)  # Cap at 100
        passed = score_percentage >= 70

        # Generate summary feedback
        if passed:
            summary = f"✅ PASS: IntelliSense fixed! Score: {score_percentage}%"
        else:
            summary = f"❌ FAIL: IntelliSense still broken. Score: {score_percentage}%"

        feedback = summary + " | " + " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score_percentage,
            "feedback": feedback,
            "details": {
                "interpreter_configured": interpreter_correct,
                "pylance_installed": pylance_installed,
                "python_installed": python_installed,
                "interpreter_path": interpreter_path if interpreter_path else "Not configured"
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
        cleanup_verification_temp(temp_dir)
