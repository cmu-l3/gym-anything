#!/usr/bin/env python3
"""
Verifier for docker_image_versioning task.
Checks if the agent's build pipeline correctly injects Git metadata.

Scoring (100 pts):
1. Application Startup (20 pts): Container runs without crashing (implies ENVs are set).
2. Dynamic SHA Injection (25 pts): APP_REVISION matches the *audit* commit SHA (not hardcoded).
3. OCI Labels (15 pts): Standard OCI labels are present.
4. Build Script Success (15 pts): build.sh runs successfully.
5. Data Consistency (15 pts): API returns same SHA as git.
6. Branch/Date Metadata (10 pts): Branch info is correctly injected.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_docker_image_versioning(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Data from export
    expected_sha = result.get("expected_sha", "unknown")
    build_exit = result.get("build_exit_code", 1)
    app_starts = result.get("app_starts", False)
    
    env_rev = result.get("env_revision", "")
    env_branch = result.get("env_branch", "")
    
    lbl_rev = result.get("label_revision", "")
    lbl_created = result.get("label_created", "")
    lbl_source = result.get("label_source", "")
    
    api_rev = result.get("app_response_sha", "")
    
    # 1. Build Script Success (15 pts)
    if build_exit == 0:
        score += 15
        feedback.append("Build script ran successfully.")
    else:
        feedback.append("Build script failed to execute.")

    # 2. Application Startup (20 pts)
    # The app crashes on startup if ENVs are missing, so this proves ENVs exist
    if app_starts:
        score += 20
        feedback.append("Container started successfully (ENVs present).")
    else:
        feedback.append("Container failed to start (likely missing ENVs).")

    # 3. Dynamic SHA Injection (25 pts)
    # Must match the NEW commit created by verifier, preventing hardcoding
    sha_match = False
    if env_rev and (env_rev == expected_sha or expected_sha.startswith(env_rev)):
        sha_match = True
    
    if sha_match:
        score += 25
        feedback.append("Dynamic Git SHA injection verified.")
    else:
        feedback.append(f"SHA mismatch or hardcoded. Expected {expected_sha[:7]}, found '{env_rev}'.")

    # 4. OCI Labels (15 pts)
    labels_ok = 0
    if lbl_rev and (lbl_rev == expected_sha or expected_sha.startswith(lbl_rev)): labels_ok += 1
    if lbl_created: labels_ok += 1
    if lbl_source: labels_ok += 1
    
    if labels_ok == 3:
        score += 15
        feedback.append("All OCI labels present and correct.")
    elif labels_ok > 0:
        score += 5 * labels_ok
        feedback.append(f"Some OCI labels missing ({labels_ok}/3 found).")
    else:
        feedback.append("No correct OCI labels found.")

    # 5. Data Consistency (15 pts)
    # Does the API return the SHA we expect?
    if api_rev and (api_rev == expected_sha or expected_sha.startswith(api_rev)):
        score += 15
        feedback.append("API endpoint returns correct version metadata.")
    elif api_rev:
        feedback.append(f"API returned incorrect SHA: {api_rev}")

    # 6. Branch Metadata (10 pts)
    if env_branch and env_branch in result.get("expected_branch", "main"):
        score += 10
        feedback.append("Branch metadata correctly injected.")

    passed = score >= 60 and app_starts and sha_match

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }