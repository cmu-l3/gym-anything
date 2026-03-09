#!/usr/bin/env python3
"""
Verifier for setup_devcontainer_onboarding@1
Checks that a complete devcontainer onboarding setup was created
"""

import sys
import os
import json
import logging
import tempfile
import shutil
from pathlib import Path
from typing import Dict, List, Any, Tuple

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import cleanup_verification_temp

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

WORKSPACE_PATH = "/home/ga/workspace/team_project"


def safe_json_load(filepath: str) -> Tuple[bool, Dict[str, Any], str]:
    """
    Safely load and parse JSON file.
    
    Returns:
        Tuple of (success, parsed_data, error_message)
    """
    try:
        if not os.path.exists(filepath):
            return False, {}, "File not found"
        
        if os.path.getsize(filepath) == 0:
            return False, {}, "File is empty"
        
        with open(filepath, 'r', encoding='utf-8') as f:
            data = json.load(f)
        
        return True, data, ""
    except json.JSONDecodeError as e:
        return False, {}, f"Invalid JSON: {str(e)}"
    except Exception as e:
        return False, {}, f"Error reading file: {str(e)}"


def verify_devcontainer_config(devcontainer_data: Dict[str, Any]) -> Tuple[List[str], List[str]]:
    """
    Verify devcontainer.json configuration.
    
    Returns:
        Tuple of (passed_checks, failed_checks)
    """
    passed = []
    failed = []
    
    # Check 1: Python base image
    has_python = False
    if "image" in devcontainer_data:
        image = devcontainer_data["image"].lower()
        if "python" in image and ("3.11" in image or "3.1" in image):
            has_python = True
            passed.append(f"✅ Python 3.11 base image: {devcontainer_data['image']}")
        elif "python" in image:
            has_python = True
            passed.append(f"✅ Python base image (version may vary): {devcontainer_data['image']}")
    elif "dockerFile" in devcontainer_data or "build" in devcontainer_data:
        has_python = True  # Assume custom Dockerfile has Python
        passed.append("✅ Custom Dockerfile/build configuration present")
    
    if not has_python:
        failed.append("❌ No Python base image found (expected 'image' field with Python)")
    
    # Check 2: PostgreSQL feature
    has_postgres = False
    if "features" in devcontainer_data:
        features = devcontainer_data["features"]
        features_str = json.dumps(features).lower()
        if "postgres" in features_str:
            has_postgres = True
            passed.append("✅ PostgreSQL feature configured")
    
    # Also check in image name as fallback
    if not has_postgres and "image" in devcontainer_data:
        if "postgres" in devcontainer_data["image"].lower():
            has_postgres = True
            passed.append("✅ PostgreSQL in base image")
    
    if not has_postgres:
        # Not critical, just note it
        failed.append("⚠️ PostgreSQL feature not explicitly configured (optional)")
    
    # Check 3: VSCode customizations - extensions
    required_extensions = {
        "ms-python.python": False,
        "ms-python.black-formatter": False,
        "eamodio.gitlens": False,
    }
    has_linter = False
    
    extensions = []
    if "customizations" in devcontainer_data:
        vscode = devcontainer_data.get("customizations", {}).get("vscode", {})
        extensions = vscode.get("extensions", [])
    
    extensions_lower = [ext.lower() for ext in extensions]
    
    for req_ext in required_extensions:
        if req_ext.lower() in extensions_lower:
            required_extensions[req_ext] = True
    
    # Check for any linter
    has_linter = any("lint" in ext.lower() or "pylint" in ext.lower() for ext in extensions)
    
    found_count = sum(required_extensions.values())
    if found_count >= 3 and has_linter:
        passed.append(f"✅ Required extensions configured ({len(extensions)} total)")
    elif found_count >= 2:
        passed.append(f"⚠️ Most required extensions found ({found_count}/3)")
        missing = [k for k, v in required_extensions.items() if not v]
        failed.append(f"❌ Missing extensions: {', '.join(missing)}")
    else:
        failed.append(f"❌ Missing required extensions (found {found_count}/3)")
    
    # Check 4: Settings in customizations
    if "customizations" in devcontainer_data:
        vscode = devcontainer_data.get("customizations", {}).get("vscode", {})
        settings = vscode.get("settings", {})
        
        if settings:
            passed.append(f"✅ Container-specific settings configured")
    
    # Check 5: Post-create command
    if "postCreateCommand" in devcontainer_data:
        cmd = str(devcontainer_data["postCreateCommand"])
        if "pip install" in cmd and "requirements" in cmd:
            passed.append("✅ Post-create command installs dependencies")
        elif "pip install" in cmd:
            passed.append("⚠️ Post-create command runs pip install")
        else:
            failed.append("⚠️ Post-create command exists but may not install requirements")
    else:
        failed.append("❌ No postCreateCommand defined")
    
    return passed, failed


