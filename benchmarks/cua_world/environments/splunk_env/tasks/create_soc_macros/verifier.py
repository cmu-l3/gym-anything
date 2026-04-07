#!/usr/bin/env python3
"""Verifier for create_soc_macros task.

Validates that three specific Splunk search macros were created with the correct names,
argument counts, and SPL definition logic.

Scoring Criteria (100 points total, Pass Threshold: 60):
1. Macro 1 (auth_failures_by_ip) exists with 1 argument (20 points)
2. Macro 1 definition has valid logic (security_logs, fail, stats) (20 points)
3. Macro 2 (top_attackers) exists with 1 argument (10 points)
4. Macro 2 definition has valid logic (security_logs, fail, top/head/limit) (20 points)
5. Macro 3 (event_volume_trend) exists with 0 arguments (10 points)
6. Macro 3 definition has valid logic (timechart, >=2 indexes) (20 points)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def get_macro_data(base_name, current_macros):
    """Find a macro by base name, handling the (N) suffix in Splunk."""
    for name, data in current_macros.items():
        if name.lower().startswith(base_name.lower()):
            return name, data
    return None, None


def verify_create_soc_macros(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve exported results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/macro_results.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    initial_macros = result.get('initial_macros', [])
    current_macros = result.get('current_macros', {})
    
    score = 0
    feedback_parts = []
    
    # Check Macro 1: auth_failures_by_ip
    m1_name, m1_data = get_macro_data('auth_failures_by_ip', current_macros)
    if m1_name and m1_name not in initial_macros:
        # Check args
        args_str = str(m1_data.get('args', ''))
        if '(1)' in m1_name or (args_str and len(args_str.split(',')) == 1):
            score += 20
            feedback_parts.append("Macro auth_failures_by_ip exists with 1 arg")
            
            # Check definition
            m1_def = m1_data.get('definition', '').lower()
            if 'security_logs' in m1_def and 'fail' in m1_def and 'stats' in m1_def:
                score += 20
                feedback_parts.append("Macro auth_failures_by_ip definition logic is correct")
            else:
                feedback_parts.append("FAIL: auth_failures_by_ip missing required logic (needs 'security_logs', 'fail', and 'stats')")
        else:
            feedback_parts.append(f"FAIL: auth_failures_by_ip exists but does not have exactly 1 argument (found: {m1_name})")
    else:
        feedback_parts.append("FAIL: Macro auth_failures_by_ip not found or wasn't created during task")

    # Check Macro 2: top_attackers
    m2_name, m2_data = get_macro_data('top_attackers', current_macros)
    if m2_name and m2_name not in initial_macros:
        # Check args
        args_str = str(m2_data.get('args', ''))
        if '(1)' in m2_name or (args_str and len(args_str.split(',')) == 1):
            score += 10
            feedback_parts.append("Macro top_attackers exists with 1 arg")
            
            # Check definition
            m2_def = m2_data.get('definition', '').lower()
            valid_limit = 'top' in m2_def or 'head' in m2_def or 'limit' in m2_def
            if 'security_logs' in m2_def and 'fail' in m2_def and valid_limit:
                score += 20
                feedback_parts.append("Macro top_attackers definition logic is correct")
            else:
                feedback_parts.append("FAIL: top_attackers missing required logic (needs 'security_logs', 'fail', and 'top'/'head')")
        else:
            feedback_parts.append(f"FAIL: top_attackers exists but does not have exactly 1 argument (found: {m2_name})")
    else:
        feedback_parts.append("FAIL: Macro top_attackers not found or wasn't created during task")

    # Check Macro 3: event_volume_trend
    m3_name, m3_data = get_macro_data('event_volume_trend', current_macros)
    if m3_name and m3_name not in initial_macros:
        # Check args (should be 0)
        args_str = str(m3_data.get('args', ''))
        if '(0)' in m3_name or not args_str or m3_name == 'event_volume_trend':
            score += 10
            feedback_parts.append("Macro event_volume_trend exists with 0 args")
            
            # Check definition
            m3_def = m3_data.get('definition', '').lower()
            idx_count = sum(1 for idx in ['security_logs', 'web_logs', 'system_logs'] if idx in m3_def)
            if 'timechart' in m3_def and idx_count >= 2:
                score += 20
                feedback_parts.append("Macro event_volume_trend definition logic is correct")
            else:
                feedback_parts.append("FAIL: event_volume_trend missing logic (needs 'timechart' and >=2 target indexes)")
        else:
            feedback_parts.append(f"FAIL: event_volume_trend should have 0 arguments (found: {m3_name})")
    else:
        feedback_parts.append("FAIL: Macro event_volume_trend not found or wasn't created during task")

    # Pass condition
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }