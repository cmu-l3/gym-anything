#!/usr/bin/env python3
"""
Verifier for resolve_merge_conflicts task.

Scoring (100 points total):
1. Git Merge Completed (20 pts):
   - Git working tree is clean
   - A merge commit exists
2. Build.gradle Resolved (25 pts):
   - Contains 'MPAndroidChart'
   - Contains 'Retrofit'
   - No conflict markers (<<<<<<<, =======, >>>>>>>)
3. Layout XML Resolved (25 pts):
   - Contains 'LineChart'
   - Contains 'login_container' (LinearLayout)
   - No conflict markers
4. Project Builds (30 pts):
   - ./gradlew assembleDebug returns exit code 0

Pass threshold: 100 points (Strict: Conflict resolution must be perfect and buildable)
"""

import json
import logging
import os
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

def verify_resolve_merge_conflicts(traj, env_info, task_info):
    """Verify that merge conflicts were resolved and project builds."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    result = _read_json_from_env(copy_from_env, "/tmp/task_result.json")
    if not result:
        return {"passed": False, "score": 0, "feedback": "No result file generated"}

    # Extract data
    git_clean = result.get("git_status_clean", False)
    merge_exists = result.get("git_merge_commit_exists", False)
    build_success = result.get("build_success", False)
    gradle_content = result.get("gradle_content", "")
    layout_content = result.get("layout_content", "")

    score = 0
    feedback_parts = []

    # 1. Git Checks (20 pts)
    git_score = 0
    if git_clean:
        git_score += 10
    else:
        feedback_parts.append("Git working tree not clean")
        
    if merge_exists:
        git_score += 10
    else:
        feedback_parts.append("No merge commit found")
        
    score += git_score
    feedback_parts.append(f"Git Status: {git_score}/20")

    # 2. Gradle Content (25 pts)
    # Check for markers
    markers = ["<<<<<<<", "=======", ">>>>>>>"]
    has_markers = any(m in gradle_content for m in markers)
    
    # Check for required deps
    has_mpchart = "MPAndroidChart" in gradle_content
    has_retrofit = "retrofit" in gradle_content
    
    gradle_score = 0
    if not has_markers and gradle_content:
        if has_mpchart and has_retrofit:
            gradle_score = 25
            feedback_parts.append("Gradle file resolved correctly")
        elif has_mpchart:
            gradle_score = 10
            feedback_parts.append("Gradle missing Retrofit dependency")
        elif has_retrofit:
            gradle_score = 10
            feedback_parts.append("Gradle missing MPAndroidChart dependency")
        else:
            feedback_parts.append("Gradle missing both dependencies")
    else:
        feedback_parts.append("Gradle file contains conflict markers or is empty")
    
    score += gradle_score

    # 3. Layout Content (25 pts)
    has_layout_markers = any(m in layout_content for m in markers)
    has_chart = "LineChart" in layout_content
    has_login = "login_container" in layout_content
    
    layout_score = 0
    if not has_layout_markers and layout_content:
        if has_chart and has_login:
            layout_score = 25
            feedback_parts.append("Layout file resolved correctly")
        elif has_chart:
            layout_score = 10
            feedback_parts.append("Layout missing Login UI")
        elif has_login:
            layout_score = 10
            feedback_parts.append("Layout missing Chart UI")
        else:
            feedback_parts.append("Layout missing both UI elements")
    else:
        feedback_parts.append("Layout file contains conflict markers or is empty")
        
    score += layout_score

    # 4. Build Success (30 pts)
    if build_success:
        score += 30
        feedback_parts.append("Project builds successfully")
    else:
        feedback_parts.append("Project build failed")

    # Overall result
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }