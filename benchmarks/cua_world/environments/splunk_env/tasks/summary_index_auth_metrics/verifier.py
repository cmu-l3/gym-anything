#!/usr/bin/env python3
"""Verifier for summary_index_auth_metrics task.

Checks:
1. Index 'auth_summary' exists (20 pts)
2. Saved search 'Auth_Metrics_Collector' exists (20 pts)
3. Search SPL references 'security_logs' (15 pts)
4. Search SPL uses 'collect' targeting 'auth_summary' (15 pts)
5. Search is scheduled for every 4 hours (15 pts)
6. Summary index has >= 1 event, proving execution (15 pts)
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_summary_index_auth_metrics(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_index = metadata.get('expected_index_name', 'auth_summary').lower()
    source_index = metadata.get('source_index', 'security_logs').lower()

    # Copy result file from container
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

    analysis = result.get('analysis', {})
    if 'error' in analysis:
        return {"passed": False, "score": 0, "feedback": f"Export script error: {analysis['error']}"}

    score = 0
    feedback_parts = []
    
    index_exists = analysis.get('index_exists', False)
    search_exists = analysis.get('search_exists', False)
    search_spl = analysis.get('search_spl', '').lower()
    is_scheduled = analysis.get('is_scheduled', False)
    cron_schedule = analysis.get('cron_schedule', '').strip()
    event_count = analysis.get('event_count', 0)

    # Criterion 1: Index auth_summary exists
    if index_exists:
        score += 20
        feedback_parts.append("Index 'auth_summary' created")
    else:
        feedback_parts.append("FAIL: Index 'auth_summary' not found")

    # Criterion 2: Saved search Auth_Metrics_Collector exists
    if search_exists:
        score += 20
        feedback_parts.append("Saved search 'Auth_Metrics_Collector' created")
    else:
        feedback_parts.append("FAIL: Saved search 'Auth_Metrics_Collector' not found")

    # Criterion 3: Search SPL references security_logs
    if search_exists and source_index in search_spl:
        score += 15
        feedback_parts.append("Search correctly references 'security_logs'")
    elif search_exists:
        feedback_parts.append("FAIL: Search does not reference 'security_logs'")
    
    # Criterion 4: Search SPL uses collect targeting auth_summary
    has_collect = 'collect' in search_spl
    has_target = expected_index in search_spl
    
    if search_exists and has_collect and has_target:
        score += 15
        feedback_parts.append("Search correctly pipes to collect command targeting auth_summary")
    elif search_exists:
        feedback_parts.append(f"FAIL: Search SPL missing collect command or index target (SPL: {search_spl[:50]}...)")

    # Criterion 5: Search is scheduled every 4 hours
    # Acceptable patterns: */4 in hours, or 0,4,8,12,16,20
    is_4_hour_cron = False
    if is_scheduled and cron_schedule:
        parts = cron_schedule.split()
        if len(parts) >= 2:
            hour_part = parts[1]
            if '*/4' in hour_part or '0,4,8,12,16,20' in hour_part or '0, 4, 8, 12, 16, 20' in hour_part:
                is_4_hour_cron = True
                
    if is_4_hour_cron:
        score += 15
        feedback_parts.append(f"Cron correctly configured for 4 hours ({cron_schedule})")
    elif is_scheduled:
        feedback_parts.append(f"FAIL: Cron schedule '{cron_schedule}' is not set to every 4 hours")
    elif search_exists:
        feedback_parts.append("FAIL: Search is not scheduled")

    # Criterion 6: Summary index has data (execution verified)
    if event_count > 0:
        score += 15
        feedback_parts.append(f"Summary index populated with {event_count} events")
    else:
        feedback_parts.append("FAIL: Summary index is empty. Search was not executed.")

    # Pass threshold: Must get at least 60 points, which requires at least index + search + proper source reference
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "index_exists": index_exists,
            "search_exists": search_exists,
            "search_spl": search_spl,
            "is_scheduled": is_scheduled,
            "cron_schedule": cron_schedule,
            "event_count": event_count
        }
    }