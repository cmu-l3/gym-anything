#!/usr/bin/env python3
"""
Verifier for configure_proguard_r8 task.

Checklist:
1. `minifyEnabled true` in build.gradle (15 pts)
2. `shrinkResources true` in build.gradle (10 pts)
3. ProGuard rules for Gson models (20 pts)
4. ProGuard rules for Gson annotations (15 pts)
5. ProGuard rules for Retrofit interfaces (10 pts)
6. Release build succeeds (20 pts)
7. Release APK exists (5 pts)
8. Files modified (5 pts)

Total: 100
"""

import json
import logging
import os
import re
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_proguard(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Read result JSON
    tmp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", tmp_file.name)
        with open(tmp_file.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(tmp_file.name):
            os.unlink(tmp_file.name)

    score = 0
    feedback = []

    # 1. Check build.gradle configuration
    bg_content = result.get("build_gradle_content", "")
    
    # Check minifyEnabled
    # Regex handles: isMinifyEnabled = true OR minifyEnabled true
    if re.search(r'(isMinifyEnabled\s*=\s*true|minifyEnabled\s+true)', bg_content):
        score += 15
        feedback.append("minifyEnabled set to true (15/15)")
    else:
        feedback.append("minifyEnabled NOT set to true (0/15)")

    # Check shrinkResources
    if re.search(r'(isShrinkResources\s*=\s*true|shrinkResources\s+true)', bg_content):
        score += 10
        feedback.append("shrinkResources set to true (10/10)")
    else:
        feedback.append("shrinkResources NOT set to true (0/10)")

    # 2. Check ProGuard Rules
    pg_content = result.get("proguard_content", "")
    
    # Check Model package rules
    # Look for: -keep class com.example.weathernow.data.model.**
    if "com.example.weathernow.data.model" in pg_content and "-keep" in pg_content:
        score += 20
        feedback.append("Model package keep rules found (20/20)")
    else:
        feedback.append("Model package keep rules missing (0/20)")

    # Check Gson annotations rule
    # Look for: @SerializedName or similar
    if "SerializedName" in pg_content or "com.google.gson.annotations" in pg_content:
        score += 15
        feedback.append("Gson annotation keep rules found (15/15)")
    else:
        feedback.append("Gson annotation keep rules missing (0/15)")

    # Check Retrofit interface rule
    # Look for: WeatherApiService or package data.api
    if ("WeatherApiService" in pg_content or "com.example.weathernow.data.api" in pg_content) and "-keep" in pg_content:
        score += 10
        feedback.append("Retrofit interface keep rules found (10/10)")
    else:
        feedback.append("Retrofit interface keep rules missing (0/10)")

    # 3. Check Build Status
    if result.get("build_success", False):
        score += 20
        feedback.append("Release build succeeded (20/20)")
    else:
        feedback.append("Release build failed (0/20)")

    # 4. Check APK
    if result.get("apk_created", False) and result.get("apk_size", 0) > 0:
        score += 5
        feedback.append("Release APK created (5/5)")
    else:
        feedback.append("Release APK not found (0/5)")

    # 5. Anti-gaming (Modification check)
    if result.get("build_gradle_modified", False) and result.get("proguard_modified", False):
        score += 5
        feedback.append("Files modified during task (5/5)")
    else:
        feedback.append("Files not modified (0/5)")

    passed = score >= 60 and result.get("build_success", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }