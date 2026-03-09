#!/usr/bin/env python3
"""
Verifier for add_gradle_build_info_task.
"""

import json
import logging
import os
import tempfile
import re
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_gradle_build_info_task(traj, env_info, task_info):
    """
    Verify the agent added a functioning Gradle task to generate build-info.json.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from export_result.sh
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to load task result"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    metadata = task_info.get('metadata', {})
    score = 0
    feedback = []
    
    # 1. Task Definition in build.gradle.kts (15 pts)
    build_content = result.get("build_file_content", "")
    has_task_def = "generateBuildInfo" in build_content and ("tasks.register" in build_content or "tasks.create" in build_content)
    if has_task_def:
        score += 15
        feedback.append("Task definition found in build.gradle.kts (15/15)")
    else:
        feedback.append("Task definition NOT found in build.gradle.kts (0/15)")

    # 2. Gradle Task Execution (15 pts)
    # Did ./gradlew generateBuildInfo succeed?
    if result.get("task_run_success"):
        score += 15
        feedback.append("Gradle task runs successfully (15/15)")
    else:
        feedback.append("Gradle task execution failed (0/15)")

    # 3. JSON File Existence (10 pts)
    json_exists = result.get("json_file_exists")
    if json_exists:
        score += 10
        feedback.append("build-info.json generated (10/10)")
    else:
        feedback.append("build-info.json NOT generated (0/10)")

    # 4. Content Verification (5 pts validity + 40 pts fields)
    json_content_str = result.get("json_content", "")
    json_data = {}
    valid_json = False
    
    if json_exists and json_content_str:
        try:
            json_data = json.loads(json_content_str)
            valid_json = True
            score += 5
            feedback.append("File is valid JSON (5/5)")
        except json.JSONDecodeError:
            feedback.append("File is INVALID JSON (0/5)")

    if valid_json:
        # Check Version Name (8 pts)
        if json_data.get("versionName") == metadata.get("expected_version_name", "1.0.0"):
            score += 8
            feedback.append("versionName correct (8/8)")
        else:
            feedback.append(f"versionName incorrect: {json_data.get('versionName')} (0/8)")

        # Check Version Code (8 pts)
        # Handle string or int
        if str(json_data.get("versionCode")) == str(metadata.get("expected_version_code", 1)):
            score += 8
            feedback.append("versionCode correct (8/8)")
        else:
            feedback.append(f"versionCode incorrect: {json_data.get('versionCode')} (0/8)")

        # Check Min SDK (8 pts)
        if str(json_data.get("minSdk")) == str(metadata.get("expected_min_sdk", 24)):
            score += 8
            feedback.append("minSdk correct (8/8)")
        else:
            feedback.append(f"minSdk incorrect: {json_data.get('minSdk')} (0/8)")

        # Check Target SDK (8 pts)
        if str(json_data.get("targetSdk")) == str(metadata.get("expected_target_sdk", 34)):
            score += 8
            feedback.append("targetSdk correct (8/8)")
        else:
            feedback.append(f"targetSdk incorrect: {json_data.get('targetSdk')} (0/8)")

        # Check Build Timestamp (8 pts)
        # Just check if it looks like a timestamp/date
        ts = json_data.get("buildTimestamp", "")
        if ts and len(ts) > 10:
            score += 8
            feedback.append("buildTimestamp present (8/8)")
        else:
            feedback.append("buildTimestamp missing or invalid (0/8)")

        # Check Git Hash (8 pts)
        # Should match what we retrieved from the env
        expected_hash = result.get("git_hash", "").strip()
        actual_hash = json_data.get("gitCommitHash", "").strip()
        
        # Allow partial match (short vs long)
        if actual_hash and expected_hash and (actual_hash in expected_hash or expected_hash in actual_hash):
            score += 8
            feedback.append("gitCommitHash correct (8/8)")
        else:
             feedback.append(f"gitCommitHash mismatch (Expected approx {expected_hash}, got {actual_hash}) (0/8)")

    # 5. Task Wiring (7 pts)
    if result.get("is_wired"):
        score += 7
        feedback.append("Task wired to preBuild (7/7)")
    else:
        feedback.append("Task NOT wired to preBuild (0/7)")

    # 6. Anti-gaming check (File modified during task)
    if not result.get("build_file_modified"):
         feedback.append("WARNING: build.gradle.kts not modified during task time.")
         # We don't necessarily zero the score, but it's suspicious. 
         # However, if the json was created during task and correct, they likely did the work.

    passed = score >= 60 and result.get("task_run_success") and has_task_def

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }