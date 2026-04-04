#!/usr/bin/env python3
"""
Verifier for migrate_groovy_to_kotlin_dsl task.
Verifies that Gradle build scripts were converted to Kotlin DSL and the project builds.
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

def verify_migration(traj, env_info, task_info):
    """Verify Gradle Groovy to Kotlin DSL migration."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    result = _read_json_from_env(copy_from_env, "/tmp/task_result.json")
    if not result:
        return {"passed": False, "score": 0, "feedback": "No result file found"}

    score = 0
    feedback_parts = []
    
    # 1. Check file existence (15 pts total)
    if result.get("settings_kts_exists"):
        score += 5
        feedback_parts.append("settings.gradle.kts created")
    else:
        feedback_parts.append("settings.gradle.kts missing")

    if result.get("root_build_kts_exists"):
        score += 5
        feedback_parts.append("root build.gradle.kts created")
    else:
        feedback_parts.append("root build.gradle.kts missing")

    if result.get("app_build_kts_exists"):
        score += 5
        feedback_parts.append("app/build.gradle.kts created")
    else:
        feedback_parts.append("app/build.gradle.kts missing")

    # 2. Check Groovy files removed (5 pts)
    if result.get("groovy_files_removed"):
        score += 5
        feedback_parts.append("Old Groovy files removed")
    else:
        feedback_parts.append("Old Groovy files still present")

    # 3. Check syntax correctness (40 pts)
    # Settings.gradle.kts
    settings_content = result.get("settings_content", "")
    if 'include(":app")' in settings_content or "include(\":app\")" in settings_content:
        score += 5
    if 'rootProject.name =' in settings_content:
        score += 5
    
    # Root build.gradle.kts
    root_content = result.get("root_build_content", "")
    # Check for `id("...")` syntax
    if re.search(r'id\s*\(\s*"[^"]+"\s*\)', root_content):
        score += 10
    
    # App build.gradle.kts
    app_content = result.get("app_build_content", "")
    # Check for assignment syntax `compileSdk =`
    if re.search(r'compileSdk\s*=\s*\d+', app_content):
        score += 5
    # Check for `implementation("...")`
    if re.search(r'implementation\s*\(\s*"[^"]+"\s*\)', app_content):
        score += 10
    # Check for no single quotes (rough heuristic for leftover Groovy)
    if "'" not in app_content and app_content.strip():
        score += 5

    # 4. Check Build Success (40 pts)
    if result.get("build_success"):
        score += 40
        feedback_parts.append("Build succeeded")
    else:
        feedback_parts.append("Build failed")

    # Cap score
    score = min(score, 100)
    passed = score >= 60 and result.get("build_success")

    return {
        "passed": passed,
        "score": score,
        "feedback": ", ".join(feedback_parts)
    }