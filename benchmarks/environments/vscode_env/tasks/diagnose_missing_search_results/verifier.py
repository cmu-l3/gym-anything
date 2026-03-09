#!/usr/bin/env python3
"""
Verifier for Diagnose Missing Search Results task
Checks if VSCode search configuration was correctly modified to include the excluded JSON file
"""

import sys
import os
import json
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import parse_vscode_settings, cleanup_verification_temp

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_search_configuration(traj, env_info, task_info):
    """
    Verify that the user correctly diagnosed and fixed the search exclusion issue.
    
    Checks:
    1. Workspace settings file exists and is valid JSON
    2. The blanket "**/*.json": true exclusion is removed from search.exclude
    3. node_modules remains excluded (good practice)
    4. Settings are properly formatted
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='vscode_verify_search_')

    try:
        # Copy workspace settings
        workspace_settings_path = os.path.join(temp_dir, "workspace_settings.json")
        
        try:
            copy_from_env(
                "/tmp/task_results/workspace_settings.json",
                workspace_settings_path
            )
        except Exception as e:
            logger.error(f"Failed to copy workspace settings: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Could not access workspace settings: {str(e)}"
            }

        if not os.path.exists(workspace_settings_path):
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Workspace settings file not found at .vscode/settings.json"
            }

        # Parse settings
        try:
            with open(workspace_settings_path, 'r') as f:
                workspace_settings = json.load(f)
        except json.JSONDecodeError as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Invalid JSON in workspace settings: {str(e)}"
            }

        criteria_passed = 0
        feedback_parts = []
        max_criteria = 4

        # Criterion 1: Settings file is valid JSON (already verified above)
        criteria_passed += 1
        feedback_parts.append("✅ Settings file is valid JSON")

        # Criterion 2: Check if the blanket JSON exclusion was removed or modified
        search_exclude = workspace_settings.get("search.exclude", {})
        
        blanket_json_exclude = search_exclude.get("**/*.json")
        
        if blanket_json_exclude is True:
            feedback_parts.append("❌ The problematic '**/*.json': true exclusion is still active in search.exclude")
        elif blanket_json_exclude is None:
            # Good - the exclusion was removed
            criteria_passed += 1
            feedback_parts.append("✅ Removed blanket JSON file exclusion from search")
        else:
            # It was set to false or something else
            criteria_passed += 1
            feedback_parts.append(f"✅ Modified JSON exclusion (set to: {blanket_json_exclude})")

        # Criterion 3: Verify node_modules is still excluded (performance best practice)
        node_modules_excluded = (
            search_exclude.get("**/node_modules") == True or 
            search_exclude.get("**/node_modules/**") == True or
            "**/node_modules" in str(search_exclude)
        )
        
        if node_modules_excluded:
            criteria_passed += 1
            feedback_parts.append("✅ node_modules still excluded (good practice)")
        else:
            feedback_parts.append("⚠️  Warning: node_modules not excluded (may impact performance)")

        # Criterion 4: Verify a more specific exclusion pattern if they chose that approach
        # This is a bonus - they could have removed the exclusion OR made it more specific
        # Check if they added something like "**/node_modules/**/*.json" or excluded dist/*.json
        has_specific_exclusions = False
        for pattern in search_exclude.keys():
            if pattern not in ["**/*.json", "**/node_modules", "**/node_modules/**", "**/dist"]:
                if ".json" in pattern:
                    has_specific_exclusions = True
                    break
        
        if has_specific_exclusions:
            criteria_passed += 1
            feedback_parts.append("✅ Used specific exclusion patterns (advanced approach)")
        elif blanket_json_exclude is None:
            # They just removed it - also acceptable
            criteria_passed += 1
            feedback_parts.append("✅ Simply removed problematic exclusion (effective approach)")

        # Calculate score
        score = int((criteria_passed / max_criteria) * 100)
        passed = score >= 75

        feedback = " | ".join(feedback_parts)

        # Add helpful context
        if not passed:
            feedback += f" | Criteria passed: {criteria_passed}/{max_criteria}"
            if blanket_json_exclude is True:
                feedback += " | Hint: Remove or modify the '**/*.json' pattern in search.exclude"

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
