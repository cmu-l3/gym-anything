#!/usr/bin/env python3
"""
Verifier for web_code_edit_with_work_item_linking task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_web_code_edit_with_work_item_linking(traj, env_info, task_info):
    """
    Verify that the agent updated the configuration files correctly and linked the commits.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Define paths
    remote_path = r"C:\Users\Docker\task_results\web_code_edit_result.json"
    
    # Copy result from VM
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env(remote_path, tmp.name)
        with open(tmp.name, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve task result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback_parts = []
    
    # Check 1: App Settings (30 pts)
    app_settings = result.get("app_settings", {})
    api_settings = app_settings.get("Api", {})
    
    if api_settings.get("ApiTimeoutSeconds") == 120:
        score += 15
        feedback_parts.append("ApiTimeoutSeconds correct (120)")
    else:
        feedback_parts.append(f"ApiTimeoutSeconds incorrect: {api_settings.get('ApiTimeoutSeconds')}")
        
    if api_settings.get("MaxRetryAttempts") == 3:
        score += 15
        feedback_parts.append("MaxRetryAttempts correct (3)")
    else:
        feedback_parts.append(f"MaxRetryAttempts incorrect: {api_settings.get('MaxRetryAttempts')}")

    # Check 2: Feature Flags (30 pts)
    feature_flags_json = result.get("feature_flags", {})
    feature_flags = feature_flags_json.get("FeatureFlags", {})
    
    if feature_flags.get("EnableCircuitBreaker") is True:
        score += 15
        feedback_parts.append("EnableCircuitBreaker correct (true)")
    else:
        feedback_parts.append(f"EnableCircuitBreaker incorrect: {feature_flags.get('EnableCircuitBreaker')}")
        
    if feature_flags.get("EnableRequestBuffering") is True:
        score += 15
        feedback_parts.append("EnableRequestBuffering correct (true)")
    else:
        feedback_parts.append(f"EnableRequestBuffering incorrect: {feature_flags.get('EnableRequestBuffering')}")

    # Check 3: Commits and Linking (40 pts)
    commits_since_start = result.get("commits_since_start", 0)
    linked_commits = result.get("linked_commit_count", 0)
    commit_messages = result.get("commit_messages", [])
    bug_id = str(result.get("bug_id", ""))

    # Check for commits
    if commits_since_start >= 2:
        score += 10
        feedback_parts.append(f"Found {commits_since_start} new commits")
    elif commits_since_start == 1:
        score += 5
        feedback_parts.append("Found only 1 new commit (expected separate commits)")
    else:
        feedback_parts.append("No new commits found")

    # Check for #ID in message
    has_id_ref = any(f"#{bug_id}" in msg for msg in commit_messages)
    if has_id_ref:
        score += 15
        feedback_parts.append(f"Commit message references bug #{bug_id}")
    else:
        feedback_parts.append(f"No commit message references bug #{bug_id}")

    # Check for actual linking (Azure DevOps auto-linking)
    if linked_commits >= 1:
        score += 15
        feedback_parts.append(f"Bug has {linked_commits} linked commits")
    else:
        feedback_parts.append("Bug has no linked commits (Development section)")

    # Pass threshold
    passed = score >= 60 and api_settings.get("ApiTimeoutSeconds") == 120 and feature_flags.get("EnableCircuitBreaker") is True
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }