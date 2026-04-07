#!/usr/bin/env python3
"""
Verifier for ingest_forensic_logs task.

SCORING CRITERIA:
1. Configuration Correct (30 pts): ossec.conf has valid localfile block.
2. File Populated (20 pts): Target log file exists in container with content.
3. Alerts Indexed (50 pts): SQL Injection alerts found in Indexer for the file.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ingest_forensic_logs(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
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
    feedback = []
    
    # 1. Configuration Check (30 pts)
    config_exists = result.get('config_exists', False)
    config_format = result.get('config_format_correct', False)
    
    if config_exists:
        if config_format:
            score += 30
            feedback.append("Configuration correct (localfile block with apache format found).")
        else:
            score += 15
            feedback.append("Configuration found but log_format might be incorrect (expected 'apache').")
    else:
        feedback.append("No valid <localfile> configuration found in ossec.conf.")

    # 2. File Population Check (20 pts)
    file_exists = result.get('file_exists_in_container', False)
    line_count = int(result.get('file_line_count', 0))
    
    if file_exists and line_count > 5:
        score += 20
        feedback.append(f"Forensic log file populated correctly ({line_count} lines).")
    elif file_exists:
        score += 10
        feedback.append(f"Forensic log file exists but has few lines ({line_count}).")
    else:
        feedback.append("Forensic log file not found inside container.")

    # 3. Alerts Check (50 pts)
    indexer_results = result.get('indexer_results', {})
    alert_count = indexer_results.get('count', 0)
    alerts = indexer_results.get('alerts', [])
    
    sql_injection_found = False
    for alert in alerts:
        groups = alert.get('groups', [])
        # Rule 31103 is typically 'sql_injection' or 'web'
        if 'sql_injection' in groups or 'web' in groups:
            sql_injection_found = True
            break
            
    if alert_count > 0:
        if sql_injection_found:
            score += 50
            feedback.append(f"Success! {alert_count} alerts indexed, including SQL injection signatures.")
        else:
            score += 25
            feedback.append(f"Alerts found ({alert_count}), but specific SQL injection signature not confirmed.")
    else:
        feedback.append("No alerts found in Indexer matching the forensic file and attacker IP.")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }