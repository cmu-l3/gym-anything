#!/usr/bin/env python3
"""
Verifier for configure_staging_build_type task.

Scoring (100 points total):
1. Build Success (40 pts): ./gradlew assembleStaging completes and produces APK.
2. Build File Configuration (60 pts):
   - 'staging' build type defined (10 pts)
   - inherits from 'debug' (10 pts)
   - applicationIdSuffix correct (10 pts)
   - versionNameSuffix correct (10 pts)
   - buildConfigField correct (20 pts)
"""

import json
import logging
import os
import re
import tempfile

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

def verify_configure_staging_build_type(traj, env_info, task_info):
    """Verify the staging build type configuration."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from export_result.sh
    result = _read_json_from_env(copy_from_env, "/tmp/task_result.json")
    
    metadata = task_info.get("metadata", {})
    expected_url = metadata.get("expected_url", "https://staging.api.unscramble.com")
    
    score = 0
    feedback_parts = []
    
    # 1. Verify Build Success (40 pts)
    build_success = result.get("build_success", False)
    apk_created = result.get("apk_created", False)
    
    if build_success and apk_created:
        score += 40
        feedback_parts.append("Build 'assembleStaging' succeeded (40/40)")
    elif build_success:
        score += 30
        feedback_parts.append("Build command succeeded but APK not found (30/40)")
    else:
        feedback_parts.append("Build 'assembleStaging' failed (0/40)")
        # Check logs for hints
        log = result.get("gradle_log", "")
        if "Task 'assembleStaging' not found" in log:
            feedback_parts.append("Hint: 'staging' build type might not be defined correctly.")
            
    # 2. Verify File Content (60 pts)
    content = result.get("build_file_content", "")
    if not content:
        feedback_parts.append("Could not read build.gradle.kts (0/60)")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
        
    # Normalize content for regex
    # Remove comments to avoid false positives? Maybe overkill, simple regex is usually enough.
    
    # Check for staging block
    # Pattern looks for create("staging") or getByName("staging") or just staging {
    # In Kotlin DSL it's usually `create("staging")` inside `buildTypes`
    has_staging = False
    if re.search(r'create\s*\(\s*"staging"\s*\)', content) or \
       re.search(r'register\s*\(\s*"staging"\s*\)', content) or \
       re.search(r'named\s*\(\s*"staging"\s*\)', content): # If they configured existing, unlikely for new
        has_staging = True
    
    if has_staging:
        score += 10
        feedback_parts.append("Build type 'staging' defined (10/10)")
    else:
        feedback_parts.append("Build type 'staging' not found in build.gradle.kts (0/10)")
        
    # Check inheritance: initWith(getByName("debug"))
    if re.search(r'initWith\s*\(\s*getByName\s*\(\s*"debug"\s*\)\s*\)', content) or \
       re.search(r'initWith\s*\(\s*buildTypes\.getByName\s*\(\s*"debug"\s*\)\s*\)', content):
        score += 10
        feedback_parts.append("Inheritance from 'debug' configured (10/10)")
    else:
        feedback_parts.append("Missing inheritance from 'debug' (0/10)")
        
    # Check applicationIdSuffix
    if re.search(r'applicationIdSuffix\s*=\s*"\.staging"', content):
        score += 10
        feedback_parts.append("applicationIdSuffix correct (10/10)")
    else:
        feedback_parts.append("applicationIdSuffix missing or incorrect (0/10)")
        
    # Check versionNameSuffix
    if re.search(r'versionNameSuffix\s*=\s*"-STAGING"', content):
        score += 10
        feedback_parts.append("versionNameSuffix correct (10/10)")
    else:
        feedback_parts.append("versionNameSuffix missing or incorrect (0/10)")
        
    # Check buildConfigField
    # Expected: buildConfigField("String", "BASE_URL", "\"https://staging.api.unscramble.com\"")
    # Regex needs to be flexible with spaces
    # Note: Kotlin DSL syntax might vary slightly, but arguments are standard
    url_pattern = re.escape(expected_url)
    # Match buildConfigField("String", "BASE_URL", "...") where ... contains the url
    if re.search(r'buildConfigField\s*\(\s*"String"\s*,\s*"BASE_URL"\s*,\s*".*' + url_pattern + r'.*"\s*\)', content):
        score += 20
        feedback_parts.append("BuildConfig field BASE_URL correct (20/20)")
    else:
        feedback_parts.append("BuildConfig field BASE_URL missing or incorrect (0/20)")

    # Anti-gaming check: File modification
    file_modified = result.get("file_modified", False)
    if not file_modified and score > 0:
        score = 0
        feedback_parts = ["Anti-gaming: build.gradle.kts was not modified during the task."]

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }