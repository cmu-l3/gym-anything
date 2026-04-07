#!/usr/bin/env python3
"""
Verifier for platform_readiness_certification task.
Scores the agent based on factual accuracy of the report and functional testing evidence.
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_platform_readiness(traj, env_info, task_info):
    """
    Verify the platform readiness certification report.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    ground_truth = result.get('ground_truth', {})
    activity = result.get('activity', {})
    report = result.get('report', {})
    content = report.get('content_preview', "").lower()
    
    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # SCORING CRITERIA
    # ---------------------------------------------------------

    # Criterion 1: Report Existence & Timing (10 pts)
    # Anti-gaming: must be written after task start
    if report.get('exists') and report.get('created_during_task') and report.get('size', 0) > 100:
        score += 10
        feedback_parts.append("Report created successfully")
    elif report.get('exists'):
        score += 5
        feedback_parts.append("Report exists but timing/size issues")
    else:
        feedback_parts.append("No report file found")
        # GATE CONDITION: If no report and no activity, fail immediately
        if activity.get('window_increase', 0) < 1:
            return {"passed": False, "score": 0, "feedback": "No report and no system interaction detected."}

    # Criterion 2: Java Version Accuracy (10 pts)
    java_gt = ground_truth.get('java_version', '').lower()
    # Relaxed match: check if major version matches (e.g., '17')
    java_major = java_gt.split('.')[0] if java_gt else "17"
    if java_gt in content or (java_major and f"java {java_major}" in content) or (java_major and f"jdk {java_major}" in content):
        score += 10
        feedback_parts.append("Java version correct")
    else:
        feedback_parts.append(f"Java version incorrect/missing (Expected ~{java_gt})")

    # Criterion 3: Gradle Version Accuracy (10 pts)
    gradle_gt = ground_truth.get('gradle_version', '').lower()
    if gradle_gt and gradle_gt in content:
        score += 10
        feedback_parts.append("Gradle version correct")
    else:
        feedback_parts.append(f"Gradle version incorrect/missing (Expected {gradle_gt})")

    # Criterion 4: DDS Implementation Identified (10 pts)
    # Look for keywords like 'rti', 'connext', 'opendds'
    dds_gt = ground_truth.get('dds_impl', '').lower()
    # Make a list of likely keywords based on what the script found
    dds_keywords = []
    if "rti" in dds_gt or "connext" in dds_gt:
        dds_keywords = ["rti", "connext"]
    elif "opendds" in dds_gt:
        dds_keywords = ["opendds"]
    elif "opensplice" in dds_gt or "vortex" in dds_gt:
        dds_keywords = ["opensplice", "vortex"]
    else:
        dds_keywords = ["dds"] # Generic fallback

    if any(k in content for k in dds_keywords):
        score += 10
        feedback_parts.append("DDS implementation identified")
    else:
        feedback_parts.append("DDS implementation incorrect/missing")

    # Criterion 5: Build Status (10 pts)
    build_exists = ground_truth.get('build_exists', False)
    # Check if report says "yes", "exists", "success", "pass" vs "no", "fail", "missing"
    positive_keywords = ["yes", "exist", "success", "pass", "present", "compiled"]
    negative_keywords = ["no", "fail", "missing", "not found", "error"]
    
    report_positive = any(k in content for k in positive_keywords)
    report_negative = any(k in content for k in negative_keywords)
    
    # If build exists, report should be positive. If not, negative.
    if build_exists and report_positive:
        score += 10
        feedback_parts.append("Build status correct")
    elif not build_exists and report_negative:
        score += 10
        feedback_parts.append("Build status correct")
    else:
        feedback_parts.append("Build status incorrect")

    # Criterion 6: Functional Tests - Device (15 pts)
    # Validated via logs OR window titles
    if activity.get('device_in_logs') or activity.get('device_window_visible'):
        score += 15
        feedback_parts.append("Device functional test passed")
    else:
        feedback_parts.append("No device creation detected")

    # Criterion 7: Functional Tests - App (15 pts)
    # Validated via logs OR window titles
    if activity.get('app_in_logs') or activity.get('app_window_visible'):
        score += 15
        feedback_parts.append("App functional test passed")
    else:
        feedback_parts.append("No app launch detected")

    # Criterion 8: Log Path & Activity (10 pts)
    # Check if they mentioned the log path (e.g., "logs", "openice.log", "/home/ga")
    if "log" in content and ("openice" in content or "/home/ga" in content):
        score += 10
        feedback_parts.append("Log file identified")
    else:
        feedback_parts.append("Log info missing")

    # Criterion 9: Overall Determination (10 pts)
    if "pass" in content or "fail" in content:
        score += 10
        feedback_parts.append("Determination present")
    else:
        feedback_parts.append("No PASS/FAIL determination")

    # ---------------------------------------------------------
    # FINAL SCORING
    # ---------------------------------------------------------
    
    # Pass threshold: 60
    # Must have report + one functional test to pass
    passed = (score >= 60) and report.get('exists') and (activity.get('device_in_logs') or activity.get('app_in_logs') or activity.get('window_increase') > 0)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "ground_truth": ground_truth,
            "report_analysis": {
                "exists": report.get('exists'),
                "java_match": java_gt in content,
                "gradle_match": gradle_gt in content
            }
        }
    }