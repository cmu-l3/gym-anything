#!/usr/bin/env python3
"""
Verifier for Detect Freezer Gaps task.

Checks:
1. Report file exists and contains valid JSON.
2. Report file was created during the task.
3. Feed ID matches the actual feed.
4. Gap start time is within tolerance (+/- 2 minutes).
5. Gap duration is within tolerance (+/- 2 minutes).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_detect_freezer_gaps(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Check if report exists
    if not result.get('report_exists'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Report file /home/ga/outage_report.json not found."
        }
    
    score += 10
    feedback_parts.append("Report file found (+10)")

    # 2. Check if created during task
    if result.get('report_created_during_task'):
        score += 10
        feedback_parts.append("Report created during task (+10)")
    else:
        feedback_parts.append("Warning: Report file timestamp predates task start")

    # Parse content
    report = result.get('report_content', {})
    truth = result.get('ground_truth', {})

    if not truth:
        return {"passed": False, "score": score, "feedback": "System Error: Ground truth missing"}

    # 3. Check Feed ID
    rep_feed_id = report.get('feed_id')
    true_feed_id = truth.get('feed_id')
    
    if str(rep_feed_id) == str(true_feed_id):
        score += 10
        feedback_parts.append(f"Feed ID matches ({rep_feed_id}) (+10)")
    else:
        feedback_parts.append(f"Feed ID incorrect. Expected {true_feed_id}, got {rep_feed_id}")

    # 4. Check Gap Start Time (Tolerance: +/- 120s)
    # The agent might pick the timestamp of the last valid point or first missing point.
    # We allow a small range.
    rep_start = report.get('gap_start_timestamp')
    true_start = truth.get('gap_start_timestamp')
    
    if rep_start is not None and isinstance(rep_start, (int, float)):
        diff = abs(rep_start - true_start)
        if diff <= 60:
            score += 35
            feedback_parts.append(f"Start time precise (diff {diff}s) (+35)")
        elif diff <= 300: # 5 mins
            score += 20
            feedback_parts.append(f"Start time approximate (diff {diff}s) (+20)")
        else:
            feedback_parts.append(f"Start time inaccurate (diff {diff}s, >5m tolerance)")
    else:
        feedback_parts.append("Start time missing or invalid format")

    # 5. Check Gap Duration (Tolerance: +/- 120s)
    rep_duration = report.get('gap_duration_seconds')
    true_duration = truth.get('gap_duration_seconds')
    
    if rep_duration is not None and isinstance(rep_duration, (int, float)):
        diff_d = abs(rep_duration - true_duration)
        if diff_d <= 60:
            score += 35
            feedback_parts.append(f"Duration precise (diff {diff_d}s) (+35)")
        elif diff_d <= 300:
            score += 15
            feedback_parts.append(f"Duration approximate (diff {diff_d}s) (+15)")
        else:
            feedback_parts.append(f"Duration inaccurate (diff {diff_d}s, >5m tolerance)")
    else:
        feedback_parts.append("Duration missing or invalid format")

    passed = score >= 85
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }