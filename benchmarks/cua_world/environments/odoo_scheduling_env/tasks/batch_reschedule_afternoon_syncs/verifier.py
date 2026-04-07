#!/usr/bin/env python3
"""
Verifier for batch_reschedule_afternoon_syncs task.
"""

import json
import datetime
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_odoo_date(date_str):
    """Parse Odoo's datetime string format: 'YYYY-MM-DD HH:MM:SS'"""
    return datetime.datetime.strptime(date_str, '%Y-%m-%d %H:%M:%S')

def verify_batch_reschedule(traj, env_info, task_info):
    """
    Verify that all 'Sync' meetings after 12pm were moved to 9am.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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

    if 'error' in result:
        return {"passed": False, "score": 0, "feedback": f"Error during export: {result['error']}"}

    baseline = result.get('baseline', {})
    final_state = result.get('final_state', {})
    task_start_time = result.get('task_start_time', 0)

    score = 0
    feedback_parts = []
    
    # Define Targets
    target_1 = "Operations Daily Sync"
    target_2 = "Sales Pipeline Sync"
    control = "Weekly Team Kickoff"

    # --- Check Target 1: Operations Daily Sync ---
    if target_1 in final_state and target_1 in baseline:
        f_evt = final_state[target_1]
        b_evt = baseline[target_1]
        
        start_dt = parse_odoo_date(f_evt['start'])
        base_dt = parse_odoo_date(b_evt['initial_start'])
        
        # Criteria A: Hour is 9
        if start_dt.hour == 9 and start_dt.minute == 0:
            score += 30
            feedback_parts.append(f"'{target_1}' moved to 09:00.")
        else:
            feedback_parts.append(f"'{target_1}' time incorrect: {start_dt.strftime('%H:%M')}.")

        # Criteria B: Date preserved
        if start_dt.date() == base_dt.date():
            # Implicit points for keeping date, helps separate from date-change errors
            pass 
        else:
            score -= 10 # Penalty for changing date
            feedback_parts.append(f"'{target_1}' date changed (Wrong).")

        # Criteria C: Duration preserved
        if abs(f_evt['duration'] - b_evt['duration']) < 0.01:
            score += 10
            feedback_parts.append(f"'{target_1}' duration preserved.")
        else:
            feedback_parts.append(f"'{target_1}' duration changed.")

        # Anti-gaming: Modified after start
        write_date = parse_odoo_date(f_evt['write_date'])
        if write_date.timestamp() > task_start_time:
            pass # Good
        else:
            score = 0
            feedback_parts.append(f"ERROR: '{target_1}' not modified (stale timestamp).")
    else:
        feedback_parts.append(f"'{target_1}' not found in final state.")

    # --- Check Target 2: Sales Pipeline Sync ---
    if target_2 in final_state and target_2 in baseline:
        f_evt = final_state[target_2]
        b_evt = baseline[target_2]
        
        start_dt = parse_odoo_date(f_evt['start'])
        base_dt = parse_odoo_date(b_evt['initial_start'])
        
        if start_dt.hour == 9 and start_dt.minute == 0:
            score += 30
            feedback_parts.append(f"'{target_2}' moved to 09:00.")
        else:
            feedback_parts.append(f"'{target_2}' time incorrect: {start_dt.strftime('%H:%M')}.")

        if start_dt.date() != base_dt.date():
            score -= 10
            feedback_parts.append(f"'{target_2}' date changed (Wrong).")

        if abs(f_evt['duration'] - b_evt['duration']) < 0.01:
            score += 10
            feedback_parts.append(f"'{target_2}' duration preserved.")
        else:
            feedback_parts.append(f"'{target_2}' duration changed.")
            
        # Anti-gaming
        write_date = parse_odoo_date(f_evt['write_date'])
        if write_date.timestamp() <= task_start_time:
            score = 0
            feedback_parts.append(f"ERROR: '{target_2}' not modified.")
    else:
        feedback_parts.append(f"'{target_2}' not found.")

    # --- Check Control: Weekly Team Kickoff ---
    # Should NOT change
    if control in final_state and control in baseline:
        f_evt = final_state[control]
        b_evt = baseline[control]
        
        start_dt = parse_odoo_date(f_evt['start'])
        base_dt = parse_odoo_date(b_evt['initial_start'])
        
        if start_dt == base_dt:
            score += 20
            feedback_parts.append("Control event untouched.")
        else:
            feedback_parts.append("Control event modified (Penalty).")
    else:
        feedback_parts.append("Control event missing.")

    # Normalize score
    score = max(0, min(100, score))
    passed = (score >= 80)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }