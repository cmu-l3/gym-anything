#!/usr/bin/env python3
"""
Verifier for clinical_app_evaluation_report task.

Scoring Breakdown (100 points total):
1. Infrastructure (20 pts): Created at least 2 distinct device types.
2. Exploration (30 pts): Launched at least 2 distinct clinical apps.
3. Interaction (5 pts): Window count increased significantly (active usage).
4. Report Existence (10 pts): File exists, correct path, created during task.
5. Report Quality (35 pts):
   - Mentions >1 app name (15 pts)
   - Uses clinical terminology (10 pts)
   - Includes recommendation/evaluation language (10 pts)

Pass Threshold: 60 points
Gate Condition: If <1 device created AND <1 app launched AND no report -> 0 points.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_clinical_app_evaluation(traj, env_info, task_info):
    # Use copy_from_env to retrieve the result JSON safely
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback_parts = []
    subscores = {}

    # Extract data from result
    devices_count = result.get('devices_detected_count', 0)
    apps_count = result.get('apps_launched_count', 0)
    window_increase = result.get('window_increase', 0)
    report_exists = result.get('report_exists', False)
    report_valid = result.get('report_valid_timestamp', False)
    report_size = result.get('report_size_bytes', 0)
    
    # GATE CHECK: Anti-gaming for passive agents
    # If agent did nothing meaningful (no devices, no apps, no report), fail immediately
    if devices_count == 0 and apps_count == 0 and not report_exists and window_increase < 3:
        return {
            "passed": False,
            "score": 0,
            "feedback": "GATE FAIL: No devices created, no apps launched, and no report found. Agent did not attempt task.",
            "subscores": {}
        }

    # 1. Infrastructure (Max 20 pts)
    # 10 pts per distinct device type created, up to 20
    dev_score = min(devices_count * 10, 20)
    score += dev_score
    subscores['infrastructure'] = dev_score
    if devices_count > 0:
        feedback_parts.append(f"Created {devices_count} device type(s)")
    else:
        feedback_parts.append("No devices created")

    # 2. Exploration (Max 30 pts)
    # 15 pts per distinct app launched, up to 30
    app_score = min(apps_count * 15, 30)
    score += app_score
    subscores['exploration'] = app_score
    if apps_count > 0:
        feedback_parts.append(f"Launched {apps_count} clinical app(s)")
    else:
        feedback_parts.append("No clinical apps launched")

    # 3. Interaction (Max 5 pts)
    # If window count increased significantly (>3), it implies active exploration
    # even if specific logs weren't caught
    if window_increase >= 3:
        score += 5
        subscores['interaction'] = 5
        feedback_parts.append("Active window interaction detected")
    else:
        subscores['interaction'] = 0

    # 4. Report Existence (Max 10 pts)
    # Must exist, be created during task, and have content
    if report_exists and report_valid and report_size >= 100:
        score += 10
        subscores['report_file'] = 10
        feedback_parts.append("Report file created successfully")
    elif report_exists:
        # Partial credit if it exists but is tiny or timestamp ambiguous
        score += 5
        subscores['report_file'] = 5
        feedback_parts.append("Report file exists but is empty or old")
    else:
        subscores['report_file'] = 0
        feedback_parts.append("Report file not found")

    # 5. Report Quality (Max 35 pts)
    # Only if report exists
    qual_score = 0
    if report_exists:
        # Mentions apps (15 pts) - scaling
        mentions = result.get('report_distinct_apps_mentioned', 0)
        if mentions >= 2:
            qual_score += 15
        elif mentions == 1:
            qual_score += 7
        
        # Clinical terms (10 pts)
        if result.get('report_has_clinical_terms', False):
            qual_score += 10
            
        # Recommendation (10 pts)
        if result.get('report_has_recommendation', False):
            qual_score += 10
            
        if qual_score > 0:
            feedback_parts.append(f"Report content quality score: {qual_score}/35")
    
    score += qual_score
    subscores['report_quality'] = qual_score

    # Final check
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "devices_list": result.get('devices_list', ''),
            "apps_list": result.get('apps_list', '')
        }
    }