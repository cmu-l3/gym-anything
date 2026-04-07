#!/usr/bin/env python3
"""
Verifier for the configure_custom_message_group task.

VERIFICATION STRATEGY:
1. Validates that the underlying raw `scmaster.cfg` file was correctly modified and includes 'RISK'.
2. Checks timestamp modification against the task start to prevent spoofing.
3. Examines the effective configuration (`--dump-config`) to prove SeisComP accurately parsed the configuration.
4. Confirms that `scmaster` successfully booted without failing/crashing from bad configuration syntax.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_custom_message_group(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Load exported result JSON from the container
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    task_start = result.get('task_start', 0)
    scmaster_running = result.get('scmaster_running', False)
    raw_content = result.get('raw_config_content', '')
    dump_content = result.get('dump_config_content', '')
    config_mtime = result.get('config_mtime', 0)

    # Validate raw file inclusion
    has_risk_raw = 'RISK' in raw_content
    
    # Parse effective configuration dump strictly to ensure SeisComP accepts it as part of the intended queue
    # Format typically: queues.production.groups = AMPLITUDE, PICK, ..., RISK
    has_risk_dump = False
    for line in dump_content.split('\n'):
        if line.strip().startswith('queues.production.groups'):
            # Extract just the comma-separated group values
            groups_val = line.split('=', 1)[1]
            groups = [g.strip() for g in groups_val.split(',')]
            if 'RISK' in groups:
                has_risk_dump = True
                break

    file_modified = config_mtime > task_start

    # CRITERION 1: Service Lifecycle (30 points)
    if scmaster_running:
        score += 30
        feedback_parts.append("Service Check: scmaster is running cleanly")
    else:
        feedback_parts.append("Service Check: FAIL - scmaster is crashed or not restarted")

    # CRITERION 2: Actual File Modification (30 points)
    if has_risk_raw:
        if file_modified:
            score += 30
            feedback_parts.append("File Check: Config updated with RISK group during task")
        else:
            # File has RISK but wasn't modified after setup (agent found workaround/gaming check)
            score += 10
            feedback_parts.append("File Check: Config has RISK group but mtime check implies pre-existing")
    else:
        feedback_parts.append("File Check: RISK group not found in raw scmaster.cfg")

    # CRITERION 3: Effective Configuration Processing (40 points)
    if has_risk_dump:
        score += 40
        feedback_parts.append("Parse Check: RISK group successfully loaded into effective configuration")
    else:
        feedback_parts.append("Parse Check: FAIL - RISK group NOT found in running effective configuration")

    # Final threshold requirements
    key_criteria_met = scmaster_running and has_risk_dump
    passed = score >= 80 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }