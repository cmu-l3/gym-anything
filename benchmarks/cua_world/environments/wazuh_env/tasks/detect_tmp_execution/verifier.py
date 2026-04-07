#!/usr/bin/env python3
"""
Verifier for detect_tmp_execution task.
Checks for:
1. Custom rule 100150 in local_rules.xml
2. Replay log configuration in ossec.conf
3. Alert 100150 generation in alerts.json
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_detect_tmp_execution(traj, env_info, task_info):
    """
    Verify the Wazuh rule creation and testing task.
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

    score = 0
    feedback_parts = []
    
    # 1. Check Rule Existence & Logic (40 points)
    rules_content = result.get('local_rules_content', '')
    rule_id_pattern = r'id="100150"'
    
    # Simple regex checks for key components
    has_rule_id = re.search(rule_id_pattern, rules_content)
    has_level_12 = re.search(r'level="12"', rules_content)
    has_tmp_check = re.search(r'/tmp|/var/tmp', rules_content)
    
    if has_rule_id:
        score += 20
        feedback_parts.append("Rule 100150 found")
        
        if has_level_12:
            score += 5
            feedback_parts.append("Correct severity level")
        else:
            feedback_parts.append("Incorrect severity level (expected 12)")
            
        if has_tmp_check:
            score += 15
            feedback_parts.append("Rule logic checks for /tmp directories")
        else:
            feedback_parts.append("Rule logic missing /tmp path check")
    else:
        feedback_parts.append("Rule 100150 NOT found in local_rules.xml")

    # 2. Check Ingestion Configuration (20 points)
    ossec_conf = result.get('ossec_conf_content', '')
    # Look for <localfile> block containing replay.log
    # Regex handles potential whitespace/newlines
    ingest_pattern = r'<localfile>[\s\S]*?<location>/root/replay\.log</location>[\s\S]*?</localfile>'
    
    if re.search(ingest_pattern, ossec_conf):
        score += 20
        feedback_parts.append("Log ingestion configured for replay.log")
    else:
        feedback_parts.append("Log ingestion NOT configured for replay.log")

    # 3. Check Alert Generation (40 points)
    alerts_content = result.get('alerts_json_content', '')
    
    # We look for a JSON object with rule id 100150
    # Since alerts.json is line-delimited JSON
    alert_triggered = False
    triggered_count = 0
    
    for line in alerts_content.splitlines():
        if '100150' in line:
            try:
                alert_data = json.loads(line)
                rule_id = str(alert_data.get('rule', {}).get('id', ''))
                if rule_id == '100150':
                    alert_triggered = True
                    triggered_count += 1
            except json.JSONDecodeError:
                continue

    if alert_triggered:
        score += 40
        feedback_parts.append(f"Alert 100150 triggered successfully ({triggered_count} times)")
    else:
        feedback_parts.append("No alerts found for rule 100150 (did you ingest the data?)")

    # Anti-gaming: Check if data was actually written to replay.log
    replay_size = result.get('replay_log_size', 0)
    task_start = result.get('task_start', 0)
    replay_mtime = result.get('replay_log_mtime', 0)
    
    if replay_size == 0 or replay_mtime < task_start:
        feedback_parts.append("Warning: replay.log was not modified during the task")
        # If they somehow got alerts without modifying the file (unlikely but possible via injection),
        # we might still respect it, but usually this indicates failure to follow instructions.
        if score > 60:
            score -= 10 # Penalty for not following "replay" instruction

    passed = score >= 60 and alert_triggered
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }