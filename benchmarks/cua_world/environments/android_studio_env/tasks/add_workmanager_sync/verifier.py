#!/usr/bin/env python3
"""
Verifier for add_workmanager_sync task.

Scoring (100 points total):
1. WorkManager Dependency (15 pts): 'androidx.work:work-runtime-ktx' in build.gradle.kts
2. SyncWorker Class (25 pts):
   - Exists (10)
   - Extends Worker/CoroutineWorker (5)
   - doWork returns Result.success() (5)
   - Writes to SharedPreferences (5)
3. WeatherApplication Class (25 pts):
   - Exists (10)
   - Schedules PeriodicWorkRequest (5)
   - Constraints: NetworkType.CONNECTED (5)
   - Enqueue Unique Work (5)
4. Manifest Registration (10 pts): <application android:name=".WeatherApplication" ...>
5. Build Success (25 pts): ./gradlew assembleDebug returns 0

Anti-gaming:
- Checks if files were actually created (content non-empty)
- Requires build success to prove code validity
"""

import json
import logging
import os
import re
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _read_json_from_env(copy_from_env, container_path: str) -> dict:
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

def verify_add_workmanager_sync(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Read result exported by script
    result = _read_json_from_env(copy_from_env, "/tmp/task_result.json")
    if not result:
        return {"passed": False, "score": 0, "feedback": "Task result file not found or empty"}

    score = 0
    feedback_parts = []

    # 1. Check Dependency (15 pts)
    build_gradle = result.get("build_gradle_content", "")
    if "androidx.work:work-runtime-ktx" in build_gradle:
        score += 15
        feedback_parts.append("Dependency added (15/15)")
    else:
        feedback_parts.append("Missing 'work-runtime-ktx' dependency")

    # 2. Check SyncWorker (25 pts)
    worker_content = result.get("worker_content", "")
    if result.get("worker_exists") and worker_content:
        score += 10
        feedback_parts.append("SyncWorker file exists (10/10)")
        
        # Check implementation details
        if "CoroutineWorker" in worker_content or "Worker" in worker_content:
            score += 5
        else:
            feedback_parts.append("SyncWorker must extend Worker/CoroutineWorker")

        if "Result.success()" in worker_content:
            score += 5
        else:
            feedback_parts.append("doWork missing Result.success()")

        # Check SharedPreferences usage
        if "getSharedPreferences" in worker_content and "edit()" in worker_content:
            score += 5
        else:
            feedback_parts.append("Missing SharedPreferences logic in Worker")
    else:
        feedback_parts.append("SyncWorker.kt not found")

    # 3. Check WeatherApplication (25 pts)
    app_content = result.get("app_content", "")
    if result.get("app_exists") and app_content:
        score += 10
        feedback_parts.append("WeatherApplication file exists (10/10)")
        
        # Check scheduling logic
        if "PeriodicWorkRequest" in app_content or "PeriodicWorkRequestBuilder" in app_content:
            score += 5
        else:
            feedback_parts.append("Missing PeriodicWorkRequest")

        if "NetworkType.CONNECTED" in app_content:
            score += 5
        else:
            feedback_parts.append("Missing NetworkType.CONNECTED constraint")
            
        if "enqueueUniquePeriodicWork" in app_content:
            score += 5
        else:
            feedback_parts.append("Missing enqueueUniquePeriodicWork")
    else:
        feedback_parts.append("WeatherApplication.kt not found")

    # 4. Check Manifest (10 pts)
    manifest_content = result.get("manifest_content", "")
    if 'android:name=".WeatherApplication"' in manifest_content or 'android:name="com.example.weatherapp.WeatherApplication"' in manifest_content:
        score += 10
        feedback_parts.append("Manifest registered (10/10)")
    else:
        feedback_parts.append("Application not registered in Manifest")

    # 5. Check Build Success (25 pts)
    if result.get("build_success"):
        score += 25
        feedback_parts.append("Build Successful (25/25)")
    else:
        feedback_parts.append("Build Failed")

    return {
        "passed": score >= 60 and result.get("build_success"),
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }