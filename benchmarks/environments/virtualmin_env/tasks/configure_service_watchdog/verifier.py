#!/usr/bin/env python3
"""
Verifier for configure_service_watchdog task.

Checks:
1. Scheduled monitoring is enabled in Webmin.
2. Schedule interval is set to 5 minutes.
3. A MySQL/MariaDB monitor exists.
4. The monitor has the correct restart command configured.
5. The monitor has the correct description.
6. Configuration files were modified during the task window.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_service_watchdog(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON from container
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

    score = 0
    feedback_parts = []
    
    # Metadata targets
    metadata = task_info.get('metadata', {})
    expected_interval = str(metadata.get('expected_interval', '5'))
    expected_cmd_part = "systemctl restart mariadb"
    alt_cmd_part = "service mariadb restart"
    
    task_start = result.get('task_start_time', 0)
    
    # 1. Scheduled Monitoring Enabled (25 pts)
    # sched_mode=1 means enabled
    if str(result.get('sched_mode', '0')) == '1':
        score += 25
        feedback_parts.append("Scheduled monitoring enabled")
    else:
        feedback_parts.append("Scheduled monitoring NOT enabled")

    # 2. Correct Interval (15 pts)
    actual_int = str(result.get('sched_int', '0'))
    if actual_int == expected_interval:
        score += 15
        feedback_parts.append(f"Interval set to {actual_int} min")
    else:
        feedback_parts.append(f"Interval incorrect ({actual_int} min, expected {expected_interval})")

    # 3. MySQL Monitor Exists (20 pts)
    if result.get('monitor_found', False):
        score += 20
        feedback_parts.append("MySQL monitor created")
        
        # 4. Restart Command Configured (25 pts)
        cmd = result.get('monitor_cmd', '').lower()
        if expected_cmd_part in cmd or alt_cmd_part in cmd:
            score += 25
            feedback_parts.append("Restart command correct")
        else:
            feedback_parts.append(f"Restart command incorrect (found: '{cmd}')")
            
        # 5. Description Matches (5 pts)
        desc = result.get('monitor_desc', '')
        if "mariadb watchdog" in desc.lower():
            score += 5
            feedback_parts.append("Description correct")
        else:
            feedback_parts.append("Description mismatch")
            
        # 6. Anti-Gaming / Timestamp Check (10 pts)
        # Check if the monitor file was created/modified after task start
        monitor_mtime = result.get('monitor_mtime', 0)
        config_mtime = result.get('config_mtime', 0)
        
        if monitor_mtime > task_start or config_mtime > task_start:
            score += 10
            feedback_parts.append("Configuration modified during task")
        else:
            feedback_parts.append("No configuration changes detected during task window")
            
    else:
        feedback_parts.append("No MySQL monitor found")

    # Calculate final status
    # Must have at least enabled monitoring AND created the specific monitor to pass
    passed = (str(result.get('sched_mode')) == '1') and result.get('monitor_found', False) and score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }