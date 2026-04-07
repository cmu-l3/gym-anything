#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_debug_media_organizer(traj, env_info, task_info):
    """
    Verify fixes for media_organizer bugs:
    1. GPS Sign Error (30 pts)
    2. Date Parsing (30 pts)
    3. Unsafe File Overwrite (40 pts)
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    task_name = "debug_media_organizer"
    result_path = f"/tmp/{task_name}_result.json"

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".json") as tmp:
            tmp_path = tmp.name
        try:
            copy_from_env(result_path, tmp_path)
            with open(tmp_path, "r", encoding="utf-8-sig") as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    score = 0
    feedback_parts = []
    
    # 1. GPS Fix (30 pts)
    if result.get("gps_tests_passed", False):
        score += 30
        feedback_parts.append("GPS logic fixed (West/South handled)")
    else:
        feedback_parts.append("GPS logic failing tests")

    # 2. Date Fix (30 pts)
    if result.get("date_tests_passed", False):
        score += 30
        feedback_parts.append("Date parsing fixed (robust)")
    else:
        feedback_parts.append("Date parsing failing robustness tests")

    # 3. Overwrite Fix (40 pts)
    if result.get("overwrite_tests_passed", False):
        score += 40
        feedback_parts.append("Safe file move implemented (no data loss)")
    else:
        feedback_parts.append("Unsafe overwrite failing tests")

    # Verify pass threshold
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": ", ".join(feedback_parts)
    }