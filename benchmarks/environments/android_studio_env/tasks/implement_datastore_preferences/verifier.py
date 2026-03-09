#!/usr/bin/env python3
"""
Verifier for implement_datastore_preferences task.

Scoring (100 points):
1. Dependency Added (10 pts): Check build.gradle.kts for `androidx.datastore:datastore-preferences`.
2. Keys Defined (10 pts): Check for `floatPreferencesKey` and `booleanPreferencesKey`.
3. Read Implementation (20 pts): Check for `map` and default values (1.0f, true).
4. Write Implementation (20 pts): Check for `edit` and `it[KEY] = value`.
5. Exception Handling (10 pts): Check for `catch` block handling IOException.
6. Tests Passed (30 pts): Based on gradle test execution.
"""

import json
import logging
import os
import re
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _read_json_from_env(copy_from_env, container_path):
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env(container_path, tmp.name)
        with open(tmp.name, "r") as f:
            return json.load(f)
    except Exception:
        return {}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

def verify_implement_datastore_preferences(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}

    result = _read_json_from_env(copy_from_env, "/tmp/task_result.json")
    
    score = 0
    feedback = []
    
    # 1. Dependency Check (10 pts)
    build_content = result.get("build_content", "")
    if "androidx.datastore:datastore-preferences" in build_content:
        score += 10
        feedback.append("Dependency added correctly.")
    else:
        feedback.append("DataStore dependency missing in build.gradle.kts.")

    # 2. Code Analysis
    repo_content = result.get("repo_content", "")
    
    # Keys (10 pts)
    has_float_key = "floatPreferencesKey" in repo_content
    has_bool_key = "booleanPreferencesKey" in repo_content
    if has_float_key and has_bool_key:
        score += 10
        feedback.append("Preference keys defined.")
    else:
        feedback.append("Missing preference key definitions.")

    # Read Logic (20 pts)
    # Check for usage of .map and returning 1.0f / true
    has_map = ".map" in repo_content
    has_defaults = "1.0f" in repo_content and "true" in repo_content
    if has_map and has_defaults:
        score += 20
        feedback.append("Read logic with defaults implemented.")
    elif has_map:
        score += 10
        feedback.append("Read logic partially implemented (check defaults).")
    else:
        feedback.append("Read logic missing (.map not found).")

    # Write Logic (20 pts)
    # Check for .edit
    if ".edit" in repo_content:
        score += 20
        feedback.append("Write logic implemented (.edit found).")
    else:
        feedback.append("Write logic missing (.edit not found).")

    # Exception Handling (10 pts)
    # Check for .catch and IOException
    if ".catch" in repo_content and "IOException" in repo_content:
        score += 10
        feedback.append("IOException handling implemented.")
    else:
        feedback.append("Missing IOException handling in Flows.")

    # 6. Test Results (30 pts)
    passed_tests = result.get("passed_tests", 0)
    failed_tests = result.get("failed_tests", 0)
    total_tests = result.get("total_tests", 0)
    
    # We expect 4 tests in the provided test file
    if passed_tests >= 4 and failed_tests == 0:
        score += 30
        feedback.append("All unit tests passed.")
    elif passed_tests > 0:
        # Partial credit for tests
        points = int((passed_tests / 4) * 30)
        score += points
        feedback.append(f"Some tests passed ({passed_tests}/{total_tests}).")
    else:
        feedback.append("Unit tests failed or did not run.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }