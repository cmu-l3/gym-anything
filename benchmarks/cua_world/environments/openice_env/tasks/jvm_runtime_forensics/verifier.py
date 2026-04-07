#!/usr/bin/env python3
"""
Verifier for JVM Runtime Forensics Task.

Verifies:
1. Files existence and timestamp (Anti-gaming).
2. Content validity (Regex patterns).
3. Report quality (Keywords, Tuning recommendations).
4. Correct Process ID targeting.
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_jvm_forensics(traj, env_info, task_info):
    # 1. Setup access to result file
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Initialize Scoring
    score = 0
    feedback_parts = []
    
    # Files data
    files = result.get("files", {})
    report_content = result.get("report_content", "").lower()
    
    # 3. Verify Diagnostic Files (40 Points)
    # 10 points per file if it exists, has content, created during task, and matches pattern
    diagnostic_files = ["file_heap_stats.txt", "file_thread_dump.txt", "file_jvm_config.txt", "file_heap_summary.txt"]
    
    files_captured_count = 0
    
    for fname in diagnostic_files:
        f_data = files.get(fname, {})
        display_name = fname.replace("file_", "")
        
        if f_data.get("exists") and f_data.get("size", 0) > 50:
            if f_data.get("created_during_task"):
                if f_data.get("pattern_matched"):
                    score += 10
                    files_captured_count += 1
                    feedback_parts.append(f"✅ {display_name} valid")
                else:
                    score += 5
                    feedback_parts.append(f"⚠️ {display_name} exists but content looks wrong")
            else:
                feedback_parts.append(f"❌ {display_name} timestamp too old (pre-existing?)")
        else:
            feedback_parts.append(f"❌ {display_name} missing or empty")

    # 4. Verify PID Targeting (10 Points)
    # Did the agent find the actual OpenICE PID?
    if result.get("pid_found_in_files"):
        score += 10
        feedback_parts.append("✅ Correct PID analyzed")
    else:
        feedback_parts.append("⚠️ Could not verify correct PID in files")

    # 5. Verify Report Quality (50 Points)
    report_data = files.get("file_performance_report.txt", {})
    
    if report_data.get("exists") and report_data.get("size", 0) > 100 and report_data.get("created_during_task"):
        score += 10 # Base points for report existence
        
        # Check for PID mention in text
        if "pid" in report_content or result.get("ground_truth_pid", "99999") in report_content:
            score += 5
            feedback_parts.append("✅ Report mentions PID")
            
        # Check for Memory/Heap metrics
        if any(x in report_content for x in ["mb", "gb", "%", "heap", "usage", "utilization"]):
            score += 10
            feedback_parts.append("✅ Report analyzes memory")
            
        # Check for Thread analysis
        if any(x in report_content for x in ["thread", "runnable", "waiting", "blocked", "state"]):
            score += 10
            feedback_parts.append("✅ Report analyzes threads")
            
        # Check for Tuning Recommendations
        # Looking for flags (-Xmx, -XX) or words like "recommend", "suggest", "increase", "tuning"
        if any(x in report_content for x in ["-xmx", "-xx:", "g1gc", "parallelgc", "increase heap", "tuning", "recommend"]):
            score += 15
            feedback_parts.append("✅ Report provides tuning recommendations")
        else:
            feedback_parts.append("⚠️ Report lacks clear tuning recommendations")
    else:
        feedback_parts.append("❌ Performance report missing or invalid")

    # 6. Final Status
    app_running = result.get("app_running", False)
    if not app_running:
        score = max(0, score - 20) # Penalty for crashing the app
        feedback_parts.append("⚠️ Penalty: OpenICE application is no longer running")

    # Pass Threshold: 60 points + Report Exists + At least 2 diagnostic files
    pass_threshold = 60
    passed = (score >= pass_threshold) and (files_captured_count >= 2) and (report_data.get("exists"))

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }