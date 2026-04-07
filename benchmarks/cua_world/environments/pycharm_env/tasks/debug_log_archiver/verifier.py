#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_debug_log_archiver(traj, env_info, task_info):
    """
    Verify the fix for the log archiver.
    
    Scoring:
    - Bug 1 (Data Safety): 35 pts (test_archive_failure_preserves_source passed)
    - Bug 2 (Disk Space): 30 pts (test_check_disk_space_* passed + shutil.disk_usage used)
    - Bug 3 (Regex/ISO Dates): 20 pts (test_discover_iso_dates passed)
    - Integrity/Full Pass: 15 pts (All 15 tests pass)
    
    Pass Threshold: 85/100
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}
        
    task_name = "debug_log_archiver"
    result_path = f"/tmp/{task_name}_result.json"
    
    # Load result
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".json") as tmp:
            tmp_path = tmp.name
        try:
            copy_from_env(result_path, tmp_path)
            with open(tmp_path, "r") as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
        
    score = 0
    feedback = []
    
    # 1. Data Safety Fix (35 pts)
    # This is the most critical bug (data loss).
    if result.get("test_safety_pass", False):
        score += 35
        feedback.append("CRITICAL FIX: Data safety logic fixed (source preserved on failure).")
    else:
        feedback.append("FAIL: Source file is still deleted when archiving fails!")
        
    # 2. Disk Space Check (30 pts)
    # Requires implementing the function and passing tests.
    if result.get("test_disk_pass", False) and result.get("disk_check_implemented", False):
        score += 30
        feedback.append("Disk space validation implemented correctly.")
    elif result.get("test_disk_pass", False):
        # Passed tests but maybe didn't use shutil (weird?)
        score += 25
        feedback.append("Disk space tests passed, but implementation check ambiguous.")
    else:
        feedback.append("FAIL: Disk space validation tests failing.")
        
    # 3. Regex Fix (20 pts)
    if result.get("test_regex_pass", False):
        score += 20
        feedback.append("Regex updated to support ISO-8601 dates.")
    else:
        feedback.append("FAIL: ISO-8601 date discovery failed.")
        
    # 4. Overall Integrity (15 pts)
    tests_passed = result.get("tests_passed", 0)
    tests_total = result.get("tests_total", 0)
    
    if tests_total > 0 and tests_passed == tests_total:
        score += 15
        feedback.append("All tests passed.")
    else:
        feedback.append(f"Test suite incomplete: {tests_passed}/{tests_total} passed.")
        
    passed = score >= 85
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }