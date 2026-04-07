#!/usr/bin/env python3
"""Verifier for dynamic_anomaly_detection task.

Verification Criteria (20 points each, Total 100):
1. Alert created with exactly the name "Statistical_Web_Error_Spike" (or close enough variant if it's the only one).
2. The SPL query targets the "web_logs" index.
3. The SPL query uses advanced statistical commands (eventstats/streamstats, avg, stdev/stdevp).
4. The SPL query applies a dynamic 2-sigma bound (uses 'where', '2', and '*').
5. The alert is configured with a schedule (cron).
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

POINTS_PER_CRITERION = 20
PASS_THRESHOLD = 60

def normalize_name(name):
    """Normalize alert name for comparison."""
    return name.lower().replace(' ', '_').replace('-', '_')

def verify_dynamic_anomaly_detection(traj, env_info, task_info):
    """Verify that the agent built a dynamic anomaly detection alert."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Extract metadata
    metadata = task_info.get('metadata', {})
    expected_alert_name = metadata.get('expected_alert_name', 'Statistical_Web_Error_Spike')
    expected_index = metadata.get('expected_index', 'web_logs')
    expected_name_normalized = normalize_name(expected_alert_name)

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/dynamic_anomaly_detection_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    analysis = result.get('analysis', {})
    new_searches = analysis.get('new_searches', [])
    found_target_alert = analysis.get('found_target_alert', False)
    target_alert_data = analysis.get('target_alert_data', {})
    
    score = 0
    feedback_parts = []
    subscores = {}

    # Find the best candidate alert if the exact name wasn't matched
    candidate = None
    if found_target_alert:
        candidate = target_alert_data
    elif len(new_searches) > 0:
        # Agent made an alert but named it wrong, evaluate the first one to give partial credit
        candidate = new_searches[-1]

    # Criterion 1: Alert exists (with correct name)
    if found_target_alert:
        score += POINTS_PER_CRITERION
        feedback_parts.append(f"Alert '{candidate['name']}' created successfully")
        subscores['alert_exists'] = True
    elif candidate:
        # Partial credit if they created something but named it wrong
        score += (POINTS_PER_CRITERION // 2)
        feedback_parts.append(f"Alert created but named incorrectly: '{candidate['name']}' instead of '{expected_alert_name}'")
        subscores['alert_exists'] = False
    else:
        feedback_parts.append(f"FAIL: No new scheduled alerts or saved searches were created")
        subscores['alert_exists'] = False
        return {
            "passed": False, 
            "score": 0, 
            "feedback": " | ".join(feedback_parts), 
            "subscores": subscores
        }

    search_query = candidate.get('search', '').lower()

    # Criterion 2: Queries web logs
    if expected_index in search_query:
        score += POINTS_PER_CRITERION
        feedback_parts.append(f"Query references '{expected_index}'")
        subscores['queries_web_logs'] = True
    else:
        feedback_parts.append(f"FAIL: Query does not reference '{expected_index}'")
        subscores['queries_web_logs'] = False

    # Criterion 3: Uses statistical functions
    has_stats_cmd = 'eventstats' in search_query or 'streamstats' in search_query
    has_avg = 'avg' in search_query or 'mean' in search_query
    has_stdev = 'stdev' in search_query or 'stdevp' in search_query
    
    if has_stats_cmd and has_avg and has_stdev:
        score += POINTS_PER_CRITERION
        feedback_parts.append("Query uses required statistical functions (eventstats/streamstats, avg, stdev)")
        subscores['uses_statistical_functions'] = True
    else:
        feedback_parts.append("FAIL: Query missing required statistical math (requires eventstats/streamstats, avg, and stdev)")
        subscores['uses_statistical_functions'] = False

    # Criterion 4: Applies 2-sigma dynamic bound
    # Checks for 'where' clause, the multiplier '2', and multiplication '*'
    has_where = 'where' in search_query
    has_two = '2' in search_query
    has_mult = '*' in search_query

    if has_where and has_two and has_mult:
        score += POINTS_PER_CRITERION
        feedback_parts.append("Query dynamically filters outliers using 2-sigma bound")
        subscores['applies_2_sigma_bound'] = True
    else:
        feedback_parts.append("FAIL: Query does not correctly apply the 2 * stdev threshold (missing 'where', '2', or '*')")
        subscores['applies_2_sigma_bound'] = False

    # Criterion 5: Alert is scheduled
    is_scheduled = candidate.get('is_scheduled', False)
    has_cron = bool(candidate.get('cron_schedule', '').strip())
    
    if is_scheduled and has_cron:
        score += POINTS_PER_CRITERION
        feedback_parts.append(f"Alert is scheduled (cron: {candidate.get('cron_schedule')})")
        subscores['alert_is_scheduled'] = True
    else:
        feedback_parts.append("FAIL: Alert is not scheduled or missing cron expression")
        subscores['alert_is_scheduled'] = False

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "evaluated_alert": candidate.get('name', ''),
            "search_query_preview": candidate.get('search', '')[:200],
            "cron_schedule": candidate.get('cron_schedule', '')
        }
    }