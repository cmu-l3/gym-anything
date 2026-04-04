#!/usr/bin/env python3
"""
Verifier for prepare_production_release task.

Criteria:
1. Branch 'release/v2.1' must exist (20 pts)
2. package.json on release branch must have version "2.1.0" (20 pts)
3. app-config.json on release branch must have environment "production" (20 pts)
4. Active Pull Request from release/v2.1 to main must exist (30 pts)
5. PR Title must contain "Release v2.1.0" (10 pts)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_prepare_production_release(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function unavailable"}

    # 1. Load programmatic result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:/Users/Docker/task_results/task_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Criterion 1: Branch Creation
    if result.get('branch_exists'):
        score += 20
        feedback.append("Success: Branch 'release/v2.1' created.")
    else:
        feedback.append("Fail: Branch 'release/v2.1' not found.")

    # Criterion 2: Package Version
    if result.get('version_correct'):
        score += 20
        feedback.append("Success: package.json version updated to 2.1.0.")
    else:
        # Check debug content to give better feedback
        content = result.get('debug_package_content', 'empty')
        feedback.append(f"Fail: package.json version incorrect on release branch.")

    # Criterion 3: Config Environment
    if result.get('config_correct'):
        score += 20
        feedback.append("Success: app-config.json environment set to production.")
    else:
        feedback.append("Fail: app-config.json environment incorrect on release branch.")

    # Criterion 4: Pull Request
    if result.get('pr_created'):
        score += 30
        feedback.append("Success: Pull Request created from release branch to main.")
    else:
        feedback.append("Fail: No active Pull Request found linking release/v2.1 to main.")

    # Criterion 5: PR Metadata
    if result.get('pr_title_correct'):
        score += 10
        feedback.append("Success: PR title follows naming convention.")
    elif result.get('pr_created'):
        feedback.append("Partial Fail: PR exists but title does not contain 'Release v2.1.0'.")

    # Anti-gaming: VLM verification of trajectory
    # Ensure the user actually used the UI and didn't just run a script (if visible)
    # or to verify the "messiness" of the process (optional but good practice)
    
    # Calculate Final
    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }