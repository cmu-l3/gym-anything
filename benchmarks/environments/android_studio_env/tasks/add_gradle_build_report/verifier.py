#!/usr/bin/env python3
"""
Verifier for add_gradle_build_report task.

Verifies that:
1. The gradle task 'generateBuildReport' exists and runs successfully (exit code 0).
2. The output JSON file exists and was created during the task.
3. The JSON content matches expected values (applicationId, versions, etc.).
4. The implementation accesses build config properties (anti-hardcoding check).
"""

import json
import logging
import os
import re
import tempfile
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _read_json_from_env(copy_from_env, container_path: str) -> dict:
    """Copy a JSON file out of the container and return parsed dict."""
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env(container_path, tmp.name)
        with open(tmp.name, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except Exception as exc:
        logger.debug("Could not read JSON %s: %s", container_path, exc)
        return {}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

def verify_add_gradle_build_report(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load data
    result = _read_json_from_env(copy_from_env, "/tmp/task_result.json")
    ground_truth = _read_json_from_env(copy_from_env, "/tmp/ground_truth.json")

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # Criterion 1: Task Execution (20 pts)
    # ---------------------------------------------------------
    exit_code = result.get("task_exit_code", 1)
    if exit_code == 0:
        score += 20
        feedback_parts.append("Gradle task executed successfully (20/20)")
    else:
        feedback_parts.append(f"Gradle task failed (exit code {exit_code})")

    # ---------------------------------------------------------
    # Criterion 2: Output File Existence & Freshness (10 pts)
    # ---------------------------------------------------------
    output_exists = result.get("output_exists", False)
    fresh = result.get("file_created_during_task", False)
    
    if output_exists and fresh:
        score += 10
        feedback_parts.append("Report file created during task (10/10)")
    elif output_exists:
        score += 5
        feedback_parts.append("Report file exists but timestamp check failed (5/10)")
    else:
        feedback_parts.append("Report file not found")
        # Critical failure if no output
        if score < 20: 
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # ---------------------------------------------------------
    # Criterion 3: Content Validation (60 pts)
    # ---------------------------------------------------------
    # Parse the output content string back into a dict
    try:
        report_content = json.loads(result.get("output_content", "{}"))
    except json.JSONDecodeError:
        report_content = {}
        feedback_parts.append("Output file is not valid JSON")

    # Helper for checking fields
    def check_field(key, expected_val, points):
        actual = report_content.get(key)
        # Handle type conversion loosely
        if str(actual) == str(expected_val):
            return points, f"{key} correct"
        return 0, f"{key} mismatch (expected {expected_val}, got {actual})"

    # Check fields
    f_score = 0
    
    # Simple direct matches
    s, f = check_field("applicationId", ground_truth.get("applicationId"), 10)
    f_score += s; feedback_parts.append(f)
    
    s, f = check_field("versionName", ground_truth.get("versionName"), 7)
    f_score += s
    
    s, f = check_field("versionCode", ground_truth.get("versionCode"), 7)
    f_score += s
    
    s, f = check_field("minSdk", ground_truth.get("minSdk"), 8)
    f_score += s
    
    s, f = check_field("targetSdk", ground_truth.get("targetSdk"), 7)
    f_score += s
    
    s, f = check_field("compileSdk", ground_truth.get("compileSdk"), 7)
    f_score += s
    
    # Fuzzy matches
    # Java Version
    java_ver = str(report_content.get("javaVersion", ""))
    if "17" in java_ver:
        f_score += 4
        feedback_parts.append("javaVersion correct")
    else:
        feedback_parts.append(f"javaVersion mismatch (expected ~17, got {java_ver})")
        
    # Dependency Count
    dep_count = report_content.get("dependencyCount")
    min_deps = ground_truth.get("dependencyCount_min", 0)
    max_deps = ground_truth.get("dependencyCount_max", 100)
    if isinstance(dep_count, int) and min_deps <= dep_count <= max_deps:
        f_score += 5
        feedback_parts.append(f"dependencyCount reasonable ({dep_count})")
    else:
        feedback_parts.append(f"dependencyCount out of range ({dep_count})")
        
    # Timestamp
    ts = report_content.get("buildTimestamp", "")
    try:
        # Check if it parses as ISO or similar
        # Heuristic: verify it contains 2024 or 2025 or current year
        current_year = str(datetime.now().year)
        if current_year in ts or str(int(current_year)-1) in ts:
             f_score += 5
             feedback_parts.append("buildTimestamp valid")
        else:
             feedback_parts.append("buildTimestamp invalid")
    except:
        pass
        
    score += f_score

    # ---------------------------------------------------------
    # Criterion 4: Implementation Check (Anti-hardcoding) (10 pts)
    # ---------------------------------------------------------
    build_content = result.get("build_file_content", "")
    # Look for usage of properties rather than literals
    # We expect things like 'android.defaultConfig.applicationId' or similar
    # Simple heuristic: "task" definition and some accessors
    
    has_task = "tasks.register" in build_content or "task(" in build_content
    has_access = "android.defaultConfig" in build_content or "android.compileSdk" in build_content
    
    if has_task and has_access:
        score += 10
        feedback_parts.append("Implementation accesses build properties (10/10)")
    elif has_task:
        # Penalize if they just hardcoded the JSON write
        if '"applicationId": "com.example.todoapp"' in build_content:
             feedback_parts.append("Hardcoding detected (0/10)")
        else:
             score += 5
             feedback_parts.append("Implementation ambiguous (5/10)")

    passed = score >= 60 and exit_code == 0 and output_exists

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }