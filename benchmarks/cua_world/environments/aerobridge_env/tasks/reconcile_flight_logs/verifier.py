#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reconcile_flight_logs(traj, env_info, task_info):
    """
    Verify the flight log reconciliation task.
    
    Scoring:
    - 40 pts: Correctly linked valid logs (Log 1 -> Plan 1, Log 2 -> Plan 2)
    - 30 pts: Correctly ignored outlier log (Log 3 -> None)
    - 30 pts: Outlier log ID reported in text file
    """
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
    feedback = []
    
    ids = result.get('ids', {})
    if not ids:
        return {"passed": False, "score": 0, "feedback": "Setup data missing, cannot verify."}

    # 1. Check Matching Logs (40 pts)
    # Log 1 should match Plan 1
    if result['log_1_actual_plan'] == ids['plan_1_id']:
        score += 20
        feedback.append("Log 1 matched correctly.")
    elif result['log_1_actual_plan'] is None:
        feedback.append("Log 1 is still orphaned.")
    else:
        feedback.append(f"Log 1 linked to WRONG plan {result['log_1_actual_plan']}.")

    # Log 2 should match Plan 2
    if result['log_2_actual_plan'] == ids['plan_2_id']:
        score += 20
        feedback.append("Log 2 matched correctly.")
    elif result['log_2_actual_plan'] is None:
        feedback.append("Log 2 is still orphaned.")
    else:
        feedback.append(f"Log 2 linked to WRONG plan {result['log_2_actual_plan']}.")

    # 2. Check Outlier Log (30 pts)
    # Log 3 should remain None (or not linked to Plan 1 or 2)
    if result['log_3_actual_plan'] is None:
        score += 30
        feedback.append("Outlier Log 3 correctly left unlinked.")
    else:
        feedback.append("Outlier Log 3 was incorrectly linked to a plan!")

    # 3. Check Report File (30 pts)
    report_content = result.get('report_content', '')
    log_3_id = str(ids['log_3_id'])
    
    if result['report_exists'] and log_3_id in report_content:
        score += 30
        feedback.append("Outlier Log 3 ID found in report file.")
    elif result['report_exists']:
        feedback.append(f"Report file exists but Log 3 ID ({log_3_id}) not found.")
    else:
        feedback.append("Report file not created.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }