#!/usr/bin/env python3
"""
Verifier for session_hijacking_detection task.

Verifies the alert existence, scheduling, and logical components of the SPL query.
Uses independent signals to award partial credit up to 100 points.
Pass threshold is 60 points.
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def check_scope(search_text, expected_keywords):
    """Checks if the search targets the correct dataset (tutorial index, web logs, etc)."""
    search_lower = search_text.lower()
    return any(kw in search_lower for kw in expected_keywords)


def check_session_grouping(search_text, session_keywords):
    """Checks if the search aggregates or groups by a session identifier."""
    search_lower = search_text.lower()
    return any(kw in search_lower for kw in session_keywords)


def check_hijacking_logic(search_text):
    """
    Checks if the search applies the core heuristic:
    Distinct count of IPs > 1 per session.
    """
    search_lower = search_text.lower()
    
    # Needs a distinct count or mvcount function
    has_count_func = any(fn in search_lower for fn in ['dc(', 'dc ', 'distinct_count', 'mvcount'])
    
    # Needs a threshold check strictly greater than 1
    has_threshold = bool(re.search(r'[><=]\s*1', search_lower)) or bool(re.search(r'>\s*0', search_lower))
    
    return has_count_func and has_threshold


def verify_session_hijacking_detection(traj, env_info, task_info):
    """
    Evaluates the agent's Splunk Alert configuration.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_alert_name = metadata.get('expected_alert_name', 'Session_Hijacking_Alert')
    expected_index_keywords = metadata.get('expected_index_keywords', ['tutorial', 'web', 'access'])
    expected_session_keywords = metadata.get('expected_session_keywords', ['jsessionid', 'session', 'cookie'])

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

    alert_analysis = result.get('alert_analysis', {})
    score = 0
    feedback_parts = []
    
    found_alert = alert_analysis.get('found_alert', False)
    alert_name = alert_analysis.get('alert_name', '')
    alert_search = alert_analysis.get('alert_search', '')
    is_scheduled = alert_analysis.get('is_scheduled', False)

    # CRITERION 1: Alert exists (20 pts)
    # Give full points if exact name matches, partial if they just created *any* new search that looks right
    if found_alert:
        if alert_name.lower() == expected_alert_name.lower():
            score += 20
            feedback_parts.append(f"Alert created with exact name '{alert_name}'")
        else:
            score += 10
            feedback_parts.append(f"Alert created but name mismatch (got '{alert_name}', expected '{expected_alert_name}')")
    else:
        feedback_parts.append("FAIL: No valid alert or saved search was created")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # CRITERION 2: Is Scheduled (20 pts)
    if is_scheduled:
        score += 20
        feedback_parts.append("Alert is successfully scheduled")
    else:
        feedback_parts.append("FAIL: Alert is not scheduled")

    # CRITERION 3: Targeted Scope (20 pts)
    if check_scope(alert_search, expected_index_keywords):
        score += 20
        feedback_parts.append("Search scopes correct index/data")
    else:
        feedback_parts.append("FAIL: Search does not seem to target web or tutorial logs")

    # CRITERION 4: Session Grouping (20 pts)
    if check_session_grouping(alert_search, expected_session_keywords):
        score += 20
        feedback_parts.append("Search properly groups by session ID")
    else:
        feedback_parts.append("FAIL: Search is missing session identifier grouping")

    # CRITERION 5: Hijacking Logic (20 pts)
    if check_hijacking_logic(alert_search):
        score += 20
        feedback_parts.append("Search correctly applies distinct IP > 1 heuristic")
    else:
        feedback_parts.append("FAIL: Search is missing distinct count logic or threshold filter")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "alert_name": alert_name,
            "search_query_preview": alert_search[:150]
        }
    }