def verify_workspace_settings(settings_data: Dict[str, Any]) -> Tuple[List[str], List[str]]:
    """
    Verify .vscode/settings.json configuration.
    
    Returns:
        Tuple of (passed_checks, failed_checks)
    """
    passed = []
    failed = []
    
    # Check format on save
    if settings_data.get("editor.formatOnSave"):
        passed.append("✅ Format on save enabled")
    else:
        failed.append("❌ Format on save not enabled")
    
    # Check Python linting
    if settings_data.get("python.linting.enabled"):
        passed.append("✅ Python linting enabled")
    else:
        failed.append("❌ Python linting not enabled")
    
    # Check formatter configuration
    formatter = settings_data.get("python.formatting.provider", "").lower()
    if "black" in formatter:
        passed.append("✅ Black formatter configured")
    elif formatter:
        passed.append(f"⚠️ Formatter configured: {formatter}")
    else:
        # Check alternate setting for Black
        default_formatter = settings_data.get("[python]", {}).get("editor.defaultFormatter", "")
        if "black" in default_formatter.lower():
            passed.append("✅ Black formatter configured via [python] scope")
        else:
            failed.append("❌ Black formatter not configured")
    
    return passed, failed


def verify_devcontainer_setup(traj, env_info, task_info):
    """
    Verify the devcontainer onboarding setup task.
    
    Returns:
        Dict with 'passed', 'score', 'feedback'
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='devcontainer_verify_')
    
    all_passed = []
    all_failed = []
    
    try:
        # ===== Check 1: DevContainer Configuration =====
        devcontainer_path = os.path.join(temp_dir, "devcontainer.json")
        try:
            copy_from_env(
                f"{WORKSPACE_PATH}/.devcontainer/devcontainer.json",
                devcontainer_path
            )
        except Exception as e:
            all_failed.append(f"❌ .devcontainer/devcontainer.json not found: {e}")
            devcontainer_path = None
        
        if devcontainer_path and os.path.exists(devcontainer_path):
            success, devcontainer_data, error = safe_json_load(devcontainer_path)
            if success:
                passed, failed = verify_devcontainer_config(devcontainer_data)
                all_passed.extend(passed)
                all_failed.extend(failed)
            else:
                all_failed.append(f"❌ devcontainer.json invalid: {error}")
        
        # ===== Check 2: Workspace Settings =====
        settings_path = os.path.join(temp_dir, "settings.json")
        try:
            copy_from_env(
                f"{WORKSPACE_PATH}/.vscode/settings.json",
                settings_path
            )
        except Exception as e:
            all_failed.append(f"❌ .vscode/settings.json not found: {e}")
            settings_path = None
        
        if settings_path and os.path.exists(settings_path):
            success, settings_data, error = safe_json_load(settings_path)
            if success:
                passed, failed = verify_workspace_settings(settings_data)
                all_passed.extend(passed)
                all_failed.extend(failed)
            else:
                all_failed.append(f"❌ settings.json invalid: {error}")
        
        # ===== Check 3: Extension Recommendations =====
        extensions_path = os.path.join(temp_dir, "extensions.json")
        try:
            copy_from_env(
                f"{WORKSPACE_PATH}/.vscode/extensions.json",
                extensions_path
            )
        except Exception as e:
            all_failed.append(f"❌ .vscode/extensions.json not found: {e}")
            extensions_path = None
        
        if extensions_path and os.path.exists(extensions_path):
            success, ext_data, error = safe_json_load(extensions_path)
            if success:
                recommendations = ext_data.get("recommendations", [])
                if len(recommendations) >= 3:
                    all_passed.append(f"✅ Extension recommendations: {len(recommendations)} extensions")
                elif len(recommendations) > 0:
                    all_passed.append(f"⚠️ Some recommendations: {len(recommendations)} extensions")
                else:
                    all_failed.append("❌ No extension recommendations")
            else:
                all_failed.append(f"❌ extensions.json invalid: {error}")
        
        # ===== Check 4: Tasks Configuration =====
        tasks_path = os.path.join(temp_dir, "tasks.json")
        try:
            copy_from_env(
                f"{WORKSPACE_PATH}/.vscode/tasks.json",
                tasks_path
            )
        except Exception as e:
            all_failed.append(f"❌ .vscode/tasks.json not found: {e}")
            tasks_path = None
        
        if tasks_path and os.path.exists(tasks_path):
            success, tasks_data, error = safe_json_load(tasks_path)
            if success:
                tasks = tasks_data.get("tasks", [])
                if len(tasks) >= 2:
                    all_passed.append(f"✅ Tasks configured: {len(tasks)} tasks")
                    
                    # Check for test and dev tasks
                    labels = [t.get("label", "").lower() for t in tasks]
                    has_test = any("test" in label or "pytest" in label for label in labels)
                    has_dev = any("format" in label or "dev" in label or "server" in label for label in labels)
                    
                    if has_test:
                        all_passed.append("✅ Test task defined")
                    if has_dev:
                        all_passed.append("✅ Dev/format task defined")
                    
                    if not has_test and not has_dev:
                        all_failed.append("⚠️ Tasks may not include test/dev tasks")
                elif len(tasks) > 0:
                    all_passed.append(f"⚠️ Some tasks defined: {len(tasks)} task(s)")
                else:
                    all_failed.append("❌ No tasks defined")
            else:
                all_failed.append(f"❌ tasks.json invalid: {error}")
        
        # ===== Check 5: Quickstart Guide =====
        quickstart_path = os.path.join(temp_dir, "QUICKSTART.md")
        try:
            copy_from_env(
                f"{WORKSPACE_PATH}/QUICKSTART.md",
                quickstart_path
            )
        except Exception as e:
            all_failed.append(f"❌ QUICKSTART.md not found: {e}")
            quickstart_path = None
        
        if quickstart_path and os.path.exists(quickstart_path):
            with open(quickstart_path, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
            
            has_heading = any(line.strip().startswith('#') for line in content.split('\n'))
            has_content = len(content.strip()) >= 100
            keywords = ["test", "server", "format", "run", "start"]
            has_keywords = any(kw in content.lower() for kw in keywords)
            
            if has_heading and has_content and has_keywords:
                all_passed.append(f"✅ QUICKSTART.md created ({len(content)} chars)")
            else:
                issues = []
                if not has_heading:
                    issues.append("no heading")
                if not has_content:
                    issues.append("too short")
                if not has_keywords:
                    issues.append("missing key info")
                all_failed.append(f"⚠️ QUICKSTART.md incomplete: {', '.join(issues)}")
        
        # ===== Calculate Final Score =====
        total_checks = len(all_passed) + len(all_failed)
        if total_checks == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ No configuration files found"
            }
        
        success_rate = len(all_passed) / total_checks
        score = int(success_rate * 100)
        
        # Require 80% success rate (lenient for variation in implementation)
        passed = score >= 80 and len(all_failed) <= 3
        
        # Build feedback
        feedback_lines = [
            f"\n{'✅ SUCCESS' if passed else '❌ INCOMPLETE'}: DevContainer Onboarding Setup",
            f"\nChecks Passed: {len(all_passed)}/{total_checks} ({score}%)\n"
        ]
        
        if all_passed:
            feedback_lines.append("\n".join(all_passed))
        
        if all_failed:
            feedback_lines.append("\n\n⚠️ Issues:")
            feedback_lines.append("\n".join(all_failed))
        
        feedback_lines.append(f"\n\n📊 Final Score: {score}%")
        
        feedback = "\n".join(feedback_lines)
        
        logger.info(feedback)
        
        return {
            "passed": passed,
            "score": score,
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
        cleanup_verification_temp(temp_dir)
