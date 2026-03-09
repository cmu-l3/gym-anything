#!/usr/bin/env python3
"""
Verifier for migrate_external_repo task.
Checks if the repository was imported, standardized to 'main', and set as default.
"""

import json
import logging
import os
import tempfile
from gym_anything.vlm import get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_migrate_external_repo(traj, env_info, task_info):
    """
    Verify the repository migration and standardization task.
    
    Criteria:
    1. Repository 'LegacyPrototype' exists (30 pts)
    2. Import was successful (files exist) (30 pts)
    3. Branch 'main' exists (20 pts)
    4. Default branch is set to 'refs/heads/main' (20 pts)
    
    Fallback: VLM check if API check fails or as supporting evidence.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Retrieve JSON Result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Using the Windows path defined in export_result.ps1
        copy_from_env("C:/Users/Docker/task_results/migrate_external_repo_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to retrieve result file: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed to retrieve verification data from environment. Did the task complete?"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # 2. Evaluate Programmatic Criteria
    
    # Criterion 1: Repo Existence (30 pts)
    if result.get('repo_exists', False):
        score += 30
        feedback_parts.append("Repository 'LegacyPrototype' created.")
    else:
        feedback_parts.append("Repository 'LegacyPrototype' NOT found.")
        # If repo doesn't exist, we can't check anything else really
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Import Success (30 pts)
    if result.get('import_successful', False):
        score += 30
        feedback_parts.append("Import successful (content found).")
    else:
        feedback_parts.append("Repository is empty or import failed.")

    # Criterion 3: Main Branch Exists (20 pts)
    if result.get('main_branch_exists', False):
        score += 20
        feedback_parts.append("Branch 'main' created.")
    else:
        feedback_parts.append("Branch 'main' NOT found.")

    # Criterion 4: Default Branch is Main (20 pts)
    actual_default = result.get('actual_default_branch', 'unknown')
    if result.get('default_branch_is_main', False):
        score += 20
        feedback_parts.append("Default branch correctly set to 'main'.")
    else:
        feedback_parts.append(f"Default branch is '{actual_default}' (expected 'refs/heads/main').")

    # 3. Optional VLM Verification (if score is borderline or for robust logging)
    # We use VLM to verify the visual state if the programmatic check for default branch fails
    # but the branch exists (maybe agent missed the settings checkbox but created the branch).
    if score >= 80 and not result.get('default_branch_is_main', False):
        final_screenshot = get_final_screenshot(traj)
        if final_screenshot:
            vlm_response = query_vlm(
                image=final_screenshot,
                prompt="Look at this Azure DevOps screen. Is the 'main' branch listed with a 'Default' badge or label next to it?"
            )
            if vlm_response.get('parsed', {}).get('result', False) is True:
                # Small partial credit if UI shows it but API didn't catch it (rare sync issue)
                score += 5
                feedback_parts.append("(VLM detected visual default tag, giving partial credit)")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